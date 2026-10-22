#!/usr/bin/env bash
# 运行 P0-14 文本测量性能基线。
set -euo pipefail
cd "$(dirname "$0")/../.."
cd packages/reader_core
flutter test test/bench/measure_bench_test.dart
