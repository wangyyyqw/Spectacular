#!/usr/bin/env bash
# 验证 tool/check_core_boundary.sh：正常通过、import 违规失败、pubspec 违规失败。
set -euo pipefail
cd "$(dirname "$0")/../.."

pass() { echo "通过：$1"; }
fail() { echo "失败：$1" >&2; exit 1; }

bash tool/check_core_boundary.sh >/dev/null || fail "正常状态未通过边界检查"

probe="packages/reader_core/lib/_boundary_probe.dart"
cleanup() { rm -f "$probe" /tmp/boundary_pubspec.yaml; }
trap cleanup EXIT

cat > "$probe" <<'EOF'
// 临时探针：core 不允许引用平台插件。
import 'package:path_provider/path_provider.dart';
EOF
if bash tool/check_core_boundary.sh >/tmp/boundary_import.log 2>&1; then
  fail "import 违规未被拦截"
fi
grep -q "不得 import" /tmp/boundary_import.log || fail "缺少 import 违规提示"
pass "import 违规被拦截"
rm -f "$probe"

awk '
  { print }
  /^dependencies:/ && !done {
    print "  path_provider: ^2.1.0"
    done = 1
  }
' packages/reader_core/pubspec.yaml > /tmp/boundary_pubspec.yaml
grep -q "path_provider" /tmp/boundary_pubspec.yaml || fail "测试夹具未写入 path_provider"
if CORE_PUBSPEC=/tmp/boundary_pubspec.yaml bash tool/check_core_boundary.sh >/tmp/boundary_pubspec.log 2>&1; then
  fail "pubspec 违规未被拦截"
fi
grep -q "不得依赖：path_provider" /tmp/boundary_pubspec.log || fail "缺少 pubspec 违规提示"
pass "pubspec 违规被拦截"
