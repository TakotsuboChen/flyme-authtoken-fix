# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Cross-session handoff

- On session start: read [HANDOFF.md](HANDOFF.md) fully, then summarize the previous session's goal, current state, and next step before proceeding.

## Project Overview

`flyme-authtoken-fix` 是一个免费开源的 **LSPosed / Xposed 模块**，用于修复魅族 Flyme 系统 `com.android.server.accounts.AccountManagerService` 的私有 getAuthToken 频控缺陷 —— 该缺陷会使 GitHub Mobile（`com.github.android`）等应用被强制掉登。

- 仓库：`https://github.com/TakotsuboChen/flyme-authtoken-fix`（公开）
- 许可：MIT
- 语言：纯 Java（无 Kotlin / 无 Gradle / 无 NDK），`build.sh` 直接调 `javac` + `d8` + `aapt2` + `apksigner`
- **模块 API**：libxposed API 102（`io.github.libxposed.api.XposedModule`），非旧版 `de.robv.android.xposed` API

## 版本号红线

`AndroidManifest.xml` 里的 `versionCode` / `versionName` 是**用户的决策域**。构建、装机、发 Release 一律用当前版本号原样构建；**未经用户明确同意不得升版**（需先问"版本号定多少"）。

## 缺陷本质（改动前必读）

Flyme 在 `AccountManagerService` 上私加了 `mRetryCount`(int) / `mLastRetryTime`(long) 两个**Service 单例字段**与一段节流：`elapsedRealtime() - mLastRetryTime < 500ms` 则累加计数，计数 `>= 10` 就 `onError(ERROR_CODE_CANCELED, "getAuthToken too frequently")` 直接拒绝。

两个设计错误构成缺陷：
1. **计数器粘性** —— 只有"两次调用间隔 ≥ 500ms"才清零。持续高频调用（间隔恒 < 500ms）时计数永不归零，退化成"全局累计 10 次永久封禁"。
2. **粒度过粗** —— 字段在 Service 单例上，不区分 uid / account / authTokenType，一个应用会污染所有其他应用的配额。

`ERROR_CODE_CANCELED`(=4) 被 OAuth 客户端（尤其 `net.openid.appauth`）解读为"用户取消/凭证失效" → 清理本地凭据 → 强制掉登。

**修复方式**：在 `getAuthToken` 的全部重载执行前，把 `mRetryCount` 清 0、`mLastRetryTime` 置 0（0 使 `elapsedRealtime() - 0` 恒 ≥ 500，等价于"上次调用在无限久之前"）。

改动 `ModuleEntry.java` 时注意：
- **字段句柄在安装期解析一次**（`getDeclaredField` + `setAccessible(true)`）并缓存在 `FieldResetter` 实例里；热路径只做 `setInt`/`setLong`，**不要退回按名查找**（`XposedHelpers` 式做法每帧都要字符串比较，且失败会抛异常）。
- 字段解析失败时**仍注册 hook 但挂 `NoopHooker`** —— 语义是"降级为钩子无效，绝不崩溃 `system_server`"，并让 `fieldsReady=false` 进日志。
- 必须遍历 `getDeclaredMethods()` 按**方法名**全量匹配重载，Flyme 在每个重载开头都加了节流。
- 拦截器热路径约束：**零分配 / 零异常 / 零符号查找**，字段写包在 `try/catch` 内静默吞。
- 作用域由 `src/main/resources/META-INF/xposed/scope.list` 决定：`system`（特殊虚拟包名，代表 `system_server`）+ `com.github.android`（注入确认日志用）。

## 现代 Xposed API（libxposed API 102）要点

- 入口类继承 `io.github.libxposed.api.XposedModule`，无需（也不允许）调用 `attachFramework()`。
- **元数据全部在 `META-INF/xposed/` 下**，取代旧版 `assets/xposed_init` 与 manifest 里的 `xposed*` meta-data：
  - `java_init.list`（每行一个入口类全限定名）
  - `module.prop`（`minApiVersion` / `targetApiVersion` 必填，`staticScope` / `exceptionMode` / `autoHotReload` 可选）
  - `scope.list`（每行一个包名；**`system` 是代表 system_server 的特殊虚拟包名**）
