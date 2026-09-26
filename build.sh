#!/bin/bash
#
# 纯命令行构建 FlymeAuthTokenFix.apk
#
# 依赖（任一环境满足其一即可）：
#   - Android SDK（build-tools 内含 d8.jar / apksigner.jar；aapt2 可为 Linux 版或 Windows 版 .exe）
#   - JDK（javac / java / keytool）
#   - zip
#
# 可用环境变量覆盖：
#   ANDROID_SDK       Android SDK 根目录（默认自动探测）
#   BUILD_TOOLS_VER   build-tools 版本（默认自动取最高版本）
#   PLATFORM_VER      platforms 版本（默认自动取最高版本）
#
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# ---------------------------------------------------------------- 探测 SDK ---
find_sdk() {
    local cand
    for cand in "$ANDROID_SDK" "$ANDROID_SDK_ROOT" "$ANDROID_HOME" \
                "$HOME/Android/Sdk" /opt/android-sdk /usr/lib/android-sdk \
                /mnt/c/Android; do
        [ -n "$cand" ] || continue
        # 必须同时具备 platforms（含 android.jar）与 build-tools（含 d8/apksigner）
        if ls -1 "$cand"/platforms/*/android.jar >/dev/null 2>&1 \
           && ls -1 "$cand"/build-tools/*/lib/d8.jar >/dev/null 2>&1; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

SDK="$(find_sdk || true)"
[ -n "$SDK" ] || { echo "错误：未找到 Android SDK，请设置 ANDROID_SDK 环境变量" >&2; exit 1; }

latest_dir() { ls -1 "$1" 2>/dev/null | sort -V | tail -1; }

if [ -n "$BUILD_TOOLS_VER" ]; then
    BUILD_TOOLS="$SDK/build-tools/$BUILD_TOOLS_VER"
else
    BUILD_TOOLS="$SDK/build-tools/$(latest_dir "$SDK/build-tools")"
fi
if [ -n "$PLATFORM_VER" ]; then
    PLATFORM="$SDK/platforms/$PLATFORM_VER"
else
    PLATFORM="$SDK/platforms/$(latest_dir "$SDK/platforms")"
fi

SDK_JAR="$PLATFORM/android.jar"
D8_JAR="$BUILD_TOOLS/lib/d8.jar"
APKSIGNER_JAR="$BUILD_TOOLS/lib/apksigner.jar"

[ -f "$SDK_JAR" ]      || { echo "错误：找不到 $SDK_JAR" >&2; exit 1; }
[ -f "$D8_JAR" ]       || { echo "错误：找不到 $D8_JAR" >&2; exit 1; }
[ -f "$APKSIGNER_JAR" ]|| { echo "错误：找不到 $APKSIGNER_JAR" >&2; exit 1; }

# ------------------------------------------------------- 解析 aapt2 调用方式 ---
# 三种模式，按可用性择优：
#   native —— SDK 内自带 Linux/WSL 原生 aapt2（版本与 build-tools 一致，最理想）
#   winexe —— WSL 下 SDK 只有 aapt2.exe 时的回退：经 cmd.exe 调用 Windows 版，
#            并借 pushd 的自动映射拿到 UNC 路径对应的临时盘符（Z: 之类）
#   path   —— PATH 中的 aapt2（Linux 发行版包）。注意发行版包往往远旧于
#             SDK 版本，可能无法解析新版 platforms/android-XX/android.jar
#   （native 与 winexe 都取 SDK 自带版本，保证与 build-tools 同源）
AAPT2_MODE=""
if [ -x "$BUILD_TOOLS/aapt2" ]; then
    AAPT2_MODE="native"
elif [ -x "$BUILD_TOOLS/aapt2.exe" ] && command -v cmd.exe >/dev/null 2>&1 \
     && command -v wslpath >/dev/null 2>&1; then
    AAPT2_MODE="winexe"
fi
if [ -z "$AAPT2_MODE" ] && command -v aapt2 >/dev/null 2>&1; then
    AAPT2_MODE="path"
fi

if [ -z "$AAPT2_MODE" ]; then
    echo "错误：未找到可用的 aapt2" >&2
    echo "      请在 build-tools 内安装对应宿主平台的 aapt2，" >&2
    echo "      或 WSL 下利用 Android SDK 的 aapt2.exe，" >&2
    echo "      或安装 Linux 版 aapt2（如 apt install aapt）" >&2
    exit 1
fi

AAPT2_EXE="$(wslpath -w "$BUILD_TOOLS/aapt2.exe" 2>/dev/null || echo "")"
WIN_PROJ="$(wslpath -w "$PROJECT_DIR" 2>/dev/null || echo "")"

# 经 cmd.exe 执行 aapt2.exe：把命令写进临时 .bat 再执行。
# 两个坑：
#   1. 直接 cmd.exe /c "cd /d ... && ..." 会踩到 cmd 的双引号剥离规则，
#      写成批处理文件可绕开这层转义地狱；
#   2. 项目在 \\wsl.localhost\... UNC 路径下时 cmd.exe 无法直接作为工作目录，
#      用 pushd 会让 cmd 自动分配一个临时盘符（Z: 之类）再切过去；
#      因此参数里的路径要基于 %CD%（映射后的真实盘符）而非原始 UNC 写法。
AAPT2_BAT="bin/.aapt2-tmp.bat"
aapt2_winexe() {
    # $1 = aapt2 参数串，用 %CD% 引用项目目录（见上）
    {
        printf '@echo off\r\n'
        printf '@pushd "%s" >nul\r\n' "$WIN_PROJ"
        printf '"%s" %s\r\n' "$AAPT2_EXE" "$1"
        printf '@popd >nul\r\n'
    } > "$AAPT2_BAT"
    cmd.exe /c "$(wslpath -w "$PROJECT_DIR/$AAPT2_BAT")"
    local rc=$?
    rm -f "$AAPT2_BAT"
    return $rc
}

# 把仓库内路径转成 Windows 路径；winexe 模式下统一以 %CD%（pushd 映射出的
# 临时盘符）为基准，避免 wslpath -w 在 UNC 路径下产出 cmd 无法解析的写法。
# Windows 的 aapt2 接受正斜杠，因此拼出来就是 X:/dir/file 这种形式。
win_path() {
    local p="$1"
    case "$p" in
        "$PROJECT_DIR"*) echo "%CD%${p#$PROJECT_DIR}" ;;
        *) echo "$(wslpath -w "$p")" ;;
    esac
}

