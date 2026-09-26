# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Cross-session handoff

- On session start: read [HANDOFF.md](HANDOFF.md) fully, then summarize the previous session's goal, current state, and next step before proceeding.

## Project Overview

`flyme-authtoken-fix` 是一个免费开源的 **LSPosed / Xposed 模块**（经典 `de.robv.android.xposed` API，`xposedminversion=93`，非 libxposed API 102），用于修复魅族 Flyme 系统 `com.android.server.accounts.AccountManagerService` 的私有 getAuthToken 频控缺陷 —— 该缺陷会使 GitHub Mobile（`com.github.android`）等应用被强制掉登。

- 仓库：`https://github.com/TakotsuboChen/flyme-authtoken-fix`（公开）
- 许可：MIT
- 语言：纯 Java（无 Kotlin / 无 Gradle），`build.sh` 直接调 `javac` + `d8` + `aapt2` + `apksigner`

## 版本号红线

`AndroidManifest.xml` 里的 `versionCode` / `versionName` 是**用户的决策域**。构建、装机、发 Release 一律用当前版本号原样构建；**未经用户明确同意不得升版**（需先问"版本号定多少"）。

## 缺陷本质（改动前必读）

Flyme 在 `AccountManagerService` 上私加了 `mRetryCount`(int) / `mLastRetryTime`(long) 两个**Service 单例字段**与一段节流：`elapsedRealtime() - mLastRetryTime < 500ms` 则累加计数，计数 `>= 10` 就 `onError(ERROR_CODE_CANCELED, "getAuthToken too frequently")` 直接拒绝。

两个设计错误构成缺陷：
1. **计数器粘性** —— 只有"两次调用间隔 ≥ 500ms"才清零。持续高频调用（间隔恒 < 500ms）时计数永不归零，退化成"全局累计 10 次永久封禁"。
2. **粒度过粗** —— 字段在 Service 单例上，不区分 uid / account / authTokenType，一个应用会污染所有其他应用的配额。

`ERROR_CODE_CANCELED`(=4) 被 OAuth 客户端（尤其 `net.openid.appauth`）解读为"用户取消/凭证失效" → 清理本地凭据 → 强制掉登。

**修复方式**：hook 全部 `getAuthToken` 重载的 `beforeHookedMethod`，把 `mRetryCount` 清 0、`mLastRetryTime` 置 0（0 使 `elapsedRealtime() - 0` 恒 ≥ 500，等价于"上次调用在无限久之前"）。

改动 `MainHook.java` 时注意：
- 用 `XposedHelpers.setIntField/setLongField` 并 `try/catch` 静默吞 —— 字段缺失时降级为"钩子无效"而非崩溃 `system_server`。
- 必须遍历 `getDeclaredMethods()` 按**方法名**全量匹配重载，Flyme 在每个重载开头都加了节流。
- 作用域由 `res/values/arrays.xml` 的 `xposed_scope` 决定：`android`（钩子实际生效处）+ `com.github.android`（注入确认日志用）。

## 构建

```bash
./build.sh        # → bin/FlymeAuthTokenFix.apk（bin/ 已被 .gitignore 排除）
```

**纯 Linux 环境**，不依赖任何 Windows 组件。已验证宿主：Linux（本机原生 SDK 于 `~/android-sdk`，build-tools 34/35/36.1/37、platforms 35/36/37）+ WSL2 的 Linux 侧。

### 构建中的注意点（改 build.sh 前必读）

1. **`aapt2` 优先取 SDK 自带版本**（版本与 build-tools 同源），只在 SDK 内缺失时才回落 `PATH`。Debian 打包的 `aapt` 是 `2.19-debian`，远旧于现代 SDK，解析 `android.jar` 会报 `RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data`。
2. **`aapt2 version` 把结果写到 stderr**，捕获版本号必须 `2>&1`（脚本用 `aapt2_ver()` 封装）。曾有 `2>/dev/null` 导致版本号显示为空的坑。
3. **`javac` 的 `-source 8 -target 8`** 会产生 bootstrap classpath 警告，属正常，不影响产物。
4. **`de/robv/android/xposed/**` 是 compileOnly 桩类**（空实现），构建第 2 步 `rm -rf bin/classes/de` 把它们从 DEX 里剔除，运行时由 Xposed 框架注入真实现。仓库因此无需任何二进制依赖。
5. **platforms 默认取最高版**（本机为 `android-37`）。模块不使用新版 API，影响仅限于编译基线；要固定基线就显式传 `PLATFORM_VER`。

## 实测证据（docs/）

- `flyme_account_manager_service.smali` —— Flyme 频控逻辑的反编译片段（含 `0x1f4`=500ms、`0xa`=10 两个魔数）。
- `github_mobile_logout_trigger.smali` —— GitHub Mobile 掉登触发点。
- `logcat_evidence.log` —— 掉登现场日志切片，69 个 `--- Trigger point at line N ---` 分段（每段约 24 行上下文，围绕 `SimplifiedLoginActivity` 被反复拉起）。**不含 PII**，可安全公开；但新增日志切片前应重新做一遍 PII 扫描（手机号、android_id、邮箱、token）。
