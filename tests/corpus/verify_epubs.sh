#!/usr/bin/env bash
# 校验 test_corpus 下生成的 EPUB 样本与 manifest.json。
#
# 检查项：
#   1. manifest.json 是合法 JSON，记录数 >= 6，字段齐全；
#   2. 每个样本存在、sha256 与 size_bytes 和 manifest 一致；
#      自建小样本限制 200KB，真实样本（kind=real，Git LFS）不限制；
#   3. unzip -l / unzip -t 可读，ZIP 结构完整；
#   4. mimetype 是第一个条目、内容为 application/epub+zip、以 stored 方式保存、
#      本地头 offset 为 0 且无 extra field（OCF 要求）；
#   5. 打印每个样本的文件头 od -c 与 unzip -l 输出，便于人工复核。
#
# 依赖：jq、unzip、zipinfo、shasum（macOS 自带）。
# 用法：bash tests/corpus/verify_epubs.sh
# 退出码：全部通过为 0，否则为 1。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORPUS_DIR="$REPO_ROOT/test_corpus"
MANIFEST="$CORPUS_DIR/manifest.json"
MAX_BYTES=$((200 * 1024))

FAIL=0
ok() { printf '  [通过] %s\n' "$1"; }
bad() { printf '  [失败] %s\n' "$1"; FAIL=$((FAIL + 1)); }

# 取 zipinfo -v 中第一个中央目录条目的某个字段值
zipinfo_field() {
  local file="$1" label="$2"
  zipinfo -v "$file" | awk -v label="$label" '
    /^Central directory entry #1:/ { inblock = 1; next }
    /^Central directory entry #2:/ { inblock = 0 }
    inblock && index($0, label) {
      sub("^.*" label "[[:space:]]*", "")
      print
      exit
    }
  '
}

printf '== 1. 依赖与 manifest ==\n'
for cmd in jq unzip zipinfo shasum; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "命令可用：$cmd"
  else
    bad "缺少命令：$cmd"
  fi
done

if [ -f "$MANIFEST" ]; then
  ok "manifest.json 存在"
else
  bad "manifest.json 不存在：$MANIFEST"
  printf '\n结论：失败（%d 项）\n' "$FAIL"
  exit 1
fi

if jq -e . "$MANIFEST" >/dev/null 2>&1; then
  ok "manifest.json 是合法 JSON"
else
  bad "manifest.json 不是合法 JSON"
  printf '\n结论：失败（%d 项）\n' "$FAIL"
  exit 1
fi

COUNT="$(jq '.samples | length' "$MANIFEST" 2>/dev/null || printf '0')"
if [ "$COUNT" -ge 6 ]; then
  ok "样本记录数：${COUNT}（要求 >= 6）"
else
  bad "样本记录数不足：${COUNT}（要求 >= 6）"
fi

if jq -e '
  (.samples | type == "array" and length >= 6) and
  (.samples | all(.[];
    (.id | type == "string" and length > 0) and
    (.file | type == "string" and length > 0) and
    (.title | type == "string" and length > 0) and
    (.language | type == "string" and length > 0) and
    (.source | type == "string" and length > 0) and
    (.license | type == "string" and length > 0) and
    (.features | type == "array" and length > 0) and
    (.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.size_bytes | type == "number" and . > 0)
  ))' "$MANIFEST" >/dev/null 2>&1; then
  ok "9 个必需字段齐全且类型正确"
else
  bad "存在字段缺失或类型错误（id/file/title/language/source/license/features/sha256/size_bytes）"
fi

BROKEN_LICENSE="$(jq -r '.samples[] | select(.id == "broken-resource") | .license' "$MANIFEST")"
if [ "$BROKEN_LICENSE" = "自建测试样本" ]; then
  ok "broken-resource 的 license 为「自建测试样本」"
else
  bad "broken-resource 的 license 为「${BROKEN_LICENSE}」，应为「自建测试样本」"
fi

