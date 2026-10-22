#!/usr/bin/env bash
# reader_core 边界检查：禁止 import 平台插件/宿主包，也禁止在 pubspec 声明它们。
# 依据《技术方案》§59.2；可在 CI 与本地执行。
set -euo pipefail
cd "$(dirname "$0")/.."

core_lib="${CORE_LIB:-packages/reader_core/lib}"
core_pubspec="${CORE_PUBSPEC:-packages/reader_core/pubspec.yaml}"

[ -d "$core_lib" ] || { echo "缺少目录：$core_lib" >&2; exit 1; }
[ -f "$core_pubspec" ] || { echo "缺少文件：$core_pubspec" >&2; exit 1; }

forbidden='path_provider|drift|sqlite3_flutter_libs|file_picker|flutter_tts|share_plus|url_launcher|webview_flutter|flutter_inappwebview|flutter_html|shared_preferences|sqflite|device_info_plus|package_info_plus|image_picker|permission_handler|flutter_secure_storage|open_filex'

failed=0

# 1) 源码 import 检查
if hits=$(grep -rEn "^import ['\"]package:($forbidden)(/|['\"])" "$core_lib" 2>/dev/null); then
  echo "reader_core 不得 import 平台插件/宿主包：" >&2
  echo "$hits" >&2
  failed=1
fi

# 2) pubspec 依赖检查
deps=$(
  awk '
    /^dependencies:/ { in_deps = 1; next }
    /^[a-z_]+:/ { in_deps = 0 }
    in_deps && /^  [a-zA-Z0-9_]+:/ {
      line = $0
      sub(/^  /, "", line)
      sub(/:.*/, "", line)
      print line
    }
  ' "$core_pubspec"
)
for dep in $deps; do
  if echo "$dep" | grep -Eq "^($forbidden)$"; then
    echo "reader_core 的 pubspec 不得依赖：$dep" >&2
    failed=1
  fi
done

if [ "$failed" -eq 0 ]; then
  echo "通过：reader_core 无平台插件/宿主包依赖"
fi
exit "$failed"
