#!/usr/bin/env bash
# 独立审计入口：静态分析全部代码，仅运行本次新写的 test/audit 测试。
set -euo pipefail
cd "$(dirname "$0")/.."

for target in packages/reader_core packages/reader_ui apps/reader_mobile; do
  echo "审计：$target"
  (cd "$target" && flutter pub get >/dev/null && flutter analyze && flutter test test/audit --reporter expanded)
done
bash tool/check_core_boundary.sh
bash tests/audit/engineering_guard_audit.sh
git diff --check
echo '通过：三包静态分析、独立新测试、工程守卫与差异检查'
