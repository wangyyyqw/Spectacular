# 快照工具

P0-23 的页序列哈希基建。真实页数据要等 P2-25 接入分页器后替换为 `PageSlice` 渲染结果；当前用页文本 + 标注摘要验证“固定配置下稳定、配置/内容/顺序变化必变”。

## 文件

- 哈希实现：`packages/reader_core/lib/paint/page_snapshot.dart`
- 测试：`packages/reader_core/test/snapshot/page_snapshot_test.dart`
- 运行：`bash tool/snapshot/run.sh`

## 为什么没有 `tool/snapshot.dart`

`tool/` 不是 Dart 包，直接放脚本无法 `import package:reader_core`；把哈希器放进 `reader_core` 并由包内测试运行，避免复制实现。该偏差登记在《P0 文档》附录 A-05。

## 使用约定

- 固定字段：视口宽高、DPR、字族、字号、行高、语言、字距、主题、书写模式。
- 同一输入两次哈希必须相等；任何配置或页内容变化必须导致哈希变化。
- 失败时先确认是预期变更还是回归；预期变更需更新基线并写明原因。
