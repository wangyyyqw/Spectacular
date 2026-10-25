# EPUB 引擎架构与开发者指南

> 面向后续开发者的一页式引擎全景：数据流、文件地图、设计决策、扩展方法。
> 状态基线：2026-10-25，P3（M2 资源浮动容错）+ P8（引擎完备）完成，面板 168/242。
> 配套阅读：[技术方案.md](../技术方案.md)（§51 级联、§60 块测量、§65 样式清单、§68 字体）、
> [开发方案/P8-引擎完备.md](../开发方案/P8-引擎完备.md)（任务与验收）、
> [验收记录/M2-真机测试.md](../验收记录/M2-真机测试.md) §7.1～7.6（演化日志）。

## 1. 全景数据流

```
EPUB bytes
  └─ openEpub（epub/epub_document.dart）
       ├─ 资源索引 resource_index（嗅探修复 P3-25）→ archive.readBytes
       ├─ 破损分级 L0~L4（epub/importer.dart；无 OPF 拼章 P3-26）
       └─ EpubDocumentImpl
            ├─ parseBlocks(spine) → BlockDocument（原始块树，fullBleed 判定用）
            └─ aggregateText(spine) → 聚合树（flat 管线主输入）
                  ├─ 纯图块折叠 → tag='img' 块（P3 图片路径）
                  ├─ InlineMark（行内样式标记 + 祖先链，P8-01/02）
                  └─ RubyMark（注音，P8-08）

EpubChapterSource.loadChapter（apps/…/epub_chapter_source.dart，flat 管线核心）
  ├─ 满屏图章判定（P3-10）→ 单页背景块
  ├─ collect(聚合树)
  │    ├─ 级联样式 styleForChain：链式 Cascade.compute（P8-02）
  │    │     规则 = uaRules()（P8-03，134 条对标）+ 作者样式表 + 内联 style
  │    │     视图 = _NodeView(SelectorElement)（含兄弟池）
  │    │     缓存 = 链键（全属性排序拼接，P8-07 修缓存污染）
  │    ├─ display:none 子树剔除（P8-07）
  │    ├─ 图片块（float 检测三来源 + inline-block 小图并排 P8-06）
  │    ├─ 表格块（collectTable：两遍列宽→网格→行边界切分，P8 表格接入）
  │    ├─ 伪元素 content 注入 + ::first-letter run（P8-09）
  │    └─ 文本块：layout(runs) + rubies + 盒传导（背景/边框拼合 P8-05）
  ├─ 浮动章 → _paginateWithFloats（FloatOccupancy 区间模型）
  └─ 其余 → Paginator.measureChapter（分页状态机）+ PageIndex 重放

渲染 PageRenderer（reader_core/paint/page_renderer.dart）
  阶段：背景→块背景→块边框→文本→装饰（emphasis）→注音（P8-08）→选区
  几何：leftInset/rightInset 双侧收窄（P8-05）；overlay 切片（浮动，P3-P8）
```

## 2. 文件地图（按子系统）

| 子系统 | 文件 | 职责 |
|---|---|---|
| **CSS 级联** | `reader_core/css/cascade.dart` | Cascade.compute：三源+!important+特异性+@media+18 项继承；CascadeRule.fromStylesheet（作者契约过滤 P7-17） |
| | `reader_core/css/selector.dart` | SelectorParser（csslib AST→ComplexSelector）；组合器 4 种；属性/结构伪类；Specificity 四元组；**SelectorElement 视图接口 + ParsedElementView**（flat 树接入点） |
| | `reader_core/css/ua_stylesheet.dart` | `uaStylesheetCss`（134 条对标 WHATWG/Reeden 630）→ `uaRules()`；UaBlockDefaults（快照 harness 旧路径） |
| | `reader_core/css/computed_style.dart` | 计算样式全字段（§65 清单）；values/explicitProperties |
| **flat 管线** | `apps/…/epub_chapter_source.dart` | collect/级联接线/图片/表格/浮动/伪元素/ruby 透传/盒传导——**单文件主战场，~1700 行** |
| **分页** | `reader_core/layout/paginator.dart` | PageBlock（+table/floatSide/rubies 载荷）/PageBlockSlice（+overlay/absoluteTop）/measureChapter |
| | `reader_core/layout/float_occupancy.dart` | 浮动区间模型（insert/occupiedLeftAt/take 跨页） |
| | `reader_core/layout/table_layout.dart` | TableMeasurer/GridMeasurer/Grid/Paginator + TableRenderSpec（渲染载荷） |
| **聚合** | `reader_core/parser/text_aggregator.dart` | 纯图折叠/InlineMark+链/RubyMark/white-space 模式 |
| | `reader_core/parser/full_bleed.dart` | 满屏判定（**注意 P3-30 修的 ParsedText 正文计数缺陷**） |
| **渲染** | `reader_core/paint/page_renderer.dart` | 绘制阶段机；_paintTable/_paintRubies/列表标记/边框拼合路径 |
| **UI** | `reader_ui/reader_page.dart` | ReaderPage（页脚第一槽 P8-10）/ReaderView 手势（safeEdge 24 逻辑像素！自动化点击勿贴边） |
| | `reader_ui/reader_session.dart` | 虚拟页窗口/进度持久化/重排失效矩阵 |
| **字体** | `reader_core/css/font_face.dart` + `book_font_loader.dart` | @font-face 提取/注册（bookId 族名隔离）；app 侧 `_ensureBookFonts`+`_mapBookFontFamilies` |

