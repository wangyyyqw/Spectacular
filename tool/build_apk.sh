#!/usr/bin/env bash
# 使用本地缓存打包 Android Release APK，并保存到 dist/ 与下载文件夹。
# 用法：tool/build_apk.sh [--allow-downloads]；缓存缺失时才允许下载。
set -euo pipefail
cd "$(dirname "$0")/.."

app=apps/reader_mobile
# dist 已在 .gitignore（APK 不入库）；下载文件夹仅在存在时才复制。
dist="$app/dist"
build_apk="$app/build/app/outputs/flutter-apk/app-release.apk"
downloads="${HOME}/Downloads"

cache_option=--offline
if [ "${1:-}" = --allow-downloads ] && [ "$#" -eq 1 ]; then
  cache_option=
elif [ "$#" -ne 0 ]; then
  echo '用法：tool/build_apk.sh [--allow-downloads]' >&2
  exit 2
fi
# 单独构建自动分配；build_local.py 已为同轮多个平台分配时直接共用。
if [ -z "${READER_RELEASE_VERSION:-}" ] || [ -z "${READER_RELEASE_NUMBER:-}" ]; then
  read -r READER_RELEASE_VERSION READER_RELEASE_NUMBER < <(python3 tool/release_metadata.py --reserve)
fi
name="阅微 Extend arm64 v${READER_RELEASE_VERSION}（${READER_RELEASE_NUMBER}）"
# Windows 下 Kotlin 增量缓存可能被文件锁占用，改为非增量编译以保证打包稳定。
kotlin_incremental=
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) kotlin_incremental='-Pkotlin.incremental=false' ;;
esac
symbols="$PWD/$dist/symbols/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$symbols"
# Git Bash 下 Flutter/Gradle 运行在 Windows 路径语义中；传入 POSIX 路径时
# AOT 快照器可能无法创建符号文件。保留 shell 路径用于校验和复制，构建参数
# 在 Windows 上显式转换为驱动器路径。
flutter_symbols="$symbols"
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) flutter_symbols="$(cygpath -w "$symbols")" ;;
esac
flutter_sdk="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().parent.parent)' "$(command -v flutter)")"

if [ ! -f "$app/.dart_tool/package_config.json" ] || [ -z "$cache_option" ]; then
  (cd "$app" && flutter pub get ${cache_option:+"$cache_option"})
fi
if [ -z "${JAVA_HOME:-}" ] && [ -d '/Applications/Android Studio.app/Contents/jbr/Contents/Home' ]; then
  export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
fi

(
  cd "$app"
  flutter build apk --release --no-pub --config-only --target-platform=android-arm64 \
    --build-name="$READER_RELEASE_VERSION" --build-number="$READER_RELEASE_NUMBER" \
    --split-debug-info="$flutter_symbols"
  dart --packages="$flutter_sdk/packages/flutter_tools/.dart_tool/package_config.json" \
    ../../tool/generate_release_plugins.dart "$flutter_sdk"
  cd android
  build_time="$(date '+%Y-%m-%d %H:%M:%S %z')"
  build_defines="$(python3 -c 'import base64,sys; print(base64.b64encode(("APP_BUILD_TIME="+sys.argv[1]).encode()).decode())' "$build_time")"
  ./gradlew ${cache_option:+"$cache_option"} --console=plain :app:assembleRelease \
    -Pdart-defines="$build_defines" \
    -Pflutter.versionName="$READER_RELEASE_VERSION" -Pflutter.versionCode="$READER_RELEASE_NUMBER" \
    -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart \
    -Pdisable-abi-filtering=true \
    -Psplit-debug-info="$flutter_symbols" \
    -Pbase-application-name=android.app.Application \
    -Pdart-obfuscation=false -Ptrack-widget-creation=false -Ptree-shake-icons=true \
    ${kotlin_incremental:+"$kotlin_incremental"}
)

[ -f "$build_apk" ] || { echo "构建产物缺失：$build_apk" >&2; exit 1; }
[ -s "$symbols/app.android-arm64.symbols" ] || { echo "调试符号缺失：$symbols" >&2; exit 1; }

mkdir -p "$dist"
cp "$build_apk" "$dist/$name.apk"
# 保留现有 CI 和上传脚本使用的固定入口，用户交付使用版本化文件名。
cp "$build_apk" "$dist/spectacular-reader-release.apk"

if [ -d "$downloads" ]; then
  cp "$build_apk" "$downloads/$name.apk"
  echo "已复制：$downloads/$name.apk"
else
  echo "跳过下载文件夹（不存在：$downloads）" >&2
fi

ls -lh "$dist/$name.apk"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$dist/$name.apk" | tee "$symbols/apk.sha256"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$dist/$name.apk" | tee "$symbols/apk.sha256"
fi
echo "调试符号：$symbols"
