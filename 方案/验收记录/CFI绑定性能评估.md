# CFI 文本节点绑定性能评估

> 日期：2026-10-23　执行人：Lead
> 问题：给每个文本节点构造 CFI，导入 EPUB 时会不会很卡、很慢？

## 1. 结论

**当前实现不会在导入时全量绑定。** `openEpub` 只做容器/OPF/目录/资源索引，`EpubDocumentImpl.bindCfi(spineIndex)` 是按章调用、可按需丢弃的接口。

如果强行在导入时给全部文本节点绑定并保留对象，实测确实有明显代价：

| 项目 | 实测（macOS 桌面，Debug/Flutter test） |
|---|---|
| 样本 | 《诸神愚戏》148MB，1541 个 spine，323,206 个文本节点 |
| `openEpub` | 约 1.05s（不含 CFI 绑定） |
| 绑定 100 章 | 118ms，约 6µs/节点（含预热） |
| 绑定全部 1541 章 | 817～1128ms，约 3.5µs/节点 |
| 保留全部绑定对象后的 RSS 增量 | 约 +220MB（551MB → 771MB） |

因此：**全量绑定 + 常驻 ≈ 多 1 秒导入时间、多 200MB 内存**。桌面可接受，移动端会更慢、更容易触发 GC/OOM，不建议在导入阶段做。

## 2. 建议

1. **保持按章懒绑定**（当前实现）：打开章节时调用 `bindCfi`，切章释放或 LRU 缓存；不预绑定全书。
2. **若要全书预索引**，不要为每个节点存完整 `EpubCfi`；存紧凑路径（int 步进 + 文本节点序号 + 偏移），需要时再物化成 CFI。
3. **共享祖先路径**：同一元素下的文本节点复用元素路径，避免每个节点重复存 `/6/…/4/…` 的完整步进。
4. **跳过纯空白文本节点**：只有参与排版的文本才需要 CFI；可显著减少节点数。
5. 只在文档树/布局真正需要时绑定，布局、分页、绘制阶段不重新构造。
6. 在目标移动设备上用 release/profile 复测一次，桌面数据不能直接外推。

## 3. 复现方式

临时基准（不提交）：`flutter test test/bench/cfi_bench_test.dart`，读取本地 `test_corpus/real/zhushen-yuxi.epub`，循环 `document.bindCfi(i)` 并统计 `Stopwatch`、`ProcessInfo.currentRss`。基准文件已删除，避免进入 CI/仓库。

## 4. 关联

- 实现：`packages/reader_core/lib/parser/cfi_binder.dart`、`EpubDocumentImpl.bindCfi`
- 任务：P1-12；CFI 全序与序列化：P1-10/P1-11
- 文档树落地后（P1-14）应按章构建，不在导入阶段全量绑定。