## 3. 关键设计决策（为什么是这样）

1. **flat 管线 vs 块流盒树**：引擎层有完整 BlockFlow 树（P2 建），但 app 阅读走「聚合树→块序列」的 flat 管线。P8-05 用**盒传导近似**（背景/边框透传子块 + 水平间距相加 + first/last 拼上下框）替代真嵌套盒子——改动集中在 styleForChain 一处。若未来做真盒树（P8-05 完全体），flat 决策点已内聚。
2. **SelectorElement 视图接口**：级联匹配与 DOM 类型解耦。原始树用 ParsedElementView，flat 聚合树用 `_NodeView`（兄弟池=父的子视图）。新增树源实现三 getter 即可接入。
3. **链式级联 + 前缀缓存**：body→div→p 逐级 compute（parent=上级结果），继承天然正确；同容器兄弟共享祖先前缀缓存。缓存键**必须含全部属性**（P8-07 教训：[hidden] 曾被同标签兄弟污染）。
4. **级联缓存/页索引不覆盖浮动章与伪元素文本**：浮动章走手动分页（无 PageIndex 重放）；伪元素 content 拼入块文本后 CFI 偏移不含生成文本（flat 近似，已记录）。
5. **UA 刻意差异**：li margin-left 40px 承担缩进（flat 无 ul 盒子）；img 默认 display:inline（不能给 inline-block——否则全图误浮动，P8-06 教训）；盒传导跳过 ul/ol/li（防双重缩进）。
6. **空章合法性**：书作者可用 display:none 隐藏制作页等章（级联正确产物），VirtualPager 按 P2-32 跳过；多书冒烟断言「非空章存在」而非「每章非空」。

## 4. 测试与门禁（提交前必跑）

```bash
bash tool/run_all.sh            # 三包全量（reader_core/ui + mobile）
bash tool/check_core_boundary.sh
bash tests/analysis/verify_strict_flags.sh
bash tests/tool/verify_core_boundary.sh
REAL_EPUB=1 flutter test test/reader/multi_book_smoke_test.dart   # 七本真书（apps/reader_mobile 下）
STYLE_REGRESSION_UPDATE=1 flutter test test/snapshot/style_regression_test.dart  # 基线更新（reader_core 下，预期差异才用）
```

分域回归速查：CSS 引擎 `test/css/`；聚合 `test/parser/`；分页 `test/layout/`；flat 接线 `apps/…/test/reader/`（author_css/float_flat/table_flat/ruby_flat/pseudo_flat）；页脚 `reader_ui/test/page_footer_test.dart`。

## 5. 扩展指南

- **新 CSS 属性**：ComputedStyle 解析（computed_style.dart）→ 确认是否入 Cascade.inheritedProperties → flat 消费点（styleForChain 盒传导白名单 `_promotedBoxProps` 或渲染层）。
- **新选择器语法**：csslib AST → SelectorParser._parseComplex 增分支（参考 AttributeSelector/PseudoClassFunctionSelector 现例）→ selector_test 补「支持/不支持」清单。
- **新块类型载荷**：仿 table/rubies：reader_core 定义载荷类 → PageBlock 加字段 → PageRenderer 加绘制分支/趟 → app collect 构造 → 专项 flat 测试。
- **新页家具槽**：reader_page.dart Stack 内 Positioned（仿页脚第一槽）；模板占位符在组装处替换。

## 6. 已知近似与后续方向（按价值排序）

1. 相邻段 margin 折叠未实现（flat 近似，段距可能偏大）。
2. 伪元素 CFI 偏移、浮动章行内样式区间不映射（均记录于 §7.5/7.6）。
3. 特异性 vs @layer、兄弟组合器连续场景（`A + B + C`）限制。
4. 真嵌套盒模型（上下边框圆角拼合、负 margin 穿透）——P8-05 完全体。
5. 6 槽页家具其余五槽与设置项；::first-letter 的排版级首字下沉（现为 run 近似）。
6. 表格格级 CFI/选区；SVG 矢量渲染（现为 [OBJ] 占位/封面 jpg 链）。
