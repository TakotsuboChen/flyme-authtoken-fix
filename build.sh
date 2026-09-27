#!/bin/bash
#
# 构建 FlymeAuthTokenFix.apk（纯 Linux 环境）
#
# 依赖：
#   - JDK（javac / java / keytool）
#   - Android SDK：需 platforms/<ver>/android.jar 与
#     build-tools/<ver>/{aapt2, lib/d8.jar, lib/apksigner.jar}
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
# 按优先级依次尝试；只有同时具备 android.jar 与 d8.jar 才算有效 SDK
# （后者能顺带排除 Debian 的 /usr/lib/android-sdk —— 它不含 build-tools 完整组件）
find_sdk() {
    local cand
    for cand in "$ANDROID_SDK" "$ANDROID_SDK_ROOT" "$ANDROID_HOME" \
                "$HOME/android-sdk" "$HOME/Android/Sdk" \
                /opt/android-sdk /usr/lib/android-sdk; do
        [ -n "$cand" ] || continue
        [ -d "$cand" ] || continue
        if ls -1 "$cand"/platforms/*/android.jar >/dev/null 2>&1 \
           && ls -1 "$cand"/build-tools/*/lib/d8.jar >/dev/null 2>&1; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

SDK="$(find_sdk || true)"
if [ -z "$SDK" ]; then
    echo "错误：未找到可用的 Android SDK" >&2
    echo "      请安装完整 SDK，或用 ANDROID_SDK=/path/to/sdk 显式指定" >&2
    exit 1
fi

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

[ -f "$SDK_JAR" ]       || { echo "错误：找不到 $SDK_JAR" >&2; exit 1; }
[ -f "$D8_JAR" ]        || { echo "错误：找不到 $D8_JAR" >&2; exit 1; }
[ -f "$APKSIGNER_JAR" ] || { echo "错误：找不到 $APKSIGNER_JAR" >&2; exit 1; }

# ------------------------------------------------------------------ aapt2 ---
# 优先用 SDK 自带的原生 aapt2（版本与 build-tools 严格同源）；
# 缺失时才回落到 PATH 中的 aapt2 —— 发行版包通常远旧于 SDK，
# 解析新版 android.jar 会失败（RES_TABLE_TYPE_TYPE entry offsets overlap）。
# 注意：aapt2 把 version 输出写到 stderr，必须 2>&1 才能捕获
aapt2_ver() { "$1" version 2>&1 | head -1; }

if [ -x "$BUILD_TOOLS/aapt2" ]; then
    AAPT2="$BUILD_TOOLS/aapt2"
    AAPT2_SRC="SDK 自带 ($(aapt2_ver "$AAPT2"))"
elif command -v aapt2 >/dev/null 2>&1; then
    AAPT2="$(command -v aapt2)"
    AAPT2_SRC="PATH 回落 ($(aapt2_ver "$AAPT2"))"
    echo "警告：SDK 内无 aapt2，回落到 $AAPT2" >&2
    echo "      若报 'failed to load include path .../android.jar'，说明该版本过旧" >&2
else
    echo "错误：未找到 aapt2（既不在 $BUILD_TOOLS，也不在 PATH）" >&2
    exit 1
fi

echo "SDK         : $SDK"
echo "build-tools : $BUILD_TOOLS"
echo "platform    : $PLATFORM"
echo "aapt2       : $AAPT2_SRC"
echo

rm -rf bin/classes bin/res_compiled bin/classes.dex bin/unaligned.apk
mkdir -p bin/classes bin/res_compiled

echo "1. 编译 Java 源码..."
javac -encoding UTF-8 -source 8 -target 8 -cp "$SDK_JAR" \
    $(find src/main/java -name "*.java") \
    -d bin/classes

echo "2. 剔除编译期桩类（仅用于 javac 类型检查，不打包）..."
# io/github/libxposed/api/** 是 libxposed API 102 的桩，运行时由 LSPosed 框架注入真实现。
# 保留在 DEX 里会与框架的实现类冲突（且 API 102 禁止用反射访问框架 API）。
# 注意：只删 io/ 子树，不要删模块自身的 top/ 包。
rm -rf bin/classes/io

echo "3. 转换 class 为 DEX..."
java -cp "$D8_JAR" com.android.tools.r8.D8 \
    --min-api 26 \
    --output bin/ \
    $(find bin/classes -name "*.class")

echo "4. 编译资源..."
"$AAPT2" compile --dir src/main/res -o bin/res_compiled/res.zip

echo "5. 链接 APK..."
"$AAPT2" link -I "$SDK_JAR" \
    --manifest AndroidManifest.xml \
    bin/res_compiled/res.zip \
    -o bin/unaligned.apk --auto-add-overlay

echo "6. 写入 classes.dex 与 META-INF/xposed 元数据..."
( cd bin && zip -q -u unaligned.apk classes.dex )
# 现代 Xposed API 的模块元数据：java_init.list / module.prop / scope.list
# （取代旧版的 assets/xposed_init 与 manifest 里的 xposed* meta-data）
# 必须落在 APK 根的 META-INF/xposed/ 下，故从 src/main/resources 起打包
( cd src/main/resources && zip -q -r -u "$PROJECT_DIR/bin/unaligned.apk" META-INF )

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
