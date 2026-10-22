#!/usr/bin/env bash
# 运行快照哈希测试（P0-23；P2-25 接入真实页序列后扩展为基线对比）。
set -euo pipefail
cd "$(dirname "$0")/../.."
cd packages/reader_core
flutter test test/snapshot
