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
- 已支持 `:is()`、`:where()`、`:has()`、列表形式 `:not()` 与
  `:nth-child(An+B of S)` / `:nth-last-child(An+B of S)`。`:where()` 取零特异性；
  其余函数取参数列表最高特异性，`nth-child(... of S)` 另加伪类自身 `(0,0,1,0)`。
  参数列表非法时整条规则跳过并告警，未复刻浏览器的宽容列表丢弃语义。
- csslib 仍不能完整解析上述函数伪类。实现采用括号/方括号/引号/注释感知的平衡扫描，
  将整条选择器替换为占位类，csslib 解析后恢复原文；没有用正则拼接语法树。
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

## 第三轮（同日）：document 层缓存有界

块缓存解决重放重建后，`_displayDocumentCache` 仍按 spineIndex 永久保存每章
聚合树与完整选择器视图；1541 章连续遍历时这是最大的一块无界增长。页缓存和
块缓存的 LRU 不会回收它，且旧几何下的条目也不会自动释放。

实现：document 层同样改为 LRU 5 章，命中时刷新顺序，超限淘汰最久未用章；
排版字段或几何变化时与块缓存一起清空；`cacheReport` 增加
`文档缓存 n/5 章`。该缓存只服务块重建，淘汰后再次访问会重新解析/聚合，
不影响页索引校验或渲染结果。

验证：新增 LRU 测试连续加载 8 章后文档缓存保持 `5/5`，排版字段变化后为
`0/5`；真书重放 29/30/47 为 5.244/0.495/0.175ms，页数仍为 20/11/11，
未因缓存淘汰回退。原始记录：`/tmp/navigation-doc-bounded.json`。

仍未处理：`_pageBackgrounds`、`_chapterSheetCache`、`_fullBleedCache`、
`_imageIntrinsicCache` 等按章/按资源的轻量索引仍会随遍历增长；它们不保存
完整文档树，但真机长书内存峰值与淘汰策略仍需测量后决定。

## 第四轮（同日）：现代函数选择器与样式表截断修复

问题有两层：一是 `SelectorParser` 不认识 `:is()`、`:where()`、`:has()`、列表
`:not()` 和 `nth-child(... of S)`；二是 csslib 在样式表阶段遇到这些选择器后会
留下后续 token，导致同一张表里紧随其后的普通规则也丢失。只补匹配器而不修复
样式表入口，仍会把“部分规则生效”误判为支持。

实现：

- 选择器层先提取函数伪类，替换为可被 csslib 解析的占位伪类，再编译参数。列表参数、
  An+B 与 `of S` 过滤只编译一次，匹配阶段不重新解析文本。
- `:is()` / `:where()` / 列表 `:not()` 支持复合选择器参数；`:has()` 支持缺省后代、
  `>`、`+`、`~` 四种相对组合符，并按左到右的正向链匹配
  `div:has(> p .deep)` 这类继续组合的后代关系。
- `nth-child(An+B of S)` 先按 `S` 过滤兄弟，再计算正序/倒序位置；
  `usesTreePosition` 对 `:has()`、列表参数中的结构伪类递归传播，避免宿主错误共享
  依赖兄弟位置或子树的最终样式。
- 样式表层对规则前导做平衡扫描，只替换含现代函数伪类的完整选择器；解析完成后按
  占位符精确恢复。无现代选择器时原 CSS 原样交给 csslib，不改变既有解析路径。

验证：新增选择器匹配、最高特异性、`:has()` 相对链、`of S` 过滤、样式共享依赖、
端到端级联与“现代选择器不截断后续规则”测试。`reader_core` 全量
1313 项通过、4 项跳过；`reader_ui` 170 项通过；`reader_mobile` 431 项通过、
5 项跳过、4 项失败。4 项失败仍是既有 flex `align-content`、空行内盒、行内块表格
和跨块行内样式用例，与本次选择器改动无关。三包静态检查均无新增问题；
`reader_core` 仍只有 `computed_style.dart` 与 `html5_input.dart` 两条既有 info。

