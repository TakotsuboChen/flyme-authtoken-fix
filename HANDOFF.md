# HANDOFF — 读全文再开始干活

生成时间: 2026-09-26T13:00:16+08:00 · Git HEAD: 3c74d4f
信任规则: [V] = 交接时已用命令验证；[?] = 仅记忆未复核，当线索对待；[X] = 已证伪，别用。

## 0. 复核（下一会话先做）

- 锚点: `main` @ `3c74d4f` (2026-09-26 13:00)
- 漂移检查: `git rev-parse HEAD~1` 是否仍 = `3c74d4f`——本次 handoff 提交的 parent 才是文档记录的 SHA；变了说明快照可能过期
- 待重探的 [?]: 无（本次全部结论均已 `[V]` 验证）
- 先读: `CLAUDE.md`（含缺陷本质与构建注意点）→ `src/main/java/top/takotsubo/flyme/authtokenfix/MainHook.java`

## 1. 当前目标

**已完成**：把这个原本不是 git 仓库的 LSPosed 模块整理成可公开的开源仓库，并把构建链从"依赖 Windows SDK + cmd.exe"重构为**纯 Linux**。

完成定义（已达成）：公开仓库存在、README/CLAUDE.md/LICENSE 齐备、`./build.sh` 在纯 Linux 下零依赖 Windows 组件即可产出可安装的签名 APK。

## 2. 已验证状态 — 工作实际停在哪

- 公开仓库已发布 `https://github.com/TakotsuboChen/flyme-authtoken-fix`，topics: `accountmanager android flyme lsposed meizu mod xposed` [V] `gh repo view` → `visibility: PUBLIC`, `defaultBranchRef: main`
- `build.sh` 已重构为纯 Linux（226 → 135 行），无任何 Windows 组件依赖 [V] `grep -riE "windows|wsl|cmd\.exe|aapt2\.exe|winexe|UNC|/mnt/c"` 在 `README.md`/`CLAUDE.md`/`build.sh`/`.gitignore`/`AndroidManifest.xml` 中仅剩 2 处"不依赖任何 Windows 组件"的声明语句
- 构建可复现：连续两次 clean build 均 `rc=0`，产物结构正确 [V] 见下方输出
- 签名有效 [V] `/usr/bin/apksigner verify bin/FlymeAuthTokenFix.apk` → `rc=0`
- 工作区: 干净（`git status --short` 无输出）[V]

### build 输出（本次交接 run 的真实输出）

```
BUILD EXIT CODE: 0
SDK         : /home/takotsubo/android-sdk
build-tools : /home/takotsubo/android-sdk/build-tools/37.0.0
platform    : /home/takotsubo/android-sdk/platforms/android-37
aapt2       : SDK 自带 (Android Asset Packaging Tool (aapt) 2.20-15087165)
...
完成: /home/takotsubo/projects/flyme-authtoken-fix/bin/FlymeAuthTokenFix.apk
-rw-r--r-- 1 takotsubo takotsubo 13K  9月 26 12:59 bin/FlymeAuthTokenFix.apk
```

产物内容 [V]（`unzip -l`）：`AndroidManifest.xml` 2092 / `resources.arsc` 804 / `classes.dex` 3496 / `assets/xposed_init` 42 / META-INF 3 项。

**实测未做的**：模块**尚未在真机上安装运行过**（无 LSPosed 环境测试记录）。README §安装与使用 的预期日志 `Successfully hooked N getAuthToken methods` 是**从代码推得的**，非实测 [V]。

## 3. 决策与理由

- **构建链去掉全部 Windows 依赖** [V]——SDK 探测优先本机原生 Linux SDK（`~/android-sdk`），不再含 `/mnt/c/Android`。理由是 bash 可直接 exec `.exe`（WSL2 binfmt_misc interop）且参数中的 Linux 路径会被 WSL 自动翻译，先前"用 cmd.exe 调 exe"纯属多余选择，为此付出的回退机制是自造负担。
  - 否决方案：保留三模式（`native`/`winexe`/`path`）——否决原因是它存在的唯一理由（绕 cmd.exe 的 UNC 与引号限制）在直接 exec 下根本不成立。
- **`.gitignore` 排除全部 `bin/`**（含 APK）；按用户选择，仓库只提交源码 [V]
- **build.sh 探测时要求 `platforms/*/android.jar` 与 `build-tools/*/lib/d8.jar` 同时存在**——用来排除 Debian 的 `/usr/lib/android-sdk`（它只有 build-tools 与 platform-tools，无 platforms）[V]
- **版本号保持 `versionCode=1` / `versionName=1.0` 原样**——用户红线，未擅自升版 [V] `AndroidManifest.xml`
- **`docs/logcat_evidence.log` 做了 PII 扫描后判定可公开** [V] `grep` 手机号/`android_id`/邮箱/token 模式均无命中
- **README 删去一段"AOSP 也有类似节流"的段落**——该断言无法在不联网查 AOSP 源码的情况下证实，故删而非留错 [V]（用户本期未要求恢复）