- 模块名/描述改用 `android:label` / `android:description` 资源。
- **`android` 包不再适合作为 system_server 的 scope**：官方文档指出其组件在 `android.uid.system` 下声明 `android:process="system"` 时即运行于 system_server，须显式用 `system`。
- system_server 的首次加载阶段由 `onSystemServerStarting(SystemServerStartingParam)` **替代** `onPackageLoaded`/`onPackageReady` 的首次触发。
- Hook 模型是 OkHttp 式拦截链：`hook(m).setId(...).setPriority(...).setExceptionMode(...).intercept(Hooker)`，Hooker 内通过 `Chain.getThisObject()`/`proceed()` 访问原调用。
- `ExceptionMode` 的 Java 枚举**只有** `DEFAULT`/`PROTECTIVE`/`PASSTHROUGH`（没有 `PROTECTIVE` 以外的简写）。
- API 102 起，libxposed 模块**被禁止调用旧 `de.robv.android.xposed` API**，也禁止用反射访问 Xposed API。

### libxposed API 桩类（`src/main/java/io/github/libxposed/api/`）

仓库不引 Gradle/Maven，API 以**源码桩**随仓库提供（`build.sh` 第 2 步把 `io/` 从 DEX 剔除，运行时由框架注入真实现）。桩只实现本模块用到的子集（`Invoker`/`CtorInvoker`/RemotePreferences 等未包含）。**新增 API 调用前先对照 `references/libxposed-api/` 里的上游源码补齐签名**，否则运行时 `NoSuchMethodError`。

不直接编译上游源码的原因：它依赖仓库外的 `androidx.annotation` / `libxposed:annotation`，且 `Invoker.Type` 用了 Java 17 的 `sealed interface` + `record`（与 `-source 8` 冲突）。

## 构建

```bash
./build.sh        # → bin/FlymeAuthTokenFix.apk（bin/ 已被 .gitignore 排除）
```

**纯 Linux 环境**，不依赖任何 Windows 组件。已验证宿主：Linux（本机原生 SDK 于 `~/android-sdk`，build-tools 34/35/36.1/37、platforms 35/36/37）+ WSL2 的 Linux 侧。

### 构建中的注意点（改 build.sh 前必读）

1. **`aapt2` 优先取 SDK 自带版本**（版本与 build-tools 同源），只在 SDK 内缺失时才回落 `PATH`。Debian 打包的 `aapt` 是 `2.19-debian`，远旧于现代 SDK，解析 `android.jar` 会报 `RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data`。
2. **`aapt2 version` 把结果写到 stderr**，捕获版本号必须 `2>&1`（脚本用 `aapt2_ver()` 封装）。曾有 `2>/dev/null` 导致版本号显示为空的坑。
3. **`javac` 的 `-source 8 -target 8`** 会产生 bootstrap classpath 警告，属正常，不影响产物。
4. **`io/github/libxposed/api/**` 是 compileOnly 桩**（空实现），构建第 2 步 `rm -rf bin/classes/io` 把它们从 DEX 里剔除。**只删 `io/` 子树**，不要删模块自身的 `top/` 包。
5. **`META-INF/xposed/*` 必须落在 APK 根**，因此第 6 步从 `src/main/resources` 起用 `cd … && zip -r -u … META-INF` 打包。若误从 `src/main` 打包会得到 `resources/META-INF/...`（LSPosed 读不到，模块静默不加载）。
6. **platforms 默认取最高版**（本机为 `android-37`）。模块不使用新版 API，影响仅限于编译基线；要固定基线就显式传 `PLATFORM_VER`。

## 实测证据（docs/）

- `flyme_account_manager_service.smali` —— Flyme 频控逻辑的反编译片段（含 `0x1f4`=500ms、`0xa`=10 两个魔数）。
- `github_mobile_logout_trigger.smali` —— GitHub Mobile 掉登触发点。
- `logcat_evidence.log` —— 掉登现场日志切片，69 个 `--- Trigger point at line N ---` 分段（每段约 24 行上下文，围绕 `SimplifiedLoginActivity` 被反复拉起）。**不含 PII**，可安全公开；但新增日志切片前应重新做一遍 PII 扫描（手机号、android_id、邮箱、token）。

## 未验证状态

模块**尚未在真机上安装运行过**。README §安装与使用 里的日志样例是**按代码推得的预期输出**，不是实测结果。真机验证后应回填实测日志。
