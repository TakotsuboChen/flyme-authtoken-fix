# FlymeAuthTokenFix

> 一个 LSPosed / Xposed 模块，修复魅族 Flyme 系统 `AccountManagerService` 的 **getAuthToken 频控缺陷** —— 该缺陷会导致 GitHub Mobile 等依赖系统账户体系的应用被强制掉登。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](#许可)
![Platform](https://img.shields.io/badge/platform-LSPosed%20%7C%20Xposed-green)
![API](https://img.shields.io/badge/libxposed%20API-102-brightgreen)
![minSdk](https://img.shields.io/badge/minSdk-26-orange)

---

## 目录

- [问题现象](#问题现象)
- [根因分析](#根因分析)
- [修复原理](#修复原理)
- [性能设计](#性能设计)
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
// ModuleEntry.FieldResetter#intercept —— libxposed API 102 拦截器
@Override
public Object intercept(XposedInterface.Chain chain) throws Throwable {
    Object ams = chain.getThisObject();
    try {
        retryCount.setInt(ams, 0);          // 计数器清零
        lastRetryTime.setLong(ams, 0L);     // "上次调用时间"推到远古
    } catch (Throwable ignored) {
        // 静默降级：宁可钩子失效，也不干扰 system_server 原流程
    }
    return chain.proceed();
}
```

`★ Insight ─────────────────────────────────────`
**为什么把 `mLastRetryTime` 设为 `0` 而不只是清零计数器？**

Flyme 的判断是 `elapsedRealtime() - mLastRetryTime < 500`。`SystemClock.elapsedRealtime()` 在设备启动后从 0 递增，正常运行时是数十万到数亿毫秒。把它设为 `0` 会让差值恒为 `elapsedRealtime()`，**必然 ≥ 500**（开机 500ms 之后）——等价于"假装上次调用发生在无限久之前"，从源头让 `:cond_8d` 分支永远命中、计数永远清零。这比"每帧只重置计数"更稳：即使钩子被跳过几次，残留状态也会被下一次调用自动纠正。

**为什么安装期缓存 `Field` 句柄而不是每帧按名查找？**

旧实现用 `XposedHelpers.setIntField(obj, "mRetryCount", 0)`，每次调用都要按名字符串做一次字段查找 + 字符串比较。`getAuthToken` 位于 `system_server` 的热路径上，这个成本被放大到每一次 OAuth 轮询。新实现把 `getDeclaredField` + `setAccessible(true)` 提到安装期做一次，热路径只剩两次直接的字段写（跳过访问检查）。这也顺带治好了旧实现的一个语义问题：按名查找失败会**抛异常**，异常在 `system_server` 里是昂贵的（栈填充 + 构造），而且必须靠 `try/catch` 兜住。

**为什么字段缺失时仍然注册空实现 hook，而不是干脆不注册？**

旧版与新版都坚持"降级为钩子无效，绝不崩溃 `system_server`"。新版选择注册一个 `NoopHooker`（仅 `proceed()` 转发）而不适直接跳过注册，是因为：其一，代价只是一次可被 JIT 完全内联的分支判断；其二，它让"字段是否解析成功"这件事被写进日志（`fieldsReady=false`），比静默不装更好诊断；其三，hook 句柄在 API 102 下可用同一个 id 原子替换，运行期若补齐字段仍有修正余地。
`─────────────────────────────────────────────────`

### 为什么要 hook 全部重载

`AccountManagerService.getAuthToken` 有多个重载（带/不带 `Bundle options`）。Flyme 的频控加在**每一个**重载的开头，因此模块遍历 `getDeclaredMethods()` 按方法名全量匹配，避免漏网。

## 性能设计

本模块的拦截器运行在 `system_server`，属于全局热路径，因此按"安装期做昂贵的事、热路径只做最少的活"来分层：

| 阶段 | 成本 | 做什么 |
| --- | --- | --- |
| `onModuleLoaded()` | 一次性 | 记录 API / 框架 / 进程信息用于诊断 |
| `onSystemServerStarting()` | 一次性 | `loadClass`、解析 2 个 `Field` 并 `setAccessible`、扫描 `getDeclaredMethods()`、注册 hook |
| **拦截器热路径** | **每次调用** | **2 次字段写（`setInt` / `setLong`）+ 1 次 `chain.proceed()`** |

热路径的硬性约束：

- **零分配** —— 不使用可变参数、不构造对象、不拼字符串；
- **零异常** —— 字段写包在 `try/catch` 内；正常路径下不产生也不依赖任何检查型异常；
- **零符号查找** —— 不做 `getDeclaredField(name)`、不做字符串比较、不做 `Class.forName`；
- **静态常量已内联** —— `TAG`、类名、方法名、字段名均为 `static final String`，但只在安装期使用，不进热路径。

另外，`HookBuilder.setPriority(PRIORITY_HIGHEST)` 让本模块的拦截器排在同方法上其他模块之前执行 —— 越早重置，节流判断越不可能在别的 hook 里先跑一遍。

安装完成后日志里会带出实测耗时，便于在真机上核对：

```text
[FlymeAuthFix] event=hooked result=ok count=2/2 fieldsReady=true cost_us=820
```

## 安装与使用

**前置条件**

- 已 Root 且安装**支持 libxposed API 102 的 LSPosed**（LSPosed 2.x / JingMatrix Vector 等）；
- Android 8.0+（`minSdkVersion 26`）；
- 设备为 Flyme 系统。

> ⚠️ 本模块是**现代 API 模块**，APK 内不含旧版 `xposedmodule` meta-data 与 `assets/xposed_init`。
> 若框架只实现旧版 API 82/93，模块列表里**根本不会出现它**（不会崩溃、不会 bootloop，只是永远显示"未激活"）。这种情况下请使用旧的 legacy 版本。

**步骤**

1. 下载 / 构建 `FlymeAuthTokenFix.apk` 并安装；
2. 在 LSPosed 管理器中启用模块；
3. **作用域**为 `staticScope=true` 固定，应为：
   - `system`（特殊虚拟包名，代表 `system_server` —— `AccountManagerService` 真正所在的进程，钩子生效处）
   - `com.github.android`（GitHub Mobile，仅用于打印注入确认日志）
4. **重启系统框架**（对 `system` 作用域需要重启 `system_server`，或直接重启设备）；
5. 用 `logcat` 验证：

   ```bash
   adb logcat -s LSPosed-Bridge | grep FlymeAuthFix
   ```

   期望看到：

   ```text
   # 模块加载（进程名应为 system_server 或 system）
   [FlymeAuthFix] event=module_loaded result=ok process=system api=102 framework=LSPosed ... systemServer=true
   # 钩子安装成功；count 因 Flyme 版本而异，≥1 即生效；fieldsReady 应为 true
   [FlymeAuthFix] event=hooked result=ok count=2/2 fieldsReady=true cost_us=...
   # 仅在勾选了 com.github.android 作用域时出现
   [FlymeAuthFix] event=injected result=ok package=com.github.android pid=...
   ```

   `fieldsReady=false` 表示该 Flyme 版本的字段名与预期不符 —— 钩子会**静默失效**（不崩溃），请提 Issue 并附 `adb shell dumpsys account` 与反编译片段。

> 📌 `META-INF/xposed/scope.list` 与 `java_init.list` 是**逐行清单**，不支持 `#` 注释
> （`#` 行会被当作包名/类名解析）。因此这两个文件仅含有效条目，说明写在本文档与
> `module.prop`（`.prop` 是 Java Properties 格式，`#` 注释合法）里。

## 自行构建

仓库**不含**预编译产物，请本地构建。

### 依赖

| 依赖 | 说明 |
| --- | --- |
| 环境 | **Linux**（在 WSL2 的 Linux 侧同样适用，不依赖任何 Windows 组件） |
| JDK | 需 `javac` / `java` / `keytool`（已验证 JDK 21） |
| Android SDK | 需 `platforms/<ver>/android.jar` 与 `build-tools/<ver>/{aapt2, lib/d8.jar, lib/apksigner.jar}` |
| `zip` | 打包 `classes.dex` / `META-INF` |

**不需要** Gradle，**不需要** NDK，**不需要**任何二进制依赖（libxposed API 以源码桩形式随仓库提供）。

### 一键构建

```bash
./build.sh
# 产物：bin/FlymeAuthTokenFix.apk
```

脚本会自动探测 SDK 位置（依次尝试 `$ANDROID_SDK`、`$ANDROID_SDK_ROOT`、`$ANDROID_HOME`、`~/android-sdk`、`~/Android/Sdk`、`/opt/android-sdk`、`/usr/lib/android-sdk`），并挑选**最高版本**的 `build-tools` 与 `platforms`。只有同时含 `android.jar` 与 `d8.jar` 的目录才会被认作有效 SDK。

可用环境变量覆盖：

```bash
ANDROID_SDK=/path/to/sdk BUILD_TOOLS_VER=35.0.0 PLATFORM_VER=android-36 ./build.sh
```

> ⚠️ 若本机有多个 `platforms` 版本，默认会取最高版（例如 `android-37`）。这对模块本身无影响（模块不用新版 API），但如果你想固定编译基线，建议显式传 `PLATFORM_VER`。

### 关于 `aapt2`

优先使用 SDK 自带的原生 `aapt2`（版本与 build-tools 严格同源）。仅当 SDK 内缺失时才回落到 `PATH` 中的 `aapt2`，并打印警告 —— 发行版包（如 Debian 的 `aapt 2.19-debian`）远旧于现代 SDK，解析新版 `android.jar` 会报：

```
error: failed to load include path .../android.jar
RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data
```

见到这个报错，就说明脚本回落到了 `PATH` 中的旧版 `aapt2`，请给 SDK 装齐 build-tools。

### 构建流程

```
javac (源码 → bin/classes)
  └─ 删除 io/github/libxposed/api/**（libxposed 编译期桩，不打包）
d8    (bin/classes → classes.dex)
aapt2 compile  (src/main/res → bin/res_compiled/res.zip)
aapt2 link     (manifest + res.zip → bin/unaligned.apk)
zip   (追加 classes.dex、META-INF/xposed/{java_init.list,module.prop,scope.list})
apksigner sign (bin/FlymeAuthTokenFix.apk，调试密钥首次自动生成)
```

### 关于 libxposed API 桩类（`src/main/java/io/github/libxposed/api/`）

这些是 **compileOnly 桩**：仅用于让 `javac` 通过类型检查，方法体为空。构建第 2 步会把整个 `io/` 目录从产物中剔除，运行时由 LSPosed 框架注入真实现（API 102 明确禁止模块用反射访问框架 API，所以保留桩在 DEX 里是错的）。

之所以不直接引入上游 `io.github.libxposed:api:102.0.0`，是因为纯 `javac` 环境取不到它依赖的 `androidx.annotation` / `libxposed:annotation`，且上游 `Invoker.Type` 用了 Java 17 的 `sealed interface` + `record`，与 `-source 8` 目标冲突。上游源码副本放在 [`references/libxposed-api/`](references/libxposed-api/) 供对照。

### 关于调试签名

`build.sh` 首次运行会在 `bin/debug.keystore` 生成调试密钥（口令 `android`，别名 `androiddebugkey`），该目录已被 `.gitignore` 排除。**调试签名的 APK 无法覆盖安装他人签名的同包名应用**，如需长期使用请自行替换为固定密钥。

## 仓库结构

```
.
├── AndroidManifest.xml              # 仅声明 label / description（旧 xposed* meta-data 已移除）
├── build.sh                         # 一键构建（Linux）
├── src/main/
│   ├── resources/META-INF/xposed/   # 现代 Xposed API 模块元数据
│   │   ├── java_init.list           # Java 入口类全限定名
│   │   ├── module.prop              # minApiVersion / targetApiVersion / staticScope / ...
│   │   └── scope.list               # 注入范围：system + com.github.android
│   ├── res/values/strings.xml       # app_name 与 module_description
│   └── java/
│       ├── top/takotsubo/flyme/authtokenfix/ModuleEntry.java  # 核心钩子逻辑
│       └── io/github/libxposed/api/                          # API 102 编译期桩（不打包）
├── docs/
│   ├── flyme_account_manager_service.smali   # Flyme 频控逻辑反编译片段
│   ├── github_mobile_logout_trigger.smali    # GitHub Mobile 掉登触发点
│   └── logcat_evidence.log                   # 掉登现场日志切片
└── references/
    └── libxposed-api/                        # 上游 API 源码副本（未纳入版本控制）
```

## 兼容性与已知限制

- **仅针对 Flyme**。AOSP / 其他 OEM ROM 无此私有频控逻辑，装上也只是空转（字段解析失败后 `fieldsReady=false`，钩子设为空实现）。
- **依赖 libxposed API 102 框架**（LSPosed 2.x / Vector）。旧版框架不会把本模块列为模块。
- 依赖 `com.android.server.accounts.AccountManagerService` 的**私有字段名** `mRetryCount` / `mLastRetryTime`。若某 Flyme 版本改名，模块会**静默失效**（不会崩溃），日志里会是 `fieldsReady=false`，请提 Issue 并附 `adb shell dumpsys account` 与反编译片段。
- 通过清除频控换取可用性，**理论上会放大异常应用的轮询压力**。若你在意功耗，可考虑改成更保守的策略（例如只在 `mRetryCount >= 8` 时才重置）—— 注意那需要读回字段值，会引入额外的字段读取。
- 已在 Android 14 / API 34 基线的 Flyme 上定位缺陷；模块本身**尚未在真机上安装运行验证**（无 LSPosed 环境测试记录），日志格式为按代码推得的预期输出。
- 不支持 Hot Reload（`autoHotReload=false`）。

## 免责声明

本模块通过修改系统进程内存中的字段实现修复，属于**非官方行为**。请自行评估风险，务必先做好数据备份、并确保有可用的救砖手段。作者不对任何数据丢失或设备故障负责。

## 许可

[MIT](LICENSE)
