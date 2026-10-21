# HANDOFF — 读全文再开始干活

生成时间: 2026-09-27T11:58:17+08:00 · Git HEAD: a1cc8b8
信任规则: [V] = 交接时已用命令验证；[?] = 仅记忆未复核，当线索对待；[X] = 已证伪，别用。

## 0. 复核（下一会话先做）

- 锚点: `main` @ `a1cc8b8` (2026-09-27 11:58)
- 漂移检查: `git rev-parse HEAD~1` 是否仍 = `a1cc8b8`——本次 handoff 提交的 parent 才是文档记录的 SHA；变了说明快照可能过期
- 待重探的 [?]: §5 中标 `[?]` 的两条（build-tools 37.0.0 的 aapt2 版本捕获、`android` vs `system` scope 推断）
- 先读: `CLAUDE.md`（含缺陷本质、API 102 要点、构建注意点）→ `src/main/java/top/takotsubo/flyme/authtokenfix/ModuleEntry.java`

## 1. 当前目标

**已完成**：把模块从经典 Xposed API（`de.robv.android.xposed` / `xposedminversion=93`）**重构为 libxposed API 102**，并把拦截器热路径改为零反射查找。

完成定义（已达成）：`./build.sh` 清洁构建 `rc=0`，产物含 `META-INF/xposed/{java_init.list,module.prop,scope.list}` 三项，DEX 内不含任何 libxposed API 类定义。

## 2. 已验证状态 — 工作实际停在哪

- 公开仓库 `https://github.com/TakotsuboChen/flyme-authtoken-fix`，三个切片已推送，`main` 与 `origin/main` 同步 [V] `git push` → `a51654c..a1cc8b8`；`git status --short --branch` → `## main...origin/main`（无 ahead/behind）
- 清洁构建可复现 [V] `rm -rf bin && ./build.sh` → `BUILD EXIT CODE: 0`，产物 17K
- 签名有效 [V] `apksigner verify bin/FlymeAuthTokenFix.apk` → `rc=0`
- 产物内容 [V] `unzip -l`：`AndroidManifest.xml` 1276 / `resources.arsc` 796 / `classes.dex` 7252 / `META-INF/xposed/{module.prop 906, java_init.list 45, scope.list 26}` / META-INF 签名 3 项；**无 `assets/`**
- DEX 内类定义精确为 3 个且只有 `ModuleEntry` 一族 [V] 用 Python 解析 DEX 头 `class_defs`（offset 0x60/0x64）→ `ModuleEntry$FieldResetter` / `ModuleEntry$NoopHooker` / `ModuleEntry`；**无 `io/github/libxposed/api` 任何类定义**（仅作外部引用存在于常量池）
- scope.list 打包后内容为 `system` + `com.github.android` 两行 [V] `unzip -p … META-INF/xposed/scope.list`

### build 输出（本次交接 run 的真实输出）

```
$ rm -rf bin && ./build.sh
SDK         : /home/takotsubo/android-sdk
build-tools : /home/takotsubo/android-sdk/build-tools/37.0.0
platform    : /home/takotsubo/android-sdk/platforms/android-37
aapt2       : SDK 自带 (Android Asset Packaging Tool (aapt) 2.20-15087165)
...
完成: /home/takotsubo/projects/flyme-authtoken-fix/bin/FlymeAuthTokenFix.apk
-rw-r--r-- 1 takotsubo takotsubo 17K  9月 27 11:56 bin/FlymeAuthTokenFix.apk
BUILD EXIT CODE: 0
```

**实测未做的**：模块**尚未在真机上安装运行过**（无 LSPosed 环境测试记录）。README §安装与使用 的预期日志是**从代码推得的**，非实测 [V]（已在 README 与 CLAUDE.md 显式标注）。

## 3. 决策与理由

- **走 Java hook 而非 native/Rust** [V]——用户提出的"Rust 超高性能"诉求已当面澄清后放弃：`native_init` 只接收 `HookFunType`/`UnhookFunType`，能力是 hook **native 符号**，无法拦截 Java 方法 `getAuthToken`；纯 Rust 自建 ART hook（LSPlant+Dobby 交叉编译）复杂度高、在 system_server 内增加 native 崩溃面且性能不如框架自带通道。用户选择了 Java 极致优化路线。
- **热路径改为安装期缓存 `Field` 句柄** [V]——旧实现每帧 `XposedHelpers.setXxxField(obj, "名字")` 做按名查找 + 字符串比较，且失败抛异常；新实现安装期 `getDeclaredField` + `setAccessible(true)` 一次，热路径只 `setInt`/`setLong`。相关源码：`ModuleEntry.FieldResetter`。
- **scope 由 `android` 改为特殊虚拟包名 `system`** [?]——依据 libxposed 官方 package-info：有 `android:process="system"` 组件的包不能靠包名本身定位 system_server，须用 `system`。**这是基于文档的推断，未经真机验证**（旧版用 `android` 曾"生效"的说法本身也未实测）。
- **字段缺失时仍注册 hook 但挂 `NoopHooker`，而非不注册** [V]——保持旧版"降级为钩子无效而非崩溃 system_server"语义，代价是一次可内联判断，且 `fieldsReady=false` 进日志更易诊断；API 102 同 id 可原子替换，运行期仍有修正余地。
- **API 以手写源码桩提供而非引依赖** [V]——无 Gradle 环境取不到上游依赖的 `androidx.annotation` / `libxposed:annotation`，且上游 `Invoker.Type` 用 Java 17 `sealed interface` + `record`（与 `-source 8` 冲突）。桩只覆盖本模块用到的子集。
- **版本号保持 `versionCode=1` / `versionName=1.0`** [V]——用户红线，未擅自升版。
- **`references/` 加进 `.gitignore` 而非入库** [V]——上游浅克隆副本各含嵌套 `.git`，作为本地只读参考，不是构建输入。