本轮没有为选择器编译增加真实书耗时基准，因此不宣称现代选择器带来性能收益；
其主要收益是规则正确生效且不再截断后续样式。`p::first-letter`、`:lang()`、
完整宽容选择器列表和全部布局分支的结构视图统一仍待后续处理。

规范依据（已读取官方文档并以本机 Chromium 实测核对）：

- [Selectors Level 4：特异性](https://www.w3.org/TR/selectors-4/#specificity-rules)
- [Selectors Level 4：结构伪类](https://www.w3.org/TR/selectors-4/#structural-pseudos)

## 第五轮（同日）：轻量派生索引有界

第三轮只限制了文档树与已测块树，章节样式来源、满屏判定、white-space 判定、
图片原始尺寸等索引仍会随长书遍历持续增长。本轮新增通用 LRU 定长缓存，并让
整页背景与 styles 块缓存同生命周期，消除两份缓存独立淘汰后“页还在、背景已丢”
的不一致。

实现：

- 新增 `reader/bounded_cache.dart`：基于 `LinkedHashMap` 的 `BoundedCache`，
  读取提升最近使用顺序，写入超限时淘汰最久未用项。
- 章节派生索引统一限制为 5 章，与页缓存、块缓存、文档缓存使用同一章节窗口：
  满屏分析、章节样式表来源、white-space 判定及其两遍保留文本。
- CSS AST 最多保留 32 张样式表；图片原始尺寸正值与缺失项分别最多保留 512 项。
  这些条目只含解析结果、路径或尺寸，不保存图片字节，也不缓存最终选择器匹配结论。
- 淘汰语义均为“下次访问时重建”，不改变渲染结果；图片尺寸回归重新读取压缩包，
  `white-space` 回归重新判定并聚合。
- `PageBackground` 并入 styles 层块缓存，页缓存保存已贴好背景的最终页；
  `clearPaginationCache()` 后从块缓存重放时仍会重新贴回同一背景。
- `cacheReport` 增加样式章索引、满屏索引、white-space 索引和图片正值索引的
  当前条目数/上限，供回归测试与长书诊断读取。

验证：

- `flutter analyze --no-pub` 通过。
- 新增缓存淘汰、命中顺序、删除/清空、章节索引上限及整页背景重放测试；
  定向回归 30 项全部通过。
- `reader_mobile` 全量 435 项通过、5 项跳过、4 项失败。失败仍为既有 flex
  `align-content`、空行内盒、行内块表格和跨块行内样式用例，与本次缓存改动无关。

真机对照环境：MEIZU 20、Android 16（API 36）、Android arm64 release APK
45.8MB；真实书《诸神愚戏》148.5MB、1541 章，USB 独立进程安装运行。单位 ms：

| 检查点 | HEAD 基线（文/图/完成） | 本轮（文/图/完成） |
| --- | ---: | ---: |
| 首开 spine 29 | 1587 / 1645 / 1841 | 1631 / 1703 / 1882 |
| 跳转 spine 30 | 222 / 237 / 287 | 226 / 242 / 276 |
| 跳转 spine 47 | 124 / 174 / 386 | 111 / 165 / 290 |
| 回访 spine 29 | 19 / 35 / 283 | 24 / 37 / 286 |
| 跳转 spine 32 | 342 / 348 / 614 | 342 / 359 / 376 |
| 再次打开（第二次） | 1446 / 1511 / 1710 | 1462 / 1531 / 1726 |
| 再次打开（第三次） | 1464 / 1530 / 1711 | 1453 / 1520 / 1718 |

本轮还完成 1541 章书内远跳 spine 1515：93 / 143 / 288ms，随后回访
spine 29 正常。单机单次样本受 JIT、字体与系统调度影响，且基线与本轮远跳序列
不完全相同，因此只用于发现明显回退，不宣称普遍提速；本轮主要收益是限制持续
遍历时的派生索引增长。

原始记录：`/tmp/spectacular-device-fifth-before/report.json`、
`/tmp/spectacular-device-fifth/report.json`。真机长书连续遍历的内存峰值仍未
测量；32 张 CSS AST 与 512 项图片尺寸的容量也需要在更多真实书样本上校准。

## 第六轮（同日）：保留 Flex 首片交叉轴偏移

多行 Flex 的 `align-content` 已在表格测量阶段生成首行顶部偏移，但分页器把预切
表格转换为首片时无条件减去 `rowYs[0]`，又把这段留白清零。修复只调整切片原点：
首片从内容盒顶部开始，保留 `rowYs[0]`；只有从后续行开始时，才把该行顶平移到
切片顶。未改变行高、Flex 分配或表格测量。

定向断言覆盖 `center` 与 `flex-end`：5 个等高单元的 `top` 分别为
`[20, 20, 70, 70, 120]` 和 `[40, 40, 90, 90, 140]`。修复前首片实际从 0 开始，
`center` 被错误显示为 `[0, 0, 50, 50, 100]`。

回归与静态检查：

- `reader_core`：1313 项通过、4 项跳过；静态分析仍只有
  `computed_style.dart` 与 `html5_input.dart` 两条既有 info。
- `reader_mobile`：437 项通过、5 项跳过、2 项失败；静态分析无问题。
- 剩余失败为既有 `empty_inline_block_test.dart` 空盒尺寸/基线断言，以及
  `inline_block_test.dart` 固定布局表格标签盒的节点数量断言；本轮未改相关布局。

真机继续使用 MEIZU 20、Android 16 和《诸神愚戏》148.5MB、1541 章。基线取
`HEAD`（a19d594），修复后为当前工作树；单位 ms：

| 检查点 | HEAD 基线（文/图/完成） | 本轮（文/图/完成） |
| --- | ---: | ---: |
| 首开 spine 29 | 1572 / 1636 / 1815 | 1561 / 1624 / 1806 |
| 跳转 spine 30 | 227 / 243 / 276 | 227 / 239 / 289 |
| 跳转 spine 47 | 111 / 142 / 290 | 110 / 162 / 290 |
| 回访 spine 29 | 20 / 36 / 285 | 29 / 42 / 291 |
| 跳转 spine 32 | 341 / 358 / 375 | 338 / 349 / 366 |
| 再次打开（第二次） | 1455 / 1520 / 1719 | 1447 / 1514 / 1712 |
| 再次打开（第三次） | 1492 / 1559 / 1755 | 1478 / 1550 / 1727 |

本轮额外完成 spine 1515 远跳：91 / 143 / 288ms，随后回访 spine 29 正常。
单机单次样本只用于发现明显回退，不据此宣称普遍提速。原始记录：
`/tmp/spectacular-device-sixth-before/report.json`、
`/tmp/spectacular-device-sixth/report.json`。

正式 APK：`apps/reader_mobile/build/app/outputs/flutter-apk/app-release.apk`，
包名 `com.spectacular.reader_mobile`，45.7MB，SHA-256
`28e71f351b2cef1f982ac9314e0a156df9acd927f181a5881ebd48cc4227c37e`。

## 第七轮（同日）：真机复验与测试断言校正

第六轮报告中的两项失败已复核为测试假设错误，不是渲染回退：

- `empty_inline_block_test.dart` 的 HTML 实际在红色外层 `span` 之后还有普通文字
  后缀，`runs` 应为 `[0,4]` 红字与 `[4,7]` 默认色两段，旧断言错误地要求单段。
- `inline_block_test.dart` 的 `RANK: ` 不属于 `SSS` 的加粗大字号标签，
  `runs` 应为 `[0,6]` 普通标签与 `[6,9]` 的 24px 粗体 `SSS` 两段。

只修正测试区间，没有改布局代码、容差或基线。`reader_mobile` 全量回归为
**439 项通过、5 项跳过、0 失败**，`flutter analyze --no-pub` 无问题。

设备恢复后重新测量当前生产代码，环境仍为 MEIZU 20、Android 16 和
《诸神愚戏》148.5MB、1541 章。单位为 ms：

| 检查点 | 文/图/完成 |
| --- | ---: |
| 首开 spine 29 | 1569 / 1633 / 1814 |
| 跳转 spine 30 | 221 / 239 / 287 |
| 跳转 spine 47 | 111 / 160 / 291 |
| 远跳 spine 1515 | 93 / 144 / 292 |
| 回访 spine 29 | 27 / 42 / 291 |
| 跳转 spine 32 | 351 / 367 / 383 |
| 再次打开（第二次） | 1457 / 1523 / 1721 |
| 再次打开（第三次） | 1463 / 1529 / 1727 |

原始记录：`/tmp/spectacular-device-seventh/report.json`。该轮仅复验第六轮生产代码，
不代表后续修复的性能结论。

## 第八轮（同日）：原子行内盒内部着重号

审计剩余项中，普通文本和普通行内 run 已能绘制着重号，但 `display: inline-block`
的 `PageBlock` 载荷进入 `_paintInlineBoxContent()` 后只画文字，不执行着重号趟。
因此盒内的独立 `text-emphasis`、颜色、上下位置和基线位移全部丢失。这是绘制路径
遗漏，不是解析或级联问题；内盒 `StyledRun` 已保留正确样式。

实现：

- `page_renderer.dart` 的横排原子盒内容复用 `HorizontalTextEmphasis`，每行只创建
  一次标记缓存，并与正文共用同一 `TextPainter`、行原点和实际基线。
- 嵌套原子盒仍递归进入同一函数；无着重号的内盒只做一次 `hasMarks` 判断，不增加
  逐行选区查询。
- 竖排原子盒仍走 `_paintVerticalColumns()`，本轮不宣称竖排内着重号已支持。

验证：

- 新增核心像素回归：构造 `PageBlock` 原子盒载荷，旧代码红色标记数为 0，修复后
  为 2；`inline_emphasis_test.dart` 13 项通过。
- 新增实际 CSS/章节源回归：内盒 `text-emphasis: circle #cc0000` 的 run、颜色与
  区间保留；`inline_block_test.dart` 与空盒测试合计 20 项通过。
- 新增浏览器对照 `104-atomic-inline-emphasis`，覆盖盒内上方圆点、下方芝麻点与
  混合内外文字。原始像素差 **0.05%**、墨迹形状差 **0.08%**、未配对 **0**；
  已人工检查并排图，盒内标记位置与浏览器一致。报告的 2 项失配来自浏览器不单独
  导出原子盒内部文本行，不是可见几何差异。
- `reader_core` 全量 **1314 项通过、4 项跳过**；`reader_mobile` 全量
  **440 项通过、5 项跳过、0 失败**。移动端静态分析无问题；核心仍有
  `computed_style.dart` 与 `html5_input.dart` 两条既有 info。

真机继续使用 MEIZU 20、Android 16 和《诸神愚戏》148.5MB、1541 章。单位为 ms：

| 检查点 | 第七轮 | 第八轮 |
| --- | ---: | ---: |
| 首开 spine 29 | 1569 / 1633 / 1814 | 1583 / 1646 / 1827 |
| 跳转 spine 30 | 221 / 239 / 287 | 224 / 236 / 285 |
| 跳转 spine 47 | 111 / 160 / 291 | 126 / 174 / 389 |
| 远跳 spine 1515 | 93 / 144 / 292 | 92 / 126 / 290 |
| 回访 spine 29 | 27 / 42 / 291 | 28 / 43 / 292 |
| 跳转 spine 32 | 351 / 367 / 383 | 330 / 342 / 359 |
| 再次打开（第二次） | 1457 / 1523 / 1721 | 1464 / 1528 / 1709 |
| 再次打开（第三次） | 1463 / 1529 / 1727 | 1467 / 1534 / 1712 |

第八轮首开与 spine 47 有十几到近百毫秒波动，远跳、回访、spine 32 与重复打开
未显示明确回退；单次样本不据此宣称整体加速或回退。原始记录：
`/tmp/spectacular-device-eighth/report.json`。

正式 APK 已重建并安装：
`apps/reader_mobile/build/app/outputs/flutter-apk/app-release.apk`，通用包 89.6MB，
包名 `com.spectacular.reader_mobile`，SHA-256
`8b7d4fa3a510ca235a2d7385ed0b43da818109f97fa2ea661e9a23064034fc9c`。
下一项优先处理横向行盒/字体盒计量口径，再核对 `01-text-basic` 的第二行宽度；
不使用扩大容差掩盖 Range 字体盒与 CSS 行盒的差异。

## 第九轮（同日）：排版等价 run 保留标点挤压

`01-text-basic` 的第二行在浏览器中宽 85px，修复前引擎为 102px。差异不是行盒
取整，而是标点挤压没有生效：宿主 `resolveInlineRuns()` 会为普通 `<p>` 生成一个
覆盖全文的 `StyledRun`，其排版字段与块样式等价；`_measureSegment()` 却把
“存在任意 run”误判为“存在显式行内样式”，从而跳过 `text-spacing-trim`。

实现：

- `TextLayoutResult` 新增 `plainTextLayout`，表示现有 runs 只含颜色、装饰等不影响
  文本测量的差异。判断使用 `layoutFingerprint` 与非零 `baselineShift`，字号、字距、
  字体、行高、对齐、断行等任一排版字段变化仍视为显式行内样式。
- 标点挤压、中西文自动间距和实际基线计算改看该标记；绘制仍逐 run 取颜色与装饰，
  不通过删除 run 换取纯文本测量。分页切片、多栏重排、竖排、浮动文本切片以及章节源
  的宽度/竖排带对齐均传播该标记，避免派生布局重新丢失挤压。

验证：

- 新增核心回归：仅颜色不同的全文 run 与纯文本同宽并保留颜色；改变字号或基线位移的
  run 不按纯文本处理；分页切片保留标记。
- 新增真实章节源回归：默认 `trim-adjacent`、全文等价 run、两行断点下，第二行
  `点：、。！？` 宽 85px；修复前为 102px。
- `flutter analyze --no-fatal-infos`：`reader_ui` 与 `reader_mobile` 无问题；
  `reader_core` 仅有既有的 `computed_style.dart`、`html5_input.dart` 两条 info。
- 全量测试：`reader_core` **1317 项通过、4 项跳过**；`reader_ui`
  **170 项通过、0 项跳过**；`reader_mobile` **441 项通过、5 项跳过、0 失败**。
  `tool/run_all.sh` 当前会因上述两条既有 info 在 analyze 阶段退出，因此本轮按相同
  范围显式执行 `flutter analyze --no-fatal-infos && flutter test --no-pub`。

浏览器定向复跑只覆盖 `01-text-basic`，未重跑全部用例，不能据此宣称全量失配数下降：

| 指标 | 修复前 | 修复后 |
| --- | ---: | ---: |
| 第二行 `点：、。！？` 宽 | 102px | 85px |
| 几何/样式失配 | 2 | **0** |
| 原始像素差 | 2.25% | 2.23% |
| 墨迹形状差 | 0.89% | 0.76% |

输出目录：`/tmp/spectacular-css-line-ninth/report.md` 与
`side_01-text-basic.png`。剩余像素差仍包含 Range 字体盒、CSS 行盒与字体栅格的
口径差异，没有修改容差或跳过条件。

真机继续使用 MEIZU 20、Android 16 和《诸神愚戏》148.5MB、1541 章。单位为 ms：

| 检查点 | 第八轮（文/图/完成） | 第九轮（文/图/完成） |
| --- | ---: | ---: |
| 首开 spine 29 | 1583 / 1646 / 1827 | 1575 / 1648 / 1830 |
| 跳转 spine 30 | 224 / 236 / 285 | 226 / 240 / 288 |
| 跳转 spine 47 | 126 / 174 / 389 | 111 / 142 / 290 |
| 远跳 spine 1515 | 92 / 126 / 290 | 91 / 141 / 290 |
| 回访 spine 29 | 28 / 43 / 292 | 25 / 42 / 290 |
| 跳转 spine 32 | 330 / 342 / 359 | 344 / 357 / 374 |
| 再次打开（第二次） | 1464 / 1528 / 1709 | 1458 / 1537 / 1719 |
| 再次打开（第三次） | 1467 / 1534 / 1712 | 1465 / 1532 / 1729 |

八个检查点均正常完成，未出现错误；单次样本只用于发现明显回退，不据此宣称提速。
原始记录：`/tmp/spectacular-device-ninth/report.json`。

正式 APK 已重建、安装并启动：
`apps/reader_mobile/build/app/outputs/flutter-apk/app-release.apk`，通用包 89.6MB，
包名 `com.spectacular.reader_mobile`，SHA-256
`0fcf748a7febe15278bd4e326fb57c1e43f85c224a560db33b5dbf66f381f4c9`。
横向 Range 字体盒与 CSS 行盒的剩余计量差异仍未关闭，后续不使用扩大容差掩盖。

## 第十轮（同日）：Range 字体盒按逐行盒还原

`98-structural-selectors` 的剩余两项不是排版偏差：浏览器 Range 给出字体盒
`y=116, h=31`，引擎导出 CSS 行盒 `y=119.496, h=24`，双方基线分别为
`141` 与 `141.011`。旧对照器直接比较两种盒顶，新增的归一逻辑把字体盒顶按
`(31 - 24) / 2` 下移后得到 `119.5`。

归一必须使用引擎逐行 `line.h`，不能使用块的声明 `line-height`：

- `102-inline-emphasis` 的行盒高被更大的子字号撑到 72px，父块声明仍为 48px；
- `81-font-variant-caps`、`07-font-weight-style` 同样包含混排行内字号；
- `line-height: normal` 的行为由实际字体度量决定，不能折算成块级声明值。

使用块级声明行高试跑会把上述正常布局误报为新增失配，全量为 `77/13`；
改为逐行盒高度后恢复原有行高语义。只有 Range 字体盒高于该行盒时才归一，
字体盒仍在行盒内时保留原比较口径。

全量浏览器/引擎产物重跑结果：

| 指标 | 修复前 | 修复后 |
| --- | ---: | ---: |
| `98-structural-selectors` 失配 | 2 | **0** |
| 全量失配 | 65 / 11 个用例 | **63 / 10 个用例** |
| 未配对 | 0 | 0 |
| `98` 原始像素差 / 墨迹形状差 | 0.74% / 0.44% | 0.74% / 0.44% |

本轮只修正对照器，不改变引擎生产渲染，视觉指标不变。新增 Python 单测覆盖：
超大字体的居中还原、字体盒在行盒内时保持原值、真实 `2.5px` 行顶偏移仍报错。
产物目录：`/tmp/spectacular-css-full-ninth/report.md`、`side_98-*.png`。

仍按要求重建、覆盖安装并在 MEIZU 20、Android 16 上用《诸神愚戏》
148.5MB、1541 章运行真实 EPUB。单位为 ms：

| 检查点 | 第九轮（文/图/完成） | 第十轮（文/图/完成） |
| --- | ---: | ---: |
| 首开 spine 29 | 1575 / 1648 / 1830 | 1551 / 1622 / 1805 |
| 跳转 spine 30 | 226 / 240 / 288 | 225 / 239 / 288 |
| 跳转 spine 47 | 111 / 142 / 290 | 111 / 142 / 290 |
| 远跳 spine 1515 | 91 / 141 / 290 | 92 / 140 / 288 |
| 回访 spine 29 | 25 / 42 / 290 | 27 / 42 / 291 |
| 跳转 spine 32 | 344 / 357 / 374 | 342 / 356 / 373 |
| 再次打开（第二次） | 1458 / 1537 / 1719 | 1465 / 1532 / 1713 |
| 再次打开（第三次） | 1465 / 1532 / 1729 | 1485 / 1549 / 1730 |

八个检查点均正常完成；单次样本只用于发现明显回退，不据此宣称提速。
原始记录：`/tmp/spectacular-device-tenth/report.json`。

正式 APK 已重建、覆盖安装并启动：通用包 89.6MB，包名
`com.spectacular.reader_mobile`，SHA-256
`0fcf748a7febe15278bd4e326fb57c1e43f85c224a560db33b5dbf66f381f4c9`。
哈希与第九轮一致，符合本轮未修改生产代码的事实。
