# EPUB 引擎优化与浏览器对照（2026-10-31）

## 范围与架构结论

本轮保留原生「解析 → 样式 → 布局 → 分页 → 自绘」管线，不引入 WebView，
不更换依赖、不迁移数据。检查真源后，先修样式阶段的重复工作与选择器失效，
没有把属性解析成功、样式声明覆盖率或单一基准提速等同于完整浏览器兼容。

- `reader_core/css` 负责选择器、层叠、继承；规则索引此前重复写在宿主章节源里。
- `EpubChapterSource` 仍是六千余行的编排模块，同时承担资源、生成内容、样式、
  表格与分页接线。不能仅拆文件就宣称完成架构重构；本轮只抽出可独立验证的规则集。
  原有超长编排函数暂作例外保留，避免同时搬迁表格/分页带来无法归因的回归；
  新增结构获取与候选索引函数分别控制在 40 行内。
- 普通章节首次打开先 `parseBlocks()` 再 `parseDocument()`，实际解析同一 XHTML
  两次。正文布局重新创建的兄弟视图身份不一致，使 `nth-*` 等选择器无法匹配。
- 原有 94 组浏览器对照有 61 项几何/样式失配，分布在 9 组用例；不能简单归因于
  所有相应属性都不支持，其中包括 Range 字体盒与 CSS 行盒的计量差异。

## 实现

| 位置 | 改动与约束 |
| --- | --- |
| `packages/reader_core/lib/css/cascade_rule.dart` | 规则模型从层叠算法独立出来；原 `cascade.dart` 导出路径保持兼容 |
| `packages/reader_core/lib/css/cascade_rule_set.dart` | 只读稳定排序规则集，按末端 id/class/tag 建候选桶，保留文档顺序并去重 |
| `packages/reader_core/lib/css/cascade.dart` | 已编译规则不再逐元素重新排序；原 List 调用方式继续可用 |
| `packages/reader_core/lib/css/selector.dart` | 否定参数和 An+B 预编译，修正否定参数特异性，去掉匹配时无必要的祖先列表复制 |
| `apps/reader_mobile/lib/reader/epub_chapter_source.dart` | 满屏判定与正文块树来自同一次解析；聚合结果和结构视图成对缓存，重排/重放保持身份；普通块布局复用原始元素，祖先键按视图缓存 |
| 同上 | 两处重复候选筛选统一调用核心规则集；`::before`/`::after` 的规则只编译一次 |

候选索引**不缓存最终匹配结论**：属性、祖先、兄弟、媒体条件和内联声明继续逐元素
检查。宿主仅在候选规则不依赖结构位置时共享同形元素样式；祖先、兄弟组合器以及
否定参数中的结构伪类均参与依赖判断，避免 UA 的 `dd + dt` 无谓禁用普通段落共享。
移除已无调用的旧 `parseCompound()` 否定参数解析入口。
缓存不跨章节共享，候选表不持有元素；结构视图与已有聚合缓存同生命周期，
只保存元素视图，不再保留一份原始文本树。此处增加了元素视图内存，长书连续遍历的
内存峰值仍需真机测量。

新增选择器能力：`nth-of-type()`、`nth-last-of-type()`、`nth-last-child()`、
`last-of-type`、`only-child`、`only-of-type`；支持 odd/even、正负 An+B。
`:not([attr])`、`:not(:first-child)` 等单一参数可以参与匹配；`:not(#id)` 按 ID
特异性，`:not(tag)` 按类型特异性，通配符不增加特异性。

## 浏览器实测

环境：Flutter 3.47.5 / Dart 3.13.4，Google Chrome 156.0.8078.74。
沿用已有 CDP 对照工具：350×800、DPR 1、相同思源宋体；用例打包成最小 EPUB 后
经过实际章节源渲染，并非只比较计算样式。没有修改容差、跳过条件或快照基线。

| 用例 | 改前几何/样式失配 | 改后 | 改前墨迹形状差 | 改后 |
| --- | ---: | ---: | ---: | ---: |
| 98-structural-selectors | 10 | 2 | 9.64% | 0.38% |
| 99-not-specificity | 7 | 0 | 4.10% | 0.39% |

