#!/usr/bin/env bash
# 本次独立审计：用新探针验证核心边界与严格分析配置。
set -euo pipefail
cd "$(dirname "$0")/../.."

audit_tmp=$(mktemp -d)
audit_probe="packages/reader_core/lib/_audit_probe_$$.dart"
cleanup() { rm -f "$audit_probe"; rm -rf "$audit_tmp"; }
trap cleanup EXIT
mkdir -p "$audit_tmp/lib"
cat > "$audit_tmp/pubspec.yaml" <<'EOF'
name: audit_core
dependencies:
  flutter:
    sdk: flutter
EOF

for directive in import export; do
  for package in path_provider reader_mobile reader_ui; do
    printf "%s 'package:%s/api.dart';\n" "$directive" "$package" > "$audit_tmp/lib/probe.dart"
    if CORE_LIB="$audit_tmp/lib" CORE_PUBSPEC="$audit_tmp/pubspec.yaml" \
      bash tool/check_core_boundary.sh > "$audit_tmp/boundary.log" 2>&1; then
      echo "失败：核心边界未拦截 $directive $package" >&2
      exit 1
    fi
  done
done
echo '通过：新边界探针拦截平台插件与宿主包的 import/export（6 例）'

cat > "$audit_probe" <<'EOF'
// 新审计探针：验证 dynamic 隐式转换确实按错误拦截。
int auditCast(dynamic value) {
  final int result = value;
  return result;
}
EOF
if (cd packages/reader_core && dart analyze "lib/$(basename "$audit_probe")") \
  > "$audit_tmp/cast.log" 2>&1; then
  echo '失败：strict-casts 未拦截隐式转换' >&2
  exit 1
fi
rg -q invalid_assignment "$audit_tmp/cast.log"

cat > "$audit_probe" <<'EOF'
// 新审计探针：验证集合未提供类型时严格推断确实报错。
final auditItems = [];
EOF
if (cd packages/reader_core && dart analyze "lib/$(basename "$audit_probe")") \
  > "$audit_tmp/inference.log" 2>&1; then
  echo '失败：strict-inference 未拦截无类型集合' >&2
  exit 1
fi
rg -q inference_failure_on_collection_literal "$audit_tmp/inference.log"
echo '通过：新静态探针确认 strict-casts 与 strict-inference 生效（2 例）'
