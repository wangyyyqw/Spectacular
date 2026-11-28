#!/usr/bin/env bash
# 审计入口：复用本地依赖，分析应用包并运行审计回归与 EPUB 工具测试。
set -euo pipefail
cd "$(dirname "$0")/.."

for target in packages/reader_core packages/reader_ui packages/epub_toolkit apps/reader_mobile; do
  echo "审计：$target"
  (
    cd "$target"
    flutter analyze --no-pub
    if [ -d test/audit ]; then
      tests=(test/audit/*_test.dart)
    else
      tests=(test/*_test.dart)
    fi
    flutter test --no-pub --reporter expanded "${tests[@]}"
  )
done
(cd packages/opencc_native && dart analyze)
bash tool/check_core_boundary.sh
bash tests/audit/engineering_guard_audit.sh
git diff --check
echo '通过：五包静态分析、审计与工具测试、工程守卫及差异检查'
