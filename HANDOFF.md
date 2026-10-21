# HANDOFF — 读全文再开始干活

生成时间: 2026-10-21T13:34:18+08:00 · Git HEAD: 16638e2
信任规则: [V] = 交接时已用命令验证；[?] = 仅记忆未复核，当线索对待；[X] = 已证伪，别用。

## 0. 复核（下一会话先做）

- 锚点: `main` @ `16638e2` (2026-10-21 13:34)
- 漂移检查: `git rev-parse HEAD~1` 是否仍 = `16638e2`——HEAD 必是本次 handoff 提交，其 parent 才是文档记录的 SHA
- 待重探的 [?]: 见 §5 中标 `[?]` 的条目
- 先读: `CLAUDE.md` §真机验证状态 → `src/main/java/top/takotsubo/flyme/authtokenfix/ModuleEntry.java`

## 1. 当前目标

**已完成**：模块在真机上验证通过，并用 A/B 对照确证修复有效。这是本仓库历史上第一次真正跑起来。

完成定义（已达成）：system_server 内出现 `event=hooked result=ok count=1/1 fieldsReady=true`；关闭修复时计数器累积到 9、开启修复时恒为 0。

## 2. 已验证状态 — 工作实际停在哪

- 注入 system_server 成功 [V] `grep takotsubo /data/adb/lspd/log/modules_*.log` → `(system)[...] event=module_loaded result=ok process=system api=102 systemServer=true` + `event=hooked result=ok count=1/1 fieldsReady=true cost_us=1332`
- 注入 `com.github.android` 成功 [V] 同日志 → `event=injected result=ok package=com.github.android`
- **A/B 对照确证修复有效** [V] 诊断版日志：
  - 对照组（`APPLY_FIX=false`）：`call=50..59 rawRetryCount=0,1,2,3,4,5,6,7,8,9` **持续累积**
  - 修复版（`APPLY_FIX=true`）：50 次调用 `rawRetryCount` 恒为 `0`
- `getAuthToken` 在该 ROM 上只有 1 个重载 [V] `dexdump /data/local/tmp/sj/classes.dex` → `name: 'getAuthToken' type: '(Landroid/accounts/IAccountManagerResponse;Landroid/accounts/Account;Ljava/lang/String;ZZLandroid/os/Bundle;)V'`，与 `count=1/1` 吻合
- 缺陷字段在 Flyme 12.6 仍存在 [V] `strings /system/framework/services.jar` → `mRetryCount` / `mLastRetryTime` / `getAuthToken too frequently`
- 构建通过 [V] `./build.sh` → `BUILD_RC=0`，产物 17K
- 诊断代码不残留 [V] DEX 内 `event=intercept` / `rawRetryCount` / `applyFix` 均不存在（`static final` 死代码消除）
- 工作区: 干净，`main` 与 `origin/main` 同步

### 设备环境

MEIZU 20 / Flyme 12.6.0.0A / Android 16 (API 36) / LSPosed 2.2.1 (7930) / KernelSU。
连接方式 `adb connect 192.168.50.142:5555`。另有一台 OnePlus OPD2413 同时在线（非目标设备，别搞混）。

## 3. 决策与理由

- **保留 `DIAGNOSTIC` / `APPLY_FIX` 两个开关（当前 false/true）** [V]——它们是 `static final` 常量，关闭时 javac 死代码消除，DEX 无残留、热路径零开销。保留便于将来复验，代价为零。否决方案：验证完删掉，因为下次再要验证还得重写一遍。
- **scope 保持 `system` + `com.github.android`** [V]——`system` 是 hook 目标，`com.github.android` 只用于注入确认日志。
- **不升版本号** [V]——`versionCode=1` / `versionName=1.0` 原样保留，属用户决策域。

## 4. 失败的尝试 — 不要再试

