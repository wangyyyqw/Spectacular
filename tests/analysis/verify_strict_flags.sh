#!/usr/bin/env bash
# 验证根目录 analysis_options.yaml 的严格规则确实生效：
# 1) 无法推断集合类型 → 报错；2) dynamic 隐式转换 → 报错。
set -euo pipefail
cd "$(dirname "$0")/../.."

probe="packages/reader_core/lib/_strict_probe.dart"
cleanup() { rm -f "$probe"; }
trap cleanup EXIT

fail() {
  echo "失败：$1" >&2
  exit 1
}

# 用例 1：严格推断
cat > "$probe" <<'EOF'
// 临时探针：集合字面量缺少类型实参，strict-inference 应报错。
final untypedList = [];
EOF
set +e
(cd packages/reader_core && flutter analyze lib/_strict_probe.dart > /tmp/strict_probe_1.log 2>&1)
code1=$?
set -e
if [ "$code1" -eq 0 ]; then
  cat /tmp/strict_probe_1.log >&2
  fail "严格推断未生效：分析通过"
fi
grep -q "inference_failure_on_collection_literal" /tmp/strict_probe_1.log \
  || fail "未出现 inference_failure_on_collection_literal"

# 用例 2：严格转换（dynamic 隐式赋值给 int）
cat > "$probe" <<'EOF'
// 临时探针：dynamic 隐式转换，strict-casts 应报错。
void probe() {
  dynamic value = 1;
  final int number = value;
  print(number);
}
EOF
set +e
(cd packages/reader_core && flutter analyze lib/_strict_probe.dart > /tmp/strict_probe_2.log 2>&1)
code2=$?
set -e
if [ "$code2" -eq 0 ]; then
  cat /tmp/strict_probe_2.log >&2
  fail "严格转换未生效：分析通过"
fi
grep -q "invalid_assignment" /tmp/strict_probe_2.log || fail "未出现 invalid_assignment"

echo "通过：strict-inference 与 strict-casts 均按错误级别生效（analyze 退出码非 0）"
