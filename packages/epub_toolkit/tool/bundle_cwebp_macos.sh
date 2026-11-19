#!/bin/bash
set -euo pipefail

APP_PATH="${1:?请传入 macOS .app 路径}"
CWEBP="${CWEBP_BIN:-$(command -v cwebp || true)}"
if [[ -z "$CWEBP" || ! -x "$CWEBP" ]]; then
  echo "缺少本地 cwebp，未完成 WebP 组件打包" >&2
  exit 1
fi
CONTENTS="$APP_PATH/Contents"
BREW_LIB="$(brew --prefix)/lib"
TOOLS="$CONTENTS/Resources"
BIN="$TOOLS/bin"
LIB="$TOOLS/lib"
LICENSES="$TOOLS/licenses"
mkdir -p "$BIN" "$LIB" "$LICENSES"
cp "$CWEBP" "$BIN/cwebp"
chmod 755 "$BIN/cwebp"

ensure_rpath() {
  local binary="$1"
  local path="$2"
  if ! otool -l "$binary" | awk '
    /cmd LC_RPATH/ { found=1; next }
    found && $1 == "path" { print $2; found=0 }
  ' | grep -Fxq "$path"; then
    install_name_tool -add_rpath "$path" "$binary"
  fi
}

copy_dependencies() {
  local binary="$1"
  local dependency
  while IFS= read -r dependency; do
    case "$dependency" in
      /opt/homebrew/*|/usr/local/*|@rpath/*)
        local name="${dependency##*/}"
        local source="$dependency"
        if [[ "$dependency" == @rpath/* ]]; then
          source="$BREW_LIB/$name"
        fi
        if [[ ! -f "$LIB/$name" ]]; then
          cp "$source" "$LIB/$name"
          chmod 755 "$LIB/$name"
          copy_dependencies "$LIB/$name"
          install_name_tool -id "@rpath/$name" "$LIB/$name"
          ensure_rpath "$LIB/$name" "@loader_path"
        fi
        install_name_tool -change "$dependency" "@rpath/$name" "$binary"
        ;;
    esac
  done < <(otool -L "$binary" | sed -n '2,$s/^[[:space:]]*\([^[:space:]]*\).*/\1/p')
}
copy_dependencies "$BIN/cwebp"
ensure_rpath "$BIN/cwebp" "@loader_path/../lib"
for library in "$LIB"/*.dylib; do
  codesign --force --sign - "$library"
done
codesign --force --sign - "$BIN/cwebp"

if command -v brew >/dev/null; then
  for formula in webp libpng jpeg-turbo libtiff zstd xz; do
    prefix="$(brew --prefix "$formula")"
    mkdir -p "$LICENSES/$formula"
    for notice in COPYING LICENSE LICENSE.md LICENSE.txt PATENTS; do
      if [[ -f "$prefix/$notice" ]]; then
        cp "$prefix/$notice" "$LICENSES/$formula/"
      fi
    done
  done
fi
"$BIN/cwebp" -version
if otool -L "$BIN/cwebp" "$LIB"/*.dylib | grep -E '/opt/homebrew|/usr/local/'; then
  echo "打包结果仍依赖外部动态库" >&2
  exit 1
fi
codesign --force --sign - --preserve-metadata=entitlements "$APP_PATH"
echo "已打包本地 WebP 组件"