- **用 `grep <包名> /proc/<system_server_pid>/maps` 判断模块是否注入** → 得出"现代 libxposed API 模块进不了 system_server"的错误结论 [X]——用户当场纠正「并非不生效，核心破解都是生效的」，实测不同签名覆盖安装成功证明 corepatch 确实在 system_server 生效。maps 里看不到模块是常态（DEX 可能走 `InMemoryDexClassLoader`，且 maps 里的 APK 多是资源包）。改用 LSPosed 日志 + 模块自身日志。见记忆 `lsposed-injection-verify-method`。
- **把 `module.prop` 改成极简无注释格式** → 模块从"仅 system_server 失效"恶化成"完全不加载" [X]——说明当时是别的原因（增量安装死链）叠加，改格式无益且有害。已回滚。
- **怀疑中文注释导致 Properties 解析失败** → 同一 ROM 上 corepatch 用极简格式能跑，但改极简后我们的模块反而全挂 [X]——不是根因。不要再往这个方向查。
- **`strings services.jar | grep -c getAuthToken` 数出 10 个重载** → 误判 [X]——包含了 `getAuthTokenLabel` 等不同方法名。精确方法名匹配只有 1 个，须用 `dexdump` 核实。
- **只重启 zygote（`setprop ctl.restart zygote`）来刷新配置** → 设备会短暂 offline 且 `lspd` 不重启，配置缓存不刷新 [V]——必须完整 `adb reboot`。
- 上一轮遗留、仍适用：
  - **`native_init` 拦 Java 方法** → `NativeAPIEntries` 只有 native hook 通道，对 `getAuthToken` 无立足点 [V]。不要再往"纯 Rust 拦截 Java 方法"方向做。
  - **直接编译上游 libxposed API 源码** → 缺 `androidx.annotation` / `libxposed:annotation`，且 `Invoker.Type` 用 Java 17 `sealed interface` + `record` 与 `-source 8` 冲突 [V]。
  - **第 6 步从 `src/main` 打包 META-INF** → 产物变成 `resources/META-INF/xposed/...`，LSPosed 读不到 [V]。
  - **经 `cmd.exe` 调 `aapt2.exe`** → UNC 路径与引号问题 [V]。
  - **`./build.sh 2>&1 | head -8` 验证构建** → SIGPIPE 杀死脚本，`rc=0` 但产物残缺 [V]。

## 5. 已知坑

- **`adb install` 默认 Incremental Install 会让模块静默不加载** [V]——LSPosed 记录临时 staging 路径，开机解析时报 `Failed to open APK: No such file or directory` 然后跳过该模块，无任何用户可见报错。**必须 `adb install --no-incremental -r`**（输出 `Performing Streamed Install`）。详见记忆 `lsposed-adb-incremental-install-breaks-module`。
- **重装模块可能清空 LSPosed 的启用状态与 scope** [V]——`modules_state` / `scope` 表该包名记录被删，只剩 `modules.apk_path` 更新。重装后须核对，必要时停 `lspctl stop` 后直接改 db 再重启。
- **设备上没有 `sqlite3`，也没有 `python`** [V]——改 `modules_config.db` 只能：pull 到本地用 Python 改 → push 回去 → `chmod 600` → 重启。改前先 `lspctl stop`。
- **`modules_*.log` 只记错误与异常** [V]——正常加载日志不一定出现；完整记录要开 verbose（`/data/adb/lspd/log/verbose_*.log`，只在设备重启时新建）。
- **`lspctl` 的 developer mode 默认关闭** [V]——`lspctl status` 可用，但完整功能需 developer mode。
- **`META-INF/xposed/{java_init.list,scope.list}` 不支持 `#` 注释** [V]——`#` 会被当包名解析。只有 `module.prop`（Properties 格式）能写注释。
- **`aapt2 version` 输出走 stderr** [V]——`build.sh` 用 `aapt2_ver()` 封装 `2>&1`，别"优化"掉。
- **Debian 的 `aapt`/`aapt2` 版本过旧** [V]——报 `RES_TABLE_TYPE_TYPE entry offsets overlap`，脚本优先用 SDK 自带版本。
- **`bin/` 未入库** [V]——APK 由本机临时调试密钥签名，`rm -rf bin` 会重新生成，签名不匹配时覆盖安装会失败（除非 corepatch 生效）。
- **`references/` 含嵌套 git 仓库** [V]——已在 `.gitignore` 排除。

## 6. 下一步（有序）

1. **回填 README §安装与使用 的实测日志**：把按代码推得的样例换成真机输出（`event=module_loaded ... systemServer=true`、`event=hooked result=ok count=1/1 fieldsReady=true`）。已在 README 与 CLAUDE.md 标注"仍为推得"，未完成。
2. **长期观察掉登是否真的消失**：A/B 对照证明了计数器被清零，但"GitHub Mobile 不再被踢出登录"需要真实使用数天才能确认。若仍掉登，说明还有第二条路径（如 `getAuthTokenLabel` 或其他被节流的方法）。
3. 视需要决定是否清理 `DIAGNOSTIC` / `APPLY_FIX` 开关（当前判断是保留，代价为零）。

## 7. 留给用户的开放问题

- **`CLAUDE.md` 里写了本机 SDK 路径 `~/android-sdk`**，仓库公开，暴露本地目录结构（不含秘密）。保留还是改中性说法？**已跨三个会话未答复。**
- `platforms` 编译基线是否要固定为 `android-36`（Flyme 实测机型为 Android 16 / API 36）？当前默认取最高版 `android-37`。
- 是否发 GitHub Release 附签名 APK（此前用户选择"只提交源码"）。
- 原始 APK（2026-09-26 那份，另一把调试密钥签的）备份在 `/tmp/FlymeAuthTokenFix.apk.bak`，可弃。