- 新增用例合计从 17 项降到 2 项，没有未配对块；已人工检查并排截图。
- 98 的剩余两项来自同一行的行顶口径：浏览器 Range 顶为 116px、字体盒高 31px，
  CSS 行盒顶为 120px、高 24px；引擎行顶 119.496px。实际基线分别为 141px 和
  141.011px。暂保留报告中的计数，不通过扩大容差掩盖它。
- 原有 94 组引擎 JSON 和 PNG 与改前逐字节一致；96 组总失配从 78 项降到 63 项。
  原有 61 项没有冒充本次已修复。
- 输出目录：`/tmp/spectacular-css-before/` 与 `/tmp/spectacular-css-after/`。
  `report.md` 是全量报告，`side_98-structural-selectors.png`、
  `side_99-not-specificity.png` 左侧浏览器、右侧引擎；产物不提交。

复现命令（仓库根目录，`CSS_PARITY_OUT` 建议指定绝对路径）：

```sh
CSS_PARITY_OUT=/tmp/css-parity-check node tool/css_parity/render_browser.mjs
(cd apps/reader_mobile && CSS_PARITY=1 CSS_PARITY_OUT=/tmp/css-parity-check \
  flutter test --no-pub test/css_parity/parity_dump_test.dart)
CSS_PARITY_OUT=/tmp/css-parity-check /usr/bin/python3 tool/css_parity/compare.py
```

## 性能证据与限制

核心规则基准：602 条规则，400 次计算，预热后取 5 次中位数；原始全规则路径
145.11ms，预编译候选路径 9.77ms，候选 2/602。这只证明规则筛选/排序阶段的收益，
**不等同于整本书或手机提速 14 倍**；原宿主此前已有一层粗筛。

真实书《诸神愚戏》，344×700、默认阅读设置，同机独立进程抽样（单位 ms）。
改前为本轮开始时的一次样本；改后独立运行三次，表中取中位数，未与其他测试并发。

| 阶段 / spine | 改前 | 改后 | 页数 |
| --- | ---: | ---: | ---: |
| 首访 29 | 2222.467 | 1731.542 | 20 → 20 |
| 首访 30 | 307.649 | 279.648 | 11 → 11 |
| 首访 47 | 121.021 | 118.782 | 11 → 11 |
| 页缓存 29 | 0.134 | 0.120 | 20 → 20 |
| 页缓存 30 | 0.028 | 0.025 | 11 → 11 |
| 页缓存 47 | 0.018 | 0.017 | 11 → 11 |
| 索引重放 29 | 224.516 | 227.664 | 20 → 20 |
| 索引重放 30 | 121.120 | 185.395 | 11 → 11 |
| 索引重放 47 | 82.965 | 51.156 | 11 → 11 |

首访 29 抽样下降约 22.1%，但重放 30 从 121.120ms 增至 185.395ms（改后三次
183.799–185.923ms），属于明确未解决的性能回退；重放 29 基本持平。样本包含
JIT/字体初始化且不是统计性真机基准，不能据此宣称所有路径加速。正确区分同形
元素后，已恢复无结构依赖时的安全共享，未用错误匹配换取速度；下一步优先剖析
spine 30 重放中的样式/布局热点与分配。

原始记录：`/tmp/spectacular-css-before/navigation.json`，
`/tmp/spectacular-css-after/navigation-final.json`、`navigation-final-2.json`、
`navigation-final-3.json`。

```sh
(cd packages/reader_core && CASCADE_BENCH=1 \
  flutter test --no-pub test/bench/cascade_bench_test.dart)
(cd apps/reader_mobile && flutter test --no-pub \
  --dart-define=RUN_REAL_BOOK_BENCHMARK=true \
  --dart-define=EPUB_BENCHMARK_REPORT=/tmp/navigation.json \
  test/reader/real_book_navigation_benchmark_test.dart)
```

## 回归范围与后续边界

- `bash tool/run_all.sh`：三包静态检查均无问题；核心 1264、UI 170、宿主 390 项
  通过，合计 1824 项；另有 9 项显式开关/环境条件跳过，CSS 对照与真实书基准已
  另外显式运行。最终日志：`/tmp/spectacular-engine-final-validation.log`。
- `tool/check_core_boundary.sh`、`tests/analysis/verify_strict_flags.sh`、
  `tests/tool/verify_core_boundary.sh` 全部通过；严格分析探针与全量分析串行执行。
