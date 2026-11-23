#!/usr/bin/env bash
# 打包 Android Release APK，上传到 Streamshare 并删除上一次上传。
# 用法：tool/publish_apk.sh [--allow-downloads]
set -euo pipefail
cd "$(dirname "$0")/.."

tool/build_apk.sh "$@"
node tool/share_apk.mjs apps/reader_mobile/dist/spectacular-reader-release.apk
