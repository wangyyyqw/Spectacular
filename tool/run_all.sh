#!/usr/bin/env bash
# 显式全量入口；日常验证使用 python3 tool/run_tests.py。
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tool/run_tests.py --all --analyze "$@"