printf '\n== 2. 逐样本校验 ==\n'
while IFS=$'\t' read -r id file expected_sha expected_size kind ocf; do
  printf '\n-- %s（%s）--\n' "$id" "$file"
  path="$CORPUS_DIR/$file"

  if [ ! -f "$path" ]; then
    bad "文件不存在：$file"
    continue
  fi
  ok "文件存在"

  if head -c 40 "$path" | grep -q '^version https://git-lfs'; then
    bad "文件是 Git LFS 指针，请先执行 git lfs pull"
    continue
  fi

  actual_sha="$(shasum -a 256 "$path" | awk '{print $1}')"
  if [ "$actual_sha" = "$expected_sha" ]; then
    ok "sha256 与 manifest 一致：$actual_sha"
  else
    bad "sha256 不一致：manifest=${expected_sha}，实际=$actual_sha"
  fi

  actual_size="$(wc -c <"$path" | tr -d '[:space:]')"
  if [ "$actual_size" -eq "$expected_size" ]; then
    ok "size_bytes 与 manifest 一致：$actual_size"
  else
    bad "size_bytes 不一致：manifest=${expected_size}，实际=$actual_size"
  fi

  if [ "$kind" = "real" ]; then
    ok "真实样本（Git LFS），大小 ${actual_size}B，不受 200KB 限制"
  elif [ "$actual_size" -lt "$MAX_BYTES" ]; then
    ok "文件小于 200KB：$actual_size < $MAX_BYTES"
  else
    bad "文件达到或超过 200KB：$actual_size"
  fi

  if unzip -t "$path" >/dev/null 2>&1; then
    ok "unzip -t 完整性检查通过"
  else
    bad "unzip -t 完整性检查失败"
  fi

  if [ "$kind" = "real" ]; then
    printf '\n  unzip -l %s（前 20 条）：\n' "$file"
    unzip -l "$path" 2>&1 | head -n 24 | sed 's/^/    /'
  else
    printf '\n  unzip -l %s：\n' "$file"
    unzip -l "$path" 2>&1 | sed 's/^/    /'
  fi

  first_entry="$(zipinfo -1 "$path" | head -n 1)"
  if [ "$first_entry" = "mimetype" ]; then
    ok "mimetype 是第一个条目"
  else
    bad "第一个条目是「${first_entry}」，不是 mimetype"
  fi

  mimetype_content="$(unzip -p "$path" mimetype 2>/dev/null)"
  if [ "$mimetype_content" = "application/epub+zip" ]; then
    ok "mimetype 内容正确：application/epub+zip"
  else
    bad "mimetype 内容错误：「${mimetype_content}」"
  fi

  mimetype_method="$(zipinfo_field "$path" 'compression method:')"
  case "$mimetype_method" in
    *stored*) ok "mimetype 未压缩（${mimetype_method}）" ;;
    *)
      if [ "$ocf" = "false" ]; then
        ok "mimetype 被压缩（真实样本已知不规范，manifest 标记 ocf_compliant=false）"
      else
        bad "mimetype 压缩方式不是 stored（${mimetype_method}）"
      fi
      ;;
  esac

  mimetype_offset="$(zipinfo_field "$path" 'offset of local header from start of archive:')"
  case "$mimetype_offset" in
    0*) ok "mimetype 本地头 offset 为 0" ;;
    *) bad "mimetype 本地头 offset 不为 0（${mimetype_offset}）" ;;
  esac

  mimetype_extra="$(zipinfo_field "$path" 'length of extra field:')"
  case "$mimetype_extra" in
    0\ bytes*) ok "mimetype 无 extra field" ;;
    *) bad "mimetype 存在 extra field（${mimetype_extra}）" ;;
  esac

  header_name="$(head -c 38 "$path" | tail -c 8)"
  if [ "$header_name" = "mimetype" ]; then
    ok "文件头偏移 30 处为 mimetype"
  else
    bad "文件头偏移 30 处不是 mimetype（实际「${header_name}」）"
  fi

  printf '  文件头（head -c 58 | od -c）：\n'
  head -c 58 "$path" | od -c | sed 's/^/    /'
done < <(jq -r '.samples[] | [.id, .file, .sha256, .size_bytes, (.kind // ""), (if .ocf_compliant == false then "false" else "true" end)] | @tsv' "$MANIFEST")

printf '\n== 结论 ==\n'
if [ "$FAIL" -ne 0 ]; then
  printf '失败：%d 项未通过\n' "$FAIL"
  exit 1
fi
printf '全部通过：%s 个样本（%s）\n' "$COUNT" "$MANIFEST"
exit 0
