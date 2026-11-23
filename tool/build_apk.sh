#!/usr/bin/env bash
# 使用本地缓存打包 Android Release APK，并保存到 dist/ 与下载文件夹。
# 用法：tool/build_apk.sh [--allow-downloads]；缓存缺失时才允许下载。
set -euo pipefail
cd "$(dirname "$0")/.."

app=apps/reader_mobile
name=spectacular-reader-release
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
# Windows 下 Kotlin 增量缓存可能被文件锁占用，改为非增量编译以保证打包稳定。
kotlin_incremental=
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) kotlin_incremental='-Pkotlin.incremental=false' ;;
esac
symbols="$PWD/$dist/symbols/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$symbols"
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
    --split-debug-info="$symbols"
  dart --packages="$flutter_sdk/packages/flutter_tools/.dart_tool/package_config.json" \
    ../../tool/generate_release_plugins.dart "$flutter_sdk"
  cd android
  build_time="$(date '+%Y-%m-%d %H:%M:%S %z')"
  build_defines="$(python3 -c 'import base64,sys; print(base64.b64encode(("APP_BUILD_TIME="+sys.argv[1]).encode()).decode())' "$build_time")"
  ./gradlew ${cache_option:+"$cache_option"} --console=plain :app:assembleRelease \
    -Pdart-defines="$build_defines" \
    -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart \
    -Pdisable-abi-filtering=true \
    -Psplit-debug-info="$symbols" \
    -Pbase-application-name=android.app.Application \
    -Pdart-obfuscation=false -Ptrack-widget-creation=false -Ptree-shake-icons=true \
    ${kotlin_incremental:+"$kotlin_incremental"}
)

[ -f "$build_apk" ] || { echo "构建产物缺失：$build_apk" >&2; exit 1; }
[ -s "$symbols/app.android-arm64.symbols" ] || { echo "调试符号缺失：$symbols" >&2; exit 1; }

mkdir -p "$dist"
cp "$build_apk" "$dist/$name.apk"

if [ -d "$downloads" ]; then
  cp "$build_apk" "$downloads/$name.APK"
  echo "已复制：$downloads/$name.APK"
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