- 新增核心测试覆盖只读稳定排序、候选去重、分组最高特异性、上下文变化、媒体条件、
  结构伪类与否定参数；端到端测试锁定普通块流、隐藏后源树计数、重放/重排与 CFI。
- 相对字号、行内盒、《诸神愚戏》卡片以及索引重放继续使用原有测试和原断言，
  不通过改预期值接受渲染回退。
- `:is()` / `:where()` / `:has()`、复合或列表形式的 `:not()`、`nth-child(... of S)`
  尚未扩展。现有 csslib 的 AST 能力有限，下一轮先补解析/特异性规范用例，再接入，
  不用正则替换现代选择器来制造“支持”。
- 表格与行内合成盒仍有独立节点适配；本轮不宣称所有布局分支的结构选择器已统一。
  Grid、复杂 flex 约束、嵌套计数器作用域、跨页盒装饰也不属于本轮实现。
- 原有着重号、CJK 间距和行盒对照差异、索引重放耗时、长书缓存内存与 USB 真机手势
  尚需后续验证。优先统一行盒/基线对照并剖析重放热点，再扩大布局支持面。

## 第二轮（同日）：styles 层块缓存，消除索引重放重建

临时探针定位（`SPECTACULAR_PROFILE`，定位后已移除）显示，spine 30 重放
183.7ms 中 `collect`（聚合树 → 级联样式 → 行测量）占 148.3ms，级联 56.3ms，
`PageIndex.apply` 仅 1.7ms；页索引本身不是瓶颈，瓶颈是每次重放都重建块树。

实现：`EpubChapterSource` 新增按 `paginationKey` 索引的 styles 层块缓存，
保存正文块与固定定位块，LRU 上限 5 章，与页缓存一致；命中后直接进入
`_paginateBlocks`，仍优先走页索引重放，索引缺失/损坏时用缓存块重新分页。
排版字段（字号/行高/段距/对齐/页边距）或几何变化时与页缓存同步清空；
`clearPaginationCache()` 只清页缓存，保留块缓存以服务重放。缓存报告增加
`块缓存 n/5 章`，并新增命中/失效/LRU 测试。块对象均为不可变值，重放只读；
索引校验失败时仍回退 `Paginator`，不把旧块当成免校验结果。

真书《诸神愚戏》344×700，同一基准、独立进程（单位 ms，页数不变）：

| 阶段 / spine | 改前（本轮基线） | 改后 |
| --- | ---: | ---: |
| 首访 29 | 2030.487 | 1984.642 |
| 首访 30 | 361.053 | 344.183 |
| 首访 47 | 125.000 | 123.098 |
| 页缓存 29/30/47 | 0.136/0.029/0.019 | 0.127/0.027/0.019 |
| 索引重放 29 | 374.100 | 3.126 |
| 索引重放 30 | 190.359 | 0.338 |
| 索引重放 47 | 43.472 | 0.173 |

首访仍包含真实重建成本，本表不宣称其加速；重放的下降来自复用已测量块树，
不是放宽索引校验。原始记录：`/tmp/navigation-now.json`（改前）、
`/tmp/navigation-block-cache.json` 与 `-2.json`（两次改后独立运行；重放
29 分别为 5.496/3.126ms，其余阶段差异在抽样噪声内）。

当前回归：`reader_core` 1306 项通过、4 项跳过；`reader_ui` 170 项通过；
`reader_mobile` 431 项通过、5 项跳过、4 项失败。4 项失败为 HEAD 上已存在
的 flex `align-content` 与行内盒/表格布局用例（临时移除本轮改动后同样失败），
不属于本次缓存变更；另 `reader_core` 分析有 2 条既有 info（`computed_style.dart`
空安全写法、`html5_input.dart` 初始化形参），本轮未改。块缓存的常驻内存为
最多 5 章块树，长书连续遍历的真机内存峰值仍需测量。

规范依据（已读取官方文档并以本机 Chromium 实测核对）：

- [Selectors Level 4：特异性](https://www.w3.org/TR/selectors-4/#specificity-rules)
- [Selectors Level 4：结构伪类](https://www.w3.org/TR/selectors-4/#structural-pseudos)