# aapt2_compile <res 目录> <输出 zip（相对仓库根）>
aapt2_compile() {
    local res_in zip_out
    res_in="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    zip_out="$PROJECT_DIR/$2"
    case "$AAPT2_MODE" in
        native) "$BUILD_TOOLS/aapt2" compile --dir "$res_in" -o "$zip_out" ;;
        path)   aapt2 compile --dir "$res_in" -o "$zip_out" ;;
        winexe) aapt2_winexe "compile --dir \"$(win_path "$res_in")\" -o \"$(win_path "$zip_out")\"" ;;
    esac
}

# aapt2_link <输出 apk（相对仓库根）>
aapt2_link() {
    # --manifest / res.zip / 输出 apk 三者共用的 Windows 路径
    local m n o
    case "$AAPT2_MODE" in
        winexe)
            m="$(win_path "$PROJECT_DIR/AndroidManifest.xml")"
            n="$(win_path "$PROJECT_DIR/bin/res_compiled/res.zip")"
            o="$(win_path "$PROJECT_DIR/$1")"
            aapt2_winexe "link -I \"$(wslpath -w "$SDK_JAR")\" \
                    --manifest \"$m\" \"$n\" -o \"$o\" --auto-add-overlay"
            ;;
        native)
            "$BUILD_TOOLS/aapt2" link -I "$SDK_JAR" \
                --manifest "$PROJECT_DIR/AndroidManifest.xml" \
                "$PROJECT_DIR/bin/res_compiled/res.zip" \
                -o "$PROJECT_DIR/$1" --auto-add-overlay
            ;;
        path)
            aapt2 link -I "$SDK_JAR" \
                --manifest "$PROJECT_DIR/AndroidManifest.xml" \
                "$PROJECT_DIR/bin/res_compiled/res.zip" \
                -o "$PROJECT_DIR/$1" --auto-add-overlay
            ;;
    esac
}

echo "SDK         : $SDK"
echo "build-tools : $BUILD_TOOLS"
echo "platform    : $PLATFORM"
echo "aapt2 模式  : $AAPT2_MODE"
echo

rm -rf bin/classes bin/res_compiled bin/classes.dex bin/unaligned.apk
mkdir -p bin/classes bin/res_compiled

echo "1. 编译 Java 源码..."
javac -encoding UTF-8 -source 8 -target 8 -cp "$SDK_JAR" \
    $(find src/main/java -name "*.java") \
    -d bin/classes

echo "2. 剔除 Xposed Stub 类（仅编译期使用，不打包）..."
rm -rf bin/classes/de

echo "3. 转换 class 为 DEX..."
java -cp "$D8_JAR" com.android.tools.r8.D8 \
    --min-api 26 \
    --output bin/ \
    $(find bin/classes -name "*.class")

echo "4. 编译资源..."
aapt2_compile src/main/res bin/res_compiled/res.zip

echo "5. 链接 APK..."
aapt2_link bin/unaligned.apk

echo "6. 写入 classes.dex 与 assets..."
( cd bin && zip -q -u unaligned.apk classes.dex )
( cd src/main && zip -q -u "$PROJECT_DIR/bin/unaligned.apk" assets/xposed_init )

echo "7. 生成调试签名（仅首次）..."
if [ ! -f bin/debug.keystore ]; then
    keytool -genkeypair -v -keystore bin/debug.keystore -storepass android \
        -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
        -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi

echo "8. 签名 APK..."
java -jar "$APKSIGNER_JAR" sign --ks bin/debug.keystore --ks-pass pass:android \
    --ks-key-alias androiddebugkey --key-pass pass:android \
    --out bin/FlymeAuthTokenFix.apk bin/unaligned.apk

echo
echo "完成: $PROJECT_DIR/bin/FlymeAuthTokenFix.apk"
ls -lh bin/FlymeAuthTokenFix.apk
