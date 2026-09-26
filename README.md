# FlymeAuthTokenFix

> 一个 LSPosed / Xposed 模块，修复魅族 Flyme 系统 `AccountManagerService` 的 **getAuthToken 频控缺陷** —— 该缺陷会导致 GitHub Mobile 等依赖系统账户体系的应用被强制掉登。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](#许可)
![Platform](https://img.shields.io/badge/platform-LSPosed%20%7C%20Xposed-green)
![minSdk](https://img.shields.io/badge/minSdk-26-orange)

---

## 目录

- [问题现象](#问题现象)
- [根因分析](#根因分析)
- [修复原理](#修复原理)
- [安装与使用](#安装与使用)
- [自行构建](#自行构建)
- [仓库结构](#仓库结构)
- [兼容性与已知限制](#兼容性与已知限制)
- [免责声明](#免责声明)
- [许可](#许可)

---

## 问题现象

在搭载 Flyme（Android 14 / API 34 基线，机型实测为魅族设备）的系统上：

1. 打开 **GitHub Mobile**（`com.github.android`）时，已登录的账户被强制登出，跳回 `SimplifiedLoginActivity`；
2. 反复重新登录后，短时间内会**再次**掉登，形成"登录 → 秒掉 → 再登录"的死循环；
3. 掉登发生时，`logcat` 中 `AccountManagerService` 会打印告警：

   ```
   W/AccountManagerService: getAuthToken too frequently: <authTokenType>
   ```

  并向调用方回传 `onError(ERROR_CODE_CANCELED, "getAuthToken too frequently")`。

问题不是 GitHub Mobile 独有的 —— 任何**高频轮询 `AccountManager.getAuthToken()`** 的应用都会踩到，只是 GitHub Mobile 的 OAuth 流程（`net.openid.appauth` + `SimplifiedLoginActivity`）触发得最稳定、最容易复现。

## 根因分析

### 官方实现

AOSP 的 `AccountManagerService.getAuthToken()` 本身**没有任何频控逻辑**，你可以在 [AOSP 源码](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/base/services/core/java/com/android/server/accounts/AccountManagerService.java) 中逐行核对。

### Flyme 的私有改动

魅族在 `com.android.server.accounts.AccountManagerService` 中**私加了两个字段和一段节流逻辑**。反编译后的 smali 见 [`docs/flyme_account_manager_service.smali`](docs/flyme_account_manager_service.smali)：

```smali
# 距上次调用 < 500ms 则累加计数，否则清零
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J
move-result-wide v3
iget-wide v14, v0, Lcom/android/server/accounts/AccountManagerService;->mLastRetryTime:J
sub-long/2addr v3, v14
const-wide/16 v14, 0x1f4          # 500ms
cmp-long v3, v3, v14
if-gez v3, :cond_8d
    iget v3, v0, Lcom/android/server/accounts/AccountManagerService;->mRetryCount:I
    add-int/2addr v3, v1
    iput v3, v0, Lcom/android/server/accounts/AccountManagerService;->mRetryCount:I
    goto :goto_8f
:cond_8d
    iput v2, v0, Lcom/android/server/accounts/AccountManagerService;->mRetryCount:I   # 清零

:goto_8f
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J
move-result-wide v3
iput-wide v3, v0, Lcom/android/server/accounts/AccountManagerService;->mLastRetryTime:J

# 计数 >= 10 → 直接拒绝
iget v3, v0, Lcom/android/server/accounts/AccountManagerService;->mRetryCount:I
const/16 v4, 0xa                   # 10
if-lt v3, v4, :cond_b6
    # Slog.w("AccountManagerService", "getAuthToken too frequently: " + authTokenType)
    # response.onError(ERROR_CODE_CANCELED, "getAuthToken too frequently")
    return-void
```

**规则可以浓缩成一句话：500ms 内 ≥ 10 次 `getAuthToken` 调用，第 10 次起一律拒绝。**

### 缺陷在哪

问题不在节流本身，而在它的**两个设计错误**：

| 问题 | 说明 |
| --- | --- |
| **计数器是"粘性"的** | 原意是"500ms 内超 10 次就拦"，但 `mRetryCount` 只在**两次调用间隔 ≥ 500ms** 时才清零。持续高频调用的应用（间隔 < 500ms 的连续轮询）计数会一直累积，永远不会归零 —— 于是退化成"全局累计 10 次就永久封禁"。 |
| **粒度过粗且跨进程共享** | `mRetryCount` / `mLastRetryTime` 是 **Service 单例上的两个字段**，不区分调用方 uid、account、`authTokenType`。一个应用的轮询会**污染同一时间窗内所有其他应用/账户**的配额。 |

`ERROR_CODE_CANCELED`（= 4）是 `AccountManager` 语义为"用户取消操作"的错误码。OAuth 客户端（尤其 `net.openid.appauth`）收到这个码时，会把它当作**认证流程被用户取消 / 凭证失效**，进而清理本地凭据 → 表现为强制掉登。

> `docs/logcat_evidence.log` 记录了掉登前后的系统日志切片（69 个关键触发点，含 `SimplifiedLoginActivity` 被反复拉起的 `ActivityTaskManager` / `WindowManager` 轨迹）。

## 修复原理

模块把钩子挂在 `AccountManagerService` 的**所有** `getAuthToken` 重载上，在**方法执行前**把两个私有字段重置：

```java
for (Method method : amsClass.getDeclaredMethods()) {
    if ("getAuthToken".equals(method.getName())) {
        XposedBridge.hookMethod(method, new XC_MethodHook() {
            @Override
            protected void beforeHookedMethod(MethodHookParam param) {
                // 清零计数器 + 把"上次调用时间"推到远古，使下次间隔判断必然 >= 500ms
                XposedHelpers.setIntField(param.thisObject, "mRetryCount", 0);
                XposedHelpers.setLongField(param.thisObject, "mLastRetryTime", 0L);
            }
        });
    }
}
```

`★ Insight ─────────────────────────────────────`
**为什么把 `mLastRetryTime` 设为 `0` 而不只是清零计数器？**

Flyme 的判断是 `elapsedRealtime() - mLastRetryTime < 500`。`SystemClock.elapsedRealtime()` 在设备启动后从 0 递增，正常运行时是数十万到数亿毫秒。把它设为 `0` 会让差值恒为 `elapsedRealtime()`，**必然 ≥ 500**（开机 500ms 之后）——等价于"假装上次调用发生在无限久之前"，从源头让 `:cond_8d` 分支永远命中、计数永远清零。这比"每帧只重置计数"更稳：即使钩子被跳过几次，残留状态也会被下一次调用自动纠正。

**为什么用 `setIntField`/`setLongField` 而不是反射硬取？**

魅族不同 Flyme 版本的字段名/类型可能微调。`XposedHelpers.setIntField` 在字段缺失时抛 `NoSuchFieldError`，代码里用 `try/catch` 静默吞掉并记日志 —— 保证在未知机型变体上**降级为"钩子无效"而不是直接崩溃 system_server**。这一点对系统级 App 的模块至关重要。
`─────────────────────────────────────────────────`

### 为什么要 hook 全部重载

`AccountManagerService.getAuthToken` 有多个重载（带/不带 `Bundle options`）。Flyme 的频控加在**每一个**重载的开头，因此模块遍历 `getDeclaredMethods()` 按方法名全量匹配，避免漏网。

## 安装与使用

**前置条件**

- 已 Root 且安装 **LSPosed**（推荐）或经典 Xposed（`xposedminversion=93`）
- Android 8.0+（`minSdkVersion 26`）
- 设备为 Flyme 系统

**步骤**

1. 下载 / 构建 `FlymeAuthTokenFix.apk` 并安装；
2. 在 LSPosed 管理器中启用模块；
3. **作用域**勾选：
   - `android`（系统框架，`system_server` 进程 —— 钩子实际生效的地方）
   - `com.github.android`（GitHub Mobile，用于注入确认日志）
4. **重启系统框架**（LSPosed 里对 `android` 作用域需要重启 system_server，或直接重启设备）；
5. 用 `logcat` 验证：

   ```bash
   adb logcat -s LSPosed-Bridge | grep FlymeAuthFix
   # 期望看到（数字因系统版本而异）：
   # [FlymeAuthFix] Successfully hooked N getAuthToken methods in AccountManagerService!
   # [FlymeAuthFix] Injected into com.github.android successfully!
   ```

   只要钩到的重载数 ≥ 1 即表示生效；`com.github.android` 的注入日志仅在选中该作用域时出现。

## 自行构建

仓库**不含**预编译产物，请本地构建。

### 依赖

| 依赖 | 说明 |
| --- | --- |
| JDK | 需 `javac` / `java` / `keytool`（已验证 JDK 17 可用） |
| Android SDK | 需 `platforms/android-XX/android.jar` 与 `build-tools/<ver>/lib/{d8.jar,apksigner.jar}` |
| `aapt2` | 见下方三种模式 |
| `zip` | 打包 `classes.dex` / `assets` |

### 一键构建

```bash
./build.sh
# 产物：bin/FlymeAuthTokenFix.apk
```

脚本会自动探测 SDK 位置（依次尝试 `$ANDROID_SDK`、`$ANDROID_SDK_ROOT`、`$ANDROID_HOME`、`~/Android/Sdk`、`/opt/android-sdk`、`/usr/lib/android-sdk`、`/mnt/c/Android`），并挑选**最高版本**的 `build-tools` 与 `platforms`。

可用环境变量覆盖：

```bash
ANDROID_SDK=/path/to/sdk BUILD_TOOLS_VER=35.0.0 PLATFORM_VER=android-36 ./build.sh
```

### aapt2 的三种模式

脚本按 `native` → `winexe` → `path` 顺序择优，必要时会打印当前模式：

| 模式 | 场景 | 说明 |
| --- | --- | --- |
| `native` | SDK 内含宿主平台原生 `aapt2` | 最理想，版本与 build-tools 严格同源 |
| `winexe` | **WSL 下** SDK 只有 `aapt2.exe` | 经 `cmd.exe` 调用 Windows 版；项目位于 UNC 路径（如 `\\wsl.localhost\...`）时借 `pushd` 的自动盘符映射绕过 cmd 的 UNC 限制 |
| `path` | `PATH` 中有 `aapt2` | 兜底。⚠️ 发行版包（如 Debian 的 `2.19-debian`）往往远旧于 SDK，可能无法解析新版 `android.jar` |

> 在 WSL 上遇到 `error: failed to load include path .../android.jar`，说明落到了 `path` 模式。解决办法：安装与 SDK 同源的 `aapt2` 到 build-tools，或确保 `path` 中不出现旧版 `aapt2`。

### 构建流程

```
javac (源码 → bin/classes)
  └─ 删除 de/robv/android/xposed/**（编译期桩类，不打包）
d8    (bin/classes → classes.dex)
aapt2 compile  (src/main/res → bin/res_compiled/res.zip)
aapt2 link     (manifest + res.zip → bin/unaligned.apk)
zip   (追加 classes.dex、assets/xposed_init)
apksigner sign (bin/FlymeAuthTokenFix.apk，调试密钥首次自动生成)
```

### 关于 Xposed 桩类（`src/main/java/de/robv/android/xposed/`）

这些是 **compileOnly 桩**：仅用于让 `javac` 通过类型检查，源码里都是空实现。构建第 2 步会把整个 `de/` 目录从产物中剔除，运行时由 Xposed 框架注入真实实现。这样仓库无需引入任何二进制依赖。

### 关于调试签名

`build.sh` 首次运行会在 `bin/debug.keystore` 生成调试密钥（口令 `android`，别名 `androiddebugkey`），该目录已被 `.gitignore` 排除。**调试签名的 APK 无法覆盖安装他人签名的同包名应用**，如需长期使用请自行替换为固定密钥。

## 仓库结构

```
.
├── AndroidManifest.xml              # 模块声明：xposedmodule / xposedscope(见 res)
├── build.sh                         # 一键构建（跨 Linux / WSL 自适应）
├── src/main/
│   ├── assets/xposed_init           # Xposed 入口类全限定名
│   ├── res/values/
│   │   ├── arrays.xml               # xposed_scope：android + com.github.android
│   │   └── strings.xml
│   └── java/
│       ├── top/takotsubo/flyme/authtokenfix/MainHook.java   # 核心钩子逻辑
│       └── de/robv/android/xposed/                          # compileOnly 桩类（不打包）
└── docs/
    ├── flyme_account_manager_service.smali   # Flyme 频控逻辑反编译片段
    ├── github_mobile_logout_trigger.smali    # GitHub Mobile 掉登触发点
    └── logcat_evidence.log                   # 掉登现场日志切片
```

## 兼容性与已知限制

- **仅针对 Flyme**。AOSP / 其他 OEM ROM 无此私有频控逻辑，装上也只是空转（`setIntField` 抛异常后被静默忽略）。
- 依赖 `com.android.server.accounts.AccountManagerService` 的**私有字段名** `mRetryCount` / `mLastRetryTime`。若某 Flyme 版本改名，模块会**静默失效**（不会崩溃），请提 Issue 并附 `adb shell dumpsys account` 与反编译片段。
- 通过清除频控换取可用性，**理论上会放大异常应用的轮询压力**。若你在意功耗，可考虑把 `beforeHookedMethod` 改为更保守的策略（例如只在 `mRetryCount >= 8` 时才重置）。
- 已在 Android 14 / API 34 基线的 Flyme 上实测；其他版本未验证。

## 免责声明

本模块通过修改系统进程内存中的字段实现修复，属于**非官方行为**。请自行评估风险，务必先做好数据备份、并确保有可用的救砖手段。作者不对任何数据丢失或设备故障负责。

## 许可

[MIT](LICENSE)