## 4. 失败的尝试 — 不要再试

- **经 `cmd.exe` 调 `aapt2.exe`** → 撞两个错：UNC 路径不能作 cmd 工作目录、`cmd.exe /c "..."` 双引号被剥离 [V] 报错 `UNC 路径不支持` 与 `文件名、目录名或卷标语法不正确`。改 `.bat`+`pushd`+`%CD%` 能跑通但是自造负担。**根因是"用 cmd 调 exe"本身多余——bash 可直接 exec `.exe`。不要再走 cmd 这条路。**
- **`aapt2 version 2>/dev/null | head -1` 捕获版本号** → 得到空字符串（输出走 stderr）[V] 打印出 `SDK 自带 ()`。必须 `2>&1`。不要再用 `2>/dev/null`。
- **`win_path()` 用 `case "$p" in "$PROJECT_DIR"*)` 判项目内路径** → UNC 项目下会把 `/mnt/c/...` 也误判为项目内 [V] 产出 `Z:\...\wsl.localhost\...` 废路径。该函数已随重构删除；**若将来重引入路径转换，注意这个 `case` 的覆盖过宽问题**。
- **`./build.sh 2>&1 | head -8` 验证构建** → 管道提前关闭导致脚本在链接步骤被 SIGPIPE 杀死，产物残缺 [V] `rc=0` 但 `bin/FlymeAuthTokenFix.apk` 不存在。取退出码时不要用 `head`/`tail` 截断（这正是 skill 反复警告的坑）。

## 5. 已知坑

- **`aapt2 version` 输出走 stderr** [V]——`build.sh` 用 `aapt2_ver()` 封装 `2>&1`。改脚本时不要"优化"掉。
- **build-tools 37.0.0 下 `aapt2 version` 在 `$(...)` 命令替换里曾捕获为空** [V] 观察到（同一次测试中 35.0.0 / 36.1.0 正常），**未追根因[?]**。脚本对空版本号是容忍的（只影响打印），不阻塞构建；但若要在 37.0.0 上依赖版本判断需先重探。
- **Debian 的 `aapt`/`aapt2` 版本过旧** [V]——`/usr/bin/aapt2` 来自 `aapt 1:14~beta1-3`，报 `RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data`，无法解析 `platforms/android-36/android.jar`。脚本优先 SDK 自带版本，仅缺失才回落 PATH 并打警告。
- **`platforms` 默认取最高版** [V]——本机为 `android-37`。模块不用新版 API，影响仅限编译基线；固定基线需显式传 `PLATFORM_VER`。
- **`bin/` 未入库** [V]——盘上 `bin/FlymeAuthTokenFix.apk` 由本机临时调试密钥签名。若要**覆盖安装**到已有旧版（由另一把调试密钥签的），签名不匹配会失败，需卸载重装。

## 6. 下一步（有序）

1. **真机验证**（唯一实质待办）：在 Flyme + LSPosed 设备上安装 `bin/FlymeAuthTokenFix.apk`，作用域勾 `android`（需重启 system_server）+ `com.github.android`，然后 `adb logcat -s LSPosed-Bridge | grep FlymeAuthFix` 确认出现 `Successfully hooked N getAuthToken methods`（N ≥ 1），并观察 GitHub Mobile 是否还会掉登。README §安装与使用 的描述目前只是代码推论，验证后应回填实测结果。
2. **可选**：若真机验证后要对外分发，考虑发 GitHub Release 附上签名 APK（用户此前选择了"`.gitignore` 全部排除、只提交源码"，Release 是另一条通路，需用户决定）。
3. **git 写操作**：本次三个切片已由 `/handoff` 流程推送。若 `git status` 显示仍有未推送提交且用户确认，再 push；否则跳过。

## 7. 留给用户的开放问题

- **CLAUDE.md 里写了本机 SDK 路径 `~/android-sdk`**，仓库公开，暴露了本地目录结构（不含任何秘密）。保留还是改为中性说法（如"原生 Linux SDK"）？**用户尚未答复。**
- 原始 APK（2026-09-26 12:28 那份，另一把调试密钥签的）备份在 `/tmp/FlymeAuthTokenFix.apk.bak`。若仍需覆盖安装旧版，得用回原密钥；否则可弃。
- `platforms` 编译基线是否要固定为 `android-36`（Flyme 实测机型为 Android 14 / API 34 基线）？当前默认取最高版 `android-37`。