## 4. 失败的尝试 — 不要再试

- **`native_init` 拦 Java 方法** → `native_init(const NativeAPIEntries*)` 的 entries 只有 `hook_func`/`unhook_func`（native 内联 hook），没有 Java hook 通道 [V] 对照 `references/libxposed-api` + 官方 Wiki + LSPlant 文档 → **native 路线对 `getAuthToken` 无立足点，不要再往"纯 Rust 拦截 Java 方法"方向做**。
- **抽取上游 libxposed API 源码直接编译** → 缺 `androidx.annotation` / `io.github.libxposed.annotation` 依赖，且 `Invoker.Type` 的 `sealed interface Type permits …` + `record` 在 `-source 8` 下编译失败 [V] 观察到 DM 报错后改为手写桩。不要重试"直接拿上游源码编译"。
- **第 6 步从 `src/main` 打包 META-INF** → 产物变成 `resources/META-INF/xposed/...`，LSPosed 读不到、模块静默不加载 [V] `unzip -l` 复核发现后改从 `src/main/resources` 起打包。**新增元数据文件时不要改回从 `src/main` 打包。**
- **经 `cmd.exe` 调 `aapt2.exe`**（上一会话遗留，仍适用）→ 撞 UNC 路径不能作 cmd 工作目录、双引号被剥离 [V]。根因是"用 cmd 调 exe"本身多余——bash 可直接 exec `.exe`。不要再走 cmd。
- **`./build.sh 2>&1 | head -8` 验证构建**（上一会话遗留，仍适用）→ 管道提前关闭使脚本在链接步骤被 SIGPIPE 杀死，`rc=0` 但产物残缺 [V]。取退出码时不要用 `head`/`tail` 截断。

## 5. 已知坑

- **`META-INF/xposed/{java_init.list,scope.list}` 是逐行清单，不支持 `#` 注释** [V]——`#` 行会被当作包名/类名解析。只有 `module.prop`（Java Properties 格式）能写注释。已因此把 scope.list 的注释全部移除。
- **`aapt2 version` 输出走 stderr** [V]——`build.sh` 用 `aapt2_ver()` 封装 `2>&1`。改脚本时不要"优化"掉。
- **build-tools 37.0.0 下 `aapt2 version` 在 `$(...)` 命令替换里曾捕获为空** [?]——上一会话观察到（同次测试 35.0.0 / 36.1.0 正常），未追根因。脚本对空版本号容忍（只影响打印），不阻塞构建。本次运行显示版本号正常捕获。
- **Debian 的 `aapt`/`aapt2` 版本过旧** [V]——`/usr/bin/aapt2` 来自 `aapt 1:14~beta1-3`，报 `RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data`，无法解析 `platforms/android-36/android.jar`。脚本优先 SDK 自带版本。
- **`platforms` 默认取最高版** [V]——本机为 `android-37`。模块不用新版 API，影响仅限编译基线；固定基线需显式传 `PLATFORM_VER`。
- **`bin/` 未入库** [V]——盘上 APK 由本机临时调试密钥签名（每次 `rm -rf bin` 会重新生成）。若要**覆盖安装**到已有旧版（另一把调试密钥签的），签名不匹配会失败，需卸载重装。
- **`references/` 含嵌套 git 仓库** [V]——已在 `.gitignore` 排除；`git status -uall` 不再显示它。若将来要真正入库，需先删掉嵌套 `.git`。

## 6. 下一步（有序）

1. **真机验证**（唯一实质待办）：在 Flyme + 支持 libxposed API 102 的 LSPosed 设备上安装 `bin/FlymeAuthTokenFix.apk`，作用域应为 `system` + `com.github.android`，重启 `system_server`（或整机重启），然后
   `adb logcat -s LSPosed-Bridge | grep FlymeAuthFix`
   预期看到 `event=module_loaded`（`systemServer=true`）、`event=hooked result=ok count=N fieldsReady=true`。
2. **重点核对 scope 语义**：若步骤 1 未出现 `event=hooked`，先试把 `scope.list` 的 `system` 换成 `android` 重打包对比——这是本轮唯一未验证的行为变更。
3. **验证后回填**：把 README §安装与使用 的"推得"日志换成实测日志，并删除 README / CLAUDE.md 里的"尚未真机验证"标注。

## 7. 留给用户的开放问题

- **`CLAUDE.md` 里写了本机 SDK 路径 `~/android-sdk`**，仓库公开，暴露本地目录结构（不含秘密）。保留还是改中性说法（如"原生 Linux SDK"）？**已跨两个会话未答复。**
- 原始 APK（2026-09-26 12:28 那份，另一把调试密钥签的）备份在 `/tmp/FlymeAuthTokenFix.apk.bak`。若仍需覆盖安装旧版，得用回原密钥；否则可弃。
- `platforms` 编译基线是否要固定为 `android-36`（Flyme 实测机型为 Android 14 / API 34 基线）？当前默认取最高版 `android-37`。
- 本模块是否需要真正的 Rust 原生层（例如把日志/诊断写进 Rust）？当前判断是"对 Java 方法 hook 无收益"，若用户有其他 native 侧诉求可另议。
- 是否发 GitHub Release 附签名 APK（此前用户选择"只提交源码"，Release 是另一条通路）。
