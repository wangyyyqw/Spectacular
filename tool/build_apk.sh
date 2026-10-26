#!/usr/bin/env bash
# 打包 Android release APK：构建 → 落到 dist/ → 复制到下载文件夹（后缀改大写 .APK）→ 打印 SHA-256。
# 用法：tool/build_apk.sh
set -euo pipefail
cd "$(dirname "$0")/.."

app=apps/reader_mobile
name=spectacular-reader-release
# dist 已在 .gitignore（APK 不入库）；下载文件夹仅在存在时才复制。
dist="$app/dist"
build_apk="$app/build/app/outputs/flutter-apk/app-release.apk"
downloads="${HOME}/Downloads"

(cd "$app" && flutter build apk --release)

[ -f "$build_apk" ] || { echo "构建产物缺失：$build_apk" >&2; exit 1; }

mkdir -p "$dist"
cp "$build_apk" "$dist/$name.apk"

if [ -d "$downloads" ]; then
  cp "$build_apk" "$downloads/$name.APK"
  echo "已复制：$downloads/$name.APK"
else
  echo "跳过下载文件夹（不存在：$downloads）" >&2
fi

ls -lh "$dist/$name.apk"
shasum -a 256 "$dist/$name.apk"
