#!/usr/bin/env bash
# 全仓库统一执行：pub get → analyze → test。
set -euo pipefail
cd "$(dirname "$0")/.."

targets=(
  packages/reader_core
  packages/reader_ui
  apps/reader_mobile
)

for dir in "${targets[@]}"; do
  echo "==> $dir"
  (cd "$dir" && flutter pub get >/dev/null && flutter analyze && flutter test)
done

echo "全部通过：${#targets[@]} 个包"
