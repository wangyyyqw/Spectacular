# CSS 属性实现审计（第 2 版）：解析位置 → 消费位置 → 是否真正生效

> 目的：把「引擎认了但没用」的属性摊开，按「影响 × 真实书频率」排待修顺序。
> 范围：`packages/reader_core/lib/css/*`（解析/层叠/计算）、`layout/*`、`paint/*`、`apps/reader_mobile/lib/reader/epub_chapter_source.dart`（flat 管线消费方）。
> 本文只做审计，不含代码改动。第 2 版替换此前所有分类与行号（第 1 版的 C 组 9 条里已有 5 条被本轮实现接通）。

## 0. 结论摘要

| 指标 | 数值 |
| --- | ---: |
| 真实书语料（`test_corpus/real/*.epub`） | 7 本 / 105 个 CSS |
| 语料中出现的不同属性名 | 132 |
| `ComputedStyle` 类型化字段 | 92 |
| **有字段且真正参与布局/绘制** | **98 条属性**（70 完整 + 28 部分） |
| **有字段但零消费（占位式）** | **0** |
| **无字段、仅留在 `values`** | D 组变体条目；逐项状态见 3.4（多数已接入、等价降级或明确不支持） |
| 本文覆盖的属性条目 | **142**（98 + 44） |
| `tool/css_parity/cases/` | 87 个用例（编号 01–90，缺 65、85、87） |

**本轮（第 1 版 → 第 2 版）的主要变化**：18 个属性从「占位/未处理」推进到真实消费（`writing-mode`、`columns` 族、inset、`display:inline-block`、`hyphens`/`word-break`/`overflow-wrap`、`font-variant`、`direction`、`overflow`、`transform` 2D、`filter`、渐变、`border-collapse`/`border-spacing`、`list-style-position`、逻辑属性、`opacity` 组合成等）；第 1 版的 Top #1（`font-weight: bolder` 失效导致 `<b>/<strong>` 不加粗）已修复。对照表见第 1 章。

两个仍然成立的判断：

1. **未知属性是「静默接受」而非拒绝。** `Cascade._consider`（`cascade.dart:548-570`）按属性名把任意 `property: value` 存进 `winners`，`ComputedStyle` 只类型化认识的那批，其余留在 `values` map 无人读取。「支持 132 个属性名」仍是假象。
2. **「有字段却没消费」已清零**——这类值在 `values` dump、`layoutFingerprint`、`parity_dump_test` 里都会看起来有效，因此审计仍要求新增字段时同步落地真实消费点；`initial-letter` 已接入首字下沉 run。

别名层伪支持已清零：`line-break`、`text-combine-upright`、`hyphens`、`text-orientation`、`writing-mode` 均有真实消费点。

行号快照：`2026-10-27 05:42 CST`，`HEAD 31ca095` + 工作树。**审计期间 `computed_style.dart`、`line_breaker.dart`、`paginator.dart`、`page_renderer.dart` 仍在被并发修改**（写作时 `computed_style.dart` 从 5363 行涨到 5487 行），行号会漂移；每行都附函数锚点，定位用附录 B 的脚本，别只信数字。

> 2026-10-30 状态补充：新增 `79-vendor-effect-aliases` 与
> `80-font-size-adjust`。前者把 WebKit 效果/变换前缀并入标准属性级联槽；后者
> 接入 `font-size-adjust` 的 x-height 计算与书籍字体度量。79/80 的几何与关键
> 样式失配均为 0；80 的 Chrome Range 高度仍按字体盒返回，对照工具已将逐行 y
> 按块顶 + CSS 行高归一。`81-font-variant-caps` 补齐 Chromium 同款小型大写
> 合成、全字符缩放与混合字号 CSS 行盒，几何/样式失配为 0。
> `82-border-image-background-attachment` 覆盖九宫格切割、`repeat`/`round`/`fill`
> 与固定底纹，几何/样式失配为 0、视觉差异 0.43%；同时修复 data URL 被整体
> 转小写和 `fill` 中间区域未按 repeat 规则平铺的问题。
> `83-backdrop-filter` 覆盖毛玻璃、灰度与半透明背景，几何/样式失配为 0；
> 当前实现受纯 Canvas 限制，以页面背景近似采样元素背后的已绘制内容，视觉
> 差异 3.62% 主要来自该近似与字体栅格。`84-text-combine-upright` 以
> `engine_only` 用例锁定竖排 2–4 位数字合并。`86-caption-side-empty-cells`
> 覆盖 `caption-side: top/bottom` 与 `empty-cells: show/hide`，几何/样式失配
> 与视觉差异均为 0；同时修正标题前后重复折叠表格外边距、空单元格占位和声明
> 高度。`89-font-kerning` 覆盖 `auto/normal/none` 的解析、继承与 `kern`
> 字形特性；同时补齐布局缓存键中的 OpenType 字体输入，几何/样式失配为 0，
> 3.88% 视觉差异来自字体抗锯齿与亚像素采样。`content: url()` 已接入伪元素
> 行内图片链路：相对地址按书内资源解析，宽高读取伪元素计算样式；组合文本、
> 前后图片与偏移重映射由章节源回归锁定。覆盖率与剩余属性名以
> `tool/css_parity/coverage.md` 的最新生成结果为准。本文的旧行号和「审计时」
> 分类保留为历史定位信息。

---

## 1. 本轮变化对照

### 1.1 从 C/D 组升到 A 组

| 属性 | 第 1 版 | 第 2 版 | 实现链（解析 → 消费） |
| --- | --- | --- | --- |
| `writing-mode` | 未处理 | **部分** ★ | `cs:1276`（`_parseWritingMode` cs:3909）→ `lb:768`（列布局）/`860`（竖排测量）/`2577`（`vertical-rl` 列序）/`2614`（写回布局）；`pg:1005`（`_verticalChunk` pg:1016 跨页列流）；`pg:1287` 说明竖排下 `lines` 即「列」 |
| `text-orientation` | 未处理（别名在） | **部分** ★ | `cs:1282`（`_parseTextOrientation` cs:3919）→ `lb:2504`（`upright`/`sideways` 逐字旋转） |
| `direction` | 未处理 | **完整** ★ | `cs:1288`（`_parseDirection` cs:3930）→ `isRtl` getter（cs:2149 附近）→ `lb:870/896/1397/1760`、`pr:624`、`hit_test.dart:113`（测量/绘制/命中三处同向） |
| `column-count`/`column-width`/`column-gap`/`column-rule`/`columns` | 未处理 | **部分** ★ | `_resolveColumns` cs:4116（读 4126/4128/4154/4159）→ `MulticolGeometry`（`pg:359/360/366/383`）、`column-rule` 绘制 `pr:1040` |
| `top`/`right`/`bottom`/`left`（inset） | 零消费 | **完整** ★ | `_parseOffset` cs:5034（读 1620/1627/1634/1641）→ `pg:847-850`（含 right/bottom 反解、`_shrink-to-fit`）→ `ecs:3723`（`isOutOfFlow`） |
| `position: relative` 偏移 | 无效果 | **完整** ★ | `cs:1414` → `ecs:3664-3680`（left 走左右 margin 等量、top 走段前距互补） |
| `display: inline-block` | 退化为 inline | **完整** ★ | `cs:1416`/`_parseDisplay` cs:5188 → `bf:537`；`ecs:2354/2785`；`pr:1502`（`_paintInlineBoxPlacements`）、`pr:1592`（`_paintInlineBoxContent`）、`pr:1539`（盒 opacity） |
| `hyphens` | 未处理（别名在） | **部分** ★ | `cs:1294`（`_parseHyphens` cs:3958）→ `lb:813` → `planSoftBreaks`（lb:911） |
| `word-break` | 未处理 | **完整** ★ | `cs:1298`（cs:3968）→ `lb:815` → lb:911 |
| `overflow-wrap`/`word-wrap` | 未处理 | **完整** ★ | `cs:1306`（cs:3978）→ `lb:814` → lb:911 |
| `font-variant`/`font-variant-caps` | 未处理（`small-caps` 丢弃） | **完整** ★ | `cs:1316`（`_parseFontVariantCaps` cs:3988；`font` 简写里也落成该长属性）→ `lb:2681`（`_fontFeatures`，`smcp` 等） |
| `overflow`/`overflow-x` | 未处理 | **完整** ★ | `cs:1367`（`_parseOverflow` cs:3939）→ `pr:1624`、`pr:648`（`clipsOverflow`） |
| `transform`/`-webkit-transform` | 未处理 | **部分** ★ | `_parseTransforms` cs:3659（读 1267）→ `pr:641`（块空间 `canvas.transform`）、`pr:661`（逐函数左乘） |
| `transform-origin` | 未处理 | **完整** ★ | `cs:1271`（`_parseTransformOrigin` cs:3803）→ `pr:675` |
| `filter`/`-webkit-filter`（含 `drop-shadow`） | 未处理 | **完整** ★ | `_parseFilters` cs:3466（读 1259）→ `pr:800`（`_withEffects`）、`pr:840` 附近（`_filterLayerPaint`）、`pr:819`（`_paintFilterDropShadow`，解析在 `cs:3615` `_parseDropShadow`） |
| `background-image: <gradient>` | 未处理（渐变丢弃） | **完整** ★ | `_parseGradient` cs:3144（读 1651）→ `pr:1792`（`backgroundGradient`）、`pr:1838`（`_gradientShader`） |
| `border-collapse`/`border-spacing` | 零消费 | **完整** ★ | `cs:1577`/`cs:1606`（cs:4996/5003）→ `ecs:2953-2955` |
| `list-style-position` | 未处理 | **完整** ★ | `cs:1600`（`_parseListStylePosition` cs:4337）→ `ecs:3755`、`ecs:4174` |
| 逻辑属性（`margin/padding/inset/border` 的 `-inline/-block-start/end`） | 仅零散别名 | **完整** ★ | `alias:143`（`logicalPhysicalMap`，按 writing-mode + direction）→ 级联期 `cas:158/222`；盒边 `cs:1345` 附近 |
| `opacity`（组不透明度） | 部分（不叠乘） | **完整** ★ | `cs:1241`/`cs:1247`（`effectiveOpacity` 沿父链乘积）→ `pr:807-811`、`ecs:1539` |

### 1.2 从「部分」升到「完整」

| 属性 | 修好的子特性 | 位置 |
| --- | --- | --- |
| `font-weight: bolder/lighter`（第 1 版 Top #1） | 相对父级字重映射，`<b>/<strong>` 恢复加粗 | `_parseFontWeight(String, {int parentWeight})` cs:4587 |
| `box-shadow` blur/spread/inset | 外阴影模糊+扩散、内阴影 even-odd 挖洞 | `CssBoxShadow blur/spread/inset`（cs:888-905）→ `pr:1081`（外）/`pr:1110`（内） |
| `white-space: pre/pre-wrap/pre-line` | 换行转硬断行、空格保留 | `text_aggregator.dart:156-170`、`lb:701-702` |
| `box-sizing: border-box` | 声明宽先扣 padding/border 再成内容宽 | `bm:46-54`（`_resolveBound`） |
| `vertical-align` 的长度/百分比取值 | 直接作为基线位移 | `cs:1471`（`_parseVerticalAlignLength` cs:5162）→ `verticalAlignShift` → `ecs:2745` |
| `border-style` 的 `groove/ridge/inset/outset` | ~~降级 solid~~ → 已按 CSS 画两半明暗 | `_parseBorderStyle` cs:2944、`_paintSide` pr:2227 |
| `text-overflow: ellipsis` | 截断迁到排版层（行宽≤内容宽，原文区间不变，CFI 安全） | `lb:2071`（`_applyTextOverflow`） |

---

## 2. 真实书 CSS 频率

口径：频次 = 声明出现次数；书数 = 7 本语料里出现该属性的书数。语料与第 1 版相同，频率未变。

| 属性 | 频次 | 书数 | 当前状态 |
| --- | ---: | ---: | --- |
| font-family | 5482 | 7 | 完整 |
| text-align | 5077 | 7 | 完整 |
| font-size | 4707 | 7 | 完整 |
| color | 3752 | 7 | 完整 |
| margin 族 | 3450 + 2043 + 1901 + 627 + 431 | 7 | 完整 |
| text-indent | 3291（含 `duokan-text-indent` 1527） | 7 | 完整 |
| font-weight | 3266 | 7 | 完整（`bolder/lighter` 已修） |
| padding 族 | 1906 + 298 + 295 + 79 + 22 | 6-7 | 完整 |
| width | 1614 | 7 | 完整 |
| background-color | 1441 | 6 | 完整 |
| line-height | 892 | 7 | 部分（`normal` 口径见 Top #4） |
| border 族 | 842 + 517 + 378 + 281 + 61 | 5-6 | 完整 |
| border-radius | 560 | 6 | 完整（含 `a / b` 椭圆半径） |
| letter-spacing | 382 | 3 | 完整 |
| float | 335 | 5 | 完整 |
| vertical-align | 319 | 7 | 部分（竖排/行内复杂对齐） |
| background-size / position / repeat | 310 / 268 / 251 | 5 | 完整 |
| border-width / border-style | 305 / 280 | 5 | 部分（四值降级 solid） |
| display | 221 | 5 | 部分（单行 `flex` 已接通；`grid`、多行与伸缩算法未实现） |
| background-attachment | 218 | 3 | 等价降级（分页器里 `fixed` 底纹 = 每页页背景，与引擎 body 背景每页重绘等价；`scroll/local` 同 `fixed`） |
| background-image | 198 | 5 | 部分（单图层 + 渐变；无多背景） |
| list-style-type | 182 | 5 | 部分（无 `counter()`） |
| font-style | 126 | 5 | 完整 |
| page-break-inside | 107 | 5 | 完整 |
| duokan-bleed | 81 | 4 | 完整 |
| box-shadow | 68 | 4 | 完整（本轮补 blur/spread/inset） |
| height | 66 | 7 | 完整 |
| text-shadow | 60 | 5 | 完整 |
| text-decoration | 57 | 6 | 部分（竖排装饰线未沿列轴） |
| white-space | 54 | 3 | 完整（`pre` 族已修） |
| border-collapse | 52 | 4 | 完整（本轮接通） |
| position | 41 | 4 | 部分（`sticky` 无效果） |
| text-transform | 40 | 3 | 完整 |
| text-align-last | 28 | 1 | 完整 |
| **overflow** | **25** | **4** | 完整（本轮接通） |
| clear | 25 | 2 | 完整 |
| **transform** | **21** | **2** | 部分（2D 已实现，3D 无） |
| max-width / table-layout / box-sizing | 21 / 21 / 20 | 2-4 | 完整 |
| border-spacing | 19 | 1 | 完整（本轮接通） |
| top / left / bottom / right | 16 / 15 / 10 / 8 | 3-4 | 完整（本轮接通） |
| justify-content / align-items | 14 / 13 | 4 / 3 | 完整（语料仅用于单行 `flex`；主轴六种对齐、交叉轴起止/居中） |
| word-break | 12 | 5 | 完整（本轮接通） |
| page-break-before / after | 13 / 11 | 5 / 4 | 完整 |
| border-image | 11 | 3 | 完整（本轮接通九宫格：切割/repeat/fill；真书里这些规则定义了但未引用） |
| writing-mode 族 | 5 + 18 别名 | 3 | 部分（主干已实现，见 Top #5/#6） |
| font-variant | 7 | 1 | 完整（`smcp` 已接通） |
| orphans / widows | 7 / 7 | 1 | 不参与分页（产品决策：电子书排版不做孤行/寡行约束） |
| text-justify / ruby-align | 5 / 4 | 3 | 部分 / 部分（规范值已接入，单注音盒近似） |
| opacity | 5 | 1 | 完整（组合成已接通） |
| z-index / backdrop-filter / word-wrap | 4 / 3 / 3 | 2 / 2 / 1 | 完整（叠序）/ 近似实现（按页背景）/ 完整 |
| list-style-position | 2 | 1 | 完整（本轮接通） |
| object-fit | 1 | 1 | 完整（映射 background-size；本轮测试锁定 cover/contain/fill） |
| hyphens（`-epub-hyphens`） | 1 | 1 | 部分（已接通，无词典） |

读法提醒：**只按频次排序会误导**。`background-attachment` 218 次排第一，但分页阅读器对「视口固定底纹」可合法降级；而 `hyphens` 只有 1 次、`text-overflow` 只在个别书出现，却决定西文书的断字与溢出表现。排序口径因此是「影响面 × 频次 × 成本」，见第 5 章。

---

## 3. 属性总表

图例：**完整** = 解析→类型化→布局/绘制真实读取；**部分** = 有消费但缺子特性；**★** = 本轮新增或升级。

行号缩写：`cs` = `packages/reader_core/lib/css/computed_style.dart`，`cas` = `cascade.dart`，`ua` = `ua_stylesheet.dart`，`alias` = `property_aliases.dart`，`lb` = `layout/line_breaker.dart`，`bf` = `layout/block_flow.dart`，`bm` = `layout/box_model.dart`，`pg` = `layout/paginator.dart`，`pr` = `paint/page_renderer.dart`，`ecs` = `apps/reader_mobile/lib/reader/epub_chapter_source.dart`。

### 3.1 A 组：有字段且真正参与布局/绘制（98 条）

| # | 属性 | 解析位置 | 消费位置 | 判定 | 缺失 / 备注 |
| ---: | --- | --- | --- | --- | --- |
| 1 | `font-size` | cs:1108（`_resolveLength` cs:4528） | lb:2676；pr:1165 | 完整 | 无 `ch`/`ex`/`vw`/`calc()` |
| 2 | `line-height` | cs:1170 | lb:2677（`height:`） | 部分 | `normal` 交给 Flutter 字体度量，与 Chrome 口径有系统偏差（Top #4） |
| 3 | `color` | cs:1188 | pr:461；`_textColorFor` pr:455 附近 | 完整 | — |
| 4 | `font-weight` | cs:1203（`_parseFontWeight` cs:4587） | lb:2682 | 完整 ★ | `bolder/lighter` 按父级字重相对映射 |
| 5 | `font-style` | cs:1209 | lb:2683 | 完整 | `oblique` 近似 `italic` |
| 6 | `font-family` | cs:1214 | lb:2686（`fontFamily`/`fontFamilyFallback`） | 完整 | 别名 + 回退链 |
| 7 | `font`（简写） | `parseFontShorthand` cs:2971 | 同上 | 部分 | `small-caps` 已落成 `font-variant-caps` ★；系统字体关键字（`caption`）仍返回 null |
| 8 | `text-align` | cs:1219（`_parseTextAlign` cs:4617） | pr:1311-1314；lb:1397 | 完整 | `justify` 末行分配与 Chrome 差 1 个间隙（parity 01） |
| 9 | `text-indent` | cs:1373 | lb:775；ecs:2661 | 完整 | 只作用于段首行（书籍语义正确） |
| 10 | `letter-spacing` | cs:1387 | lb:2692 | 完整 | — |
| 11 | `word-spacing` | cs:1453 | lb:2693 | 完整 | — |
| 12 | `margin` | cs:1404 → `_resolveMargin` cs:4443 | bm:61；pr:546 | 完整 | 相邻块 margin 塌陷未做 |
| 13 | `margin-top/-right/-bottom/-left` | 同上（逐边） | bm:61；pr:546-547 | 完整 | 同上 |
| 14 | `padding` | cs:1685 → `_resolvePadding` cs:2646 | bm:57；pr:547 | 完整 | 纵向百分比按宽度解算（与 CSS 一致） |
| 15 | `padding-top/-right/-bottom/-left` | 同上（逐边） | bm:57；pr:547 | 完整 | — |
| 16 | `border` | cs:1658 → `_resolveBorders` cs:2703 | pr:246 区域（`_paintBorders`/`_paintCellBorders`） | 完整 | `border-image` 由独立九宫格绘制替代（见 #99） |
| 17 | `border-top/-right/-bottom/-left` | `_resolveBorders` cs:2703（`parseSide`） | 同上 | 完整 | — |
| 18 | `border-width` | `applyWidths`（`_resolveBorders` 内） | 同上 | 完整 | `thin/medium/thick` 固定 1/3/5px |
| 19 | `border-style` | `_parseBorderStyle` cs:2944 | pr 边框绘制 | 完整 | `groove/ridge/inset/outset` 画两半明暗（本轮接通） |
| 20 | `border-color` | `applyColors`（`_resolveBorders` 内） | 同上 | 完整 | 四值里含函数时靠括号保护切分 |
| 21 | `border-radius` | `_resolveBorders`（`border-radius`） | pr 圆角 RRect | 完整 | 横向/纵向双半径与百分比均按盒宽/高解算 |
| 22 | `border-top-left-radius` 等四角 | `_resolveBorders`（`border-$name-radius`） | 同上 | 完整 | 支持 `水平 [垂直]` 两值 |
| 23 | `width` | cs:1692 附近（`dimension`） | bm:57；pg:837 | 完整 | `auto` 无 shrink-to-fit（绝对定位块除外，pg:877） |
| 24 | `height` | 同上 | bm:58；pg:974；lb:769（竖排列长） | 完整 | 百分比高按包含块宽近似 |
| 25 | `min-width` | 同上（`dimension`） | bm:63 | 完整 | — |
| 26 | `max-width` | 同上 | bm:64 | 完整 | — |
| 27 | `min-height` | 同上 | bm:65 | 完整 | — |
| 28 | `max-height` | 同上 | bm:66 | 完整 | — |
| 29 | `box-sizing` | cs:1692（`_parseBoxSizing` cs:2697） | bm:46-54 | 完整 ★ | 本轮补「声明宽先扣 inset」 |
| 30 | `background-color` | cs:1649 | pr:461 | 完整 | — |
| 31 | `background-image`（url） | cs:1651 | pr:2061 | 部分 | 单图层；多背景逗号分层不支持 |
| 32 | `background-image: <gradient>` | `_parseGradient` cs:3144 | pr:1792、`_gradientShader` pr:1838 | 完整 ★ | linear/radial + `repeating-` |
| 33 | `background-repeat` | cs:1551 | pr:1821 | 完整 | — |
| 34 | `background-size` | cs:1555（`_parseBackgroundSize` cs:4875） | pr:1822 | 完整 | — |
| 35 | `background-position` | cs:1562（`_parseBackgroundPosition` cs:4925） | pr:1823 | 完整 | 三/四值部分支持 |
| 36 | `background-origin` | cs:1571 | pr:2033 | 完整 | — |
| 37 | `background-clip` | cs:1574 | pr:2020 | 部分 | `text` 降级 `padding-box`（pr:2018 注释） |
| 38 | `background`（简写） | `_parseBackgroundShorthand` cs:4369 | pr:1821-1823 | 部分 | 不含 `attachment`、不含多背景 |
| 39 | `display` | cs:1416（`_parseDisplay` cs:5188） | ecs:1488 起（单行 Flex）；pg:1121 | 部分 | `inline-block` 完整 ★；`flex` 接通单行主轴/交叉轴对齐，`grid`、换行与 grow/shrink 未实现 |
| 40 | `position` | cs:1414（`_parsePosition` cs:4631） | bf:522；ecs:3723 | 部分 | `absolute/fixed` 完整 ★、`relative` 完整 ★；`sticky` 无效果 |
| 41 | `top` | cs:1620（`_parseOffset` cs:5034） | pg:849 | 完整 ★ | `inset` 简写未解析 |
| 42 | `right` | cs:1627 | pg:848 | 完整 ★ | — |
| 43 | `bottom` | cs:1634 | pg:850 | 完整 ★ | — |
| 44 | `left` | cs:1641 | pg:847；ecs:3676 | 完整 ★ | — |
| 45 | `float` | cs:1415 | bf:525、614 | 完整 | 无逻辑值 |
| 46 | `clear` | cs:1576 | bf:356；ecs:1736 | 完整 | — |
| 47 | `visibility` | cs:1419 | pr:541 | 完整 | `collapse` 按 hidden |
| 48 | `white-space` | cs:1425 | lb:701-702；`text_aggregator.dart:156-170` | 完整 ★ | 本轮补硬断行与空格保留 |
| 49 | `list-style-type` | cs:1590（`_parseListStyleType` cs:4322） | ecs:3746 | 部分 | 8 种内置；无 `counter()`/`symbols()` |
| 50 | `list-style-position` | cs:1600（`_parseListStylePosition` cs:4337） | ecs:3755、4174 | 完整 ★ | — |
| 51 | `list-style`（简写） | `cas:316`（展开为 type + position） | 同上 | 完整 ★ | 本轮补 `inside` |
| 52 | `table-layout` | cs:1604（`_parseTableLayout` cs:4298） | ecs:3356 | 完整 | — |
| 53 | `border-collapse` | cs:1577（`_parseBorderCollapse` cs:4996） | ecs:2953 | 完整 ★ | — |
| 54 | `border-spacing` | cs:1606（`_parseBorderSpacing` cs:5003） | ecs:2954-2955 | 完整 ★ | — |
| 55 | `text-decoration` / `-line` | cs:1489-1490（`_parseTextDecoration` cs:5091） | lb:2694；pr:2459 | 部分 | 竖排下装饰线仍按水平轴画（Top #5） |
| 56 | `text-decoration-style` | cs:1495 | lb:2697；pr:2721 | 完整 | — |
| 57 | `text-decoration-color` | cs:1499 | lb:2696；pr:2464 | 完整 | — |
| 58 | `text-shadow` | cs:1535（`_parseTextShadows` cs:4807） | lb:2698 | 完整 | 多层支持 |
| 59 | `text-transform` | cs:1465 | lb:761 | 完整 | — |
| 60 | `text-align-last` | cs:1230 | lb:1381、1392 | 完整 | — |
| 61 | `text-justify` | cs:1223（`_parseTextJustify` cs:4704） | lb:1376 | 部分 | `inter-character` 逐字模式细节未区分 |
| 62 | `hanging-punctuation` | cs:1431 | lb:1370 | 部分 | 仅 `allow-end` |
| 63 | `text-spacing-trim` | cs:1439 | pr:3288 | 部分 | `space-first/trim-start/trim-both` 按相邻折叠近似 |
| 64 | `text-autospace` | cs:1445 | pr:596、3284 附近 | 部分 | 未声明默认 none（与规范 normal 有偏差，cs 已注释） |
| 65 | `text-emphasis-style` | cs:1502（`_parseTextEmphasisStyle` cs:5111） | pr:370、2495 区域 | 完整 | — |
| 66 | `text-emphasis-position` | cs:1508（`_parseTextEmphasisPosition` cs:5128） | pr:2512 | 完整 | — |
| 67 | `text-emphasis-color` | cs:1514 | pr:2505、3073 | 完整 | — |
| 68 | `text-emphasis`（简写） | cs:1502 | 同上 | 完整 | — |
| 69 | `vertical-align` | cs:1471（`_parseVerticalAlign` cs:5147；长度值 cs:5162） | lb:2220/2234（行盒）、`verticalAlignShift`→`ecs:2745`、pr:1276（单元格） | 部分 | 长度/百分比本轮补齐 ★；行内 `text-top/text-bottom/middle` 与竖排仍不完整 |
| 70 | `page-break-before` / `break-before` | cs:1519 | pg:41、101 | 完整 | — |
| 71 | `page-break-after` / `break-after` | cs:1522 | pg:42、102 | 完整 | — |
| 72 | `break-inside` / `page-break-inside` | cs:1525 | pg:51、103 | 完整 | — |
| 73 | `break-after: avoid` | cs:1530 | pg:52、104 | 完整 | — |
| 74 | `opacity` | cs:1241（`effectiveOpacity` cs:1247） | pr:807-811；ecs:1539 | 完整 ★ | 本轮改沿父链乘积 |
| 75 | `filter` / `-webkit-filter` | cs:1259（`_parseFilters` cs:3466） | pr:800-820、`_filterLayerPaint` pr:840 附近 | 完整 ★ | 12 种函数；`drop-shadow` 走单独路径 |
| 76 | `transform` / `-webkit-transform` | cs:1267（`_parseTransforms` cs:3659） | pr:641、661 | 部分 ★ | 2D（translate/scale/rotate/skew/matrix）；无 3D/perspective |
| 77 | `transform-origin` | cs:1271（`_parseTransformOrigin` cs:3803） | pr:675 | 完整 ★ | — |
| 78 | `writing-mode` | cs:1276（`_parseWritingMode` cs:3909） | lb:768/860/2577/2614；pg:1005、1287；pr:3342 | 部分 ★ | 竖排主干已通；ruby/装饰线/多列组合仍缺 |
| 79 | `text-orientation` | cs:1282（`_parseTextOrientation` cs:3919） | lb:2504 | 部分 ★ | `upright`/`sideways` 逐字旋转；组合标点细节未覆盖 |
| 80 | `direction` | cs:1288（`_parseDirection` cs:3930） | `isRtl`（cs:2149 附近）→ lb:870/896/1760；pr:624；hit_test:113 | 完整 ★ | bidi 镜像/数字方向依赖 Flutter |
| 81 | `hyphens` | cs:1294（`_parseHyphens` cs:3958） | lb:813 → `planSoftBreaks` lb:911 | 部分 ★ | `auto` 为元音-辅音启发式，无断字词典（Top #1） |
| 82 | `word-break` | cs:1298（`_parseWordBreak` cs:3968） | lb:815 → lb:911 | 完整 ★ | — |
| 83 | `overflow-wrap` / `word-wrap` | cs:1306（`_parseOverflowWrap` cs:3978） | lb:814 → lb:911 | 完整 ★ | — |
| 84 | `font-variant` / `font-variant-caps` | cs:1316（`_parseFontVariantCaps` cs:3988） | lb:2681（`_fontFeatures`） | 完整 ★ | caps 族映射到 OpenType 特性标签 |
| 85 | `overflow` / `overflow-x` | cs:1367（`_parseOverflow` cs:3939） | pr:1624、648 | 完整 ★ | `overflow-y` 未单独解析 |
| 86 | `column-count` | `_resolveColumns` cs:4116（读 4126） | pg:359 | 完整 ★ | — |
| 87 | `column-width` | 同上（读 4128） | pg:360 | 完整 ★ | — |
| 88 | `column-gap` | 同上（读 4154） | pg:366 | 完整 ★ | — |
| 89 | `column-rule` | 同上（读 4159，`_parseColumnRule` cs:4226） | pr:1040（`_paintColumnRules`） | 完整 ★ | 只画竖线；`column-rule-style` 全样式 |
| 90 | `columns`（简写） | 同上（`value('columns')` 4120 附近） | 同上 | 完整 ★ | — |
| 91 | `text-overflow` | cs:1248（`_parseTextOverflow` cs:4727） | lb:2071（`_applyTextOverflow`） | 部分 | 截断点用水平 `getPositionForOffset` 反查，竖排/多列不可靠（Top #3） |
| 92 | `box-shadow` | cs:1253（`_parseBoxShadow` cs:4738） | pr:1081（外）、1110（内） | 完整 ★ | 跨页切片不重复投影 |
| 93 | `duokan-bleed` / `-duokan-bleed` | cs:1584 附近（`_parseBleed` cs:4280） | ecs:2834、2918 | 完整 | 多看私有扩展 |
| 94 | 逻辑属性（`margin/padding/inset/border` × `inline/block` × `start/end`） | `alias:143` `logicalPhysicalMap` | 级联 `cas:158/222`；盒边 `cs:1345` 附近 | 完整 ★ | 按 writing-mode + direction 映射 |
| 95 | `font-stretch` | cs:1324（`_parseFontStretch` cs:4011） | lb:3260（`fontVariations` 的 `wdth` 轴） | 完整 ★ | 可变字体按百分比映射；静态字体忽略 |
| 96 | `quotes` | cs:1341（`_parseQuotes` cs:4028） | `ecs:2700`（`quotePairAt`）、`ecs:4716`（`q` 嵌套）、`ecs:1132`（`content: open-quote/close-quote`） | 完整 ★ | 支持 `none`/`auto`/显式配对，`q` 与生成内容共用嵌套层级 |
| 97 | `font-size-adjust` | cs:1332 | lb:3250（`textStyleFor`）→ `font_metrics.dart`（OS/2.sxHeight / head.unitsPerEm） | 部分 ★ | 内置宋体与书籍字体使用真实 x-height；字体集合或无 OS/2 x-height 时回退 0.5em |
| 98 | `initial-letter` | cs:1850（`_parseInitialLetter` cs:5892） | ecs:1331（`_firstLetterRun`）、ecs:350（`_dropCapBlock`） | 部分 ★ | 首字浮动占 n 行，正文前 n 行绕排；两值下沉深度与自动字号仍为近似 |

### 3.2 B 组汇总：部分属性

对应上表编号 2、7、19、31、37、38、39、40、49、55、61、62、63、64、66、69、76、78、79、81、91（另含 89/90 的跨页近似）。

| 缺失性质 | 属性（编号） | 后果 |
| --- | --- | --- |
| 值解析不全/降级 | `border-style`(19) | 非 solid 四值画成实线 |
| 只实现一种上下文 | `line-height`(2)、`text-decoration`(55)、`text-overflow`(91)、`vertical-align`(69)、`writing-mode`(78)、`hyphens`(81)、`initial-letter`(98) | 竖排/多列/行盒语境下失真；首字绕排只覆盖常规横排普通段落 |
| 只实现部分枚举 | `text-justify`(61)、`hanging-punctuation`(62)、`text-spacing-trim`(63)、`text-autospace`(64)、`display`(39)、`position`(40)、`text-orientation`(79) | 未实现值落到默认分支（`grid`、`sticky` 等） |
| 简写丢成员 | `font`(7)、`background`(38)、`list-style-type`(49) | `background-attachment` 等价降级、`counter()` 已支持 |
| 绘制近似 | `background-image`(31)、`background-clip`(37)、`transform`(76) | 多背景不支持、`clip:text` 降级、无 3D |

### 3.3 C 组：有字段但零消费（占位式，0 条）

判定：字段存在，且除 `lib/css/` 外全库检索该字段名 0 命中。

本组已清零。`initial-letter` 由 `ComputedStyle.initialLetterLines` 进入
`epub_chapter_source.dart`：首字符抽成左侧浮动块，占据 n 行高度，正文前
n 行在首字右侧绕排，第 n+1 行恢复全宽；作者 `::first-letter` 的颜色、
字重等声明会并入浮动块。属性不继承，只在声明它的块容器上生效。

仍属近似实现：两值 `initial-letter` 的下沉深度未完整实现；未显式声明
字号时使用约 `0.85 × n 行高` 的字体度量近似。Chrome 尚不支持该属性，
parity 用例仍为 `engine_only`。

### 3.4 D 组：无字段、值被静默丢弃（44 条）

被 `Cascade._consider`（`cas:548-570`）按名存进 `values`，无类型化字段、无消费点；属性名在全库（排除 `ua_stylesheet.dart` / `property_aliases.dart`）0 命中。

| # | 属性 | 语料频次/书数 | 缺失后果 |
| ---: | --- | --- | --- |
| 99 | `border-image` | 11 / 3 | 已实现并由 `82-border-image-background-attachment` 对照：`CssBorderImage` + 九宫格绘制，覆盖切割、边 `repeat`/`round`、`fill` 中间区平铺与 data URL |
| 100 | `background-attachment` | 218 / 3 | 已记录分页介质下的等价降级，并由 `82-border-image-background-attachment` 验证 body 固定底纹按每页页背景重绘 |
| 101 | `mix-blend-mode` | 0 | 叠加模式失效 |
| 102 | `backdrop-filter` | 3 / 2 | 已按「页面背景作为 backdrop」近似（纯 Canvas 无法采样已绘制内容）；`83-backdrop-filter` 对照失配 0 |
| 103 | `z-index` | 4 / 2 | 已实现：绘制顺序按层级升序稳定排序，同层保持文档序 |
| 105 | `line-break` | 0 | 已实现 `anywhere`（软断行），其余值按现有 CJK 断点规则 |
| 106 | `tab-size` | 0 | 已实现：`pre*` 文本制表符按制表位展开 |
| 97 | `mix-blend-mode` | 0 | 已实现：背景色画布混合（multiply/screen/overlay/darken/lighten） |
| 104 | `object-fit` / `object-position` | 1 / 1 | 已实现 fit→background-size 映射（cover/contain/fill/none/scale-down）与声明位置解析 |
| 105 | `counter-reset` / `counter-increment` | 0 | 已实现：元素与伪元素计入同一作用域，伪元素声明按级联胜者生效 |
| 106 | `content`（部分） | 5 / 3 | 已支持字符串、`attr()`、`counter()`、`open/close-quote` 与 `url()` 行内图片；图片未声明尺寸时沿用现有行内图片的 1em 等比降级 |
| 107 | `line-break` | 0（别名 6 处） | 标点禁则严格度不生效 |
| 108 | `unicode-bidi` | 0 | `bdo` 覆写不生效（UA 表有规则，无消费） |
| 109 | `ruby-align` | 4 / 3 | 已接入规范值 `start/center/space-between/space-around`；flat 管线按单注音盒近似 |
| 110 | `ruby-position` | 0 | 已实现横排 over/under 与竖排两侧选择 |
| 111 | `text-combine-upright` | 4 别名 / 1 | 已实现：竖排 2–4 位数字合并占 1em；`84-text-combine-upright` 以 `engine_only` 锁定行为 |
| 112 | `tab-size` | 0 | `pre` 制表符按固定宽近似 |
| 113 | `orphans` / `widows` | 7 / 7 | 明确不做（产品决策）：电子书分页不考虑孤行/寡行，页尾单行可接受 |
| 114 | `list-style-image` | 0 | 已实现：URL 随计算样式继承，落在列表项首行；文字类型保留为加载失败回退，`30-list-style-position` 对照失配 0 |
| 115 | `caption-side` / `empty-cells` | 0 | 已实现：表格标题上下位置、空单元格边框/背景显隐与标题外边距折叠 |
| 116 | `aspect-ratio` | 0 | 已实现：`ComputedStyle.aspectRatio` 解析单值/双值/`auto <ratio>`；图片块与行内图片单边尺寸按比例推导，双显式尺寸优先，并由 `88-aspect-ratio` 对照清零 |
| 117 | `scroll-behavior` / `scrollbar-width` / `-ms-overflow-style` | 0-2 | 分页阅读器无滚动条，影响 0 |
| 118 | `overflow-y` | 1 / 1 | 已实现：任一轴非 `visible` 即启用裁剪 |
| 119 | `outline` / `cursor` | 0 / 3 | `outline` 已实现（不占布局，支持线型/颜色/宽度/偏移及圆角虚线路径）；`cursor` 无交互，影响 0 |
| 120 | `user-select` / `resize` / `will-change` / `contain` / `isolation` / `pointer-events` | 0-1 | 交互与渲染提示，影响 ~0 |
| 121 | `clip-path` / `mask` | 0 | 异形裁剪/遮罩 |
| 122 | `transition` / `animation` | 0 | 分页静态渲染，可长期不支持 |
| 123 | `font-feature-settings` / `font-kerning` / `font-variant-ligatures` | 0 | `font-kerning` 已实现：`auto/normal` 保持默认，`none` 关闭 `kern` 并同步行宽测量；`font-variant-ligatures` 已实现；`font-feature-settings` 仍不支持 |
| 124 | `box-decoration-break` | 1 / 1 | 跨页切片装饰重复语义 |
| 125 | `justify-content` / `align-items` / `grid-*` / `flex-*` | 14 / 13 | 单行 `flex` 的 `justify-content`/`align-items` 已接入并由 90 用例对照；`grid`、换行与 grow/shrink 仍不支持 |
| 126 | `inset`（简写） | 0 | `inset: 0` 不生效（仅 4 个长属性可用） |

> 26 行代表 44 个属性（第 105/107/110/111/113/117/119/120/123/125 行含同族多属性）。

---

## 4. 本轮新增实现详录（验收要点）

### 4.1 `writing-mode` 竖排

- 解析：`cs:1276`（`_parseWritingMode` cs:3909，继承，初始 `horizontal-tb`）。
- 布局：`lb:768` 判定竖排后走「列」布局（`style.height` 当列长，`lb:769`）；`lb:860` 竖排测量入口；`lb:2577` 按 `vertical-rl` 决定列顺序；`lb:2614` 写回 `TextLayoutResult`。
- 跨页：`pg:1005`（`_verticalChunk` pg:1016）把列切成跨页块；`pg:1287` 说明竖排下 `lines` 是「列」。
- 绘制：`pr:3342` 附近以列标记为准重建几何。
- **仍未覆盖**：多列 + 竖排组合（竖排已实现，组合未验证）。

### 4.2 `position: absolute` 的 inset 解算

- 解析：`_parseOffset` cs:5034（top 1620 / right 1627 / bottom 1634 / left 1641）。
- 解算：`pg:847-850` 取四边 spec；`left == null && right != null` 时反解 `containingWidth - right - width`，`top` 同理（`pg:847-860`）；`width:auto` 走 `_shrink-to-fit`（`pg:877` 附近）。
- 收口：`ecs:3723` 用 `isOutOfFlow` 决定是否走绝对定位分支；`ecs:3664-3680` 处理 `relative` 位移。
- `z-index`：`ComputedStyle.zIndex` → 绘制顺序按层级升序稳定排序
  （`pr` 的 `_paintOrder`），同层保持文档序；命中/选区仍用文档序。
- **仍未覆盖**：`inset` 简写、绝对定位内百分比高度精度。

### 4.3 `columns` 多列

- 解析：`_resolveColumns` cs:4116（count 4126 / width 4128 / gap 4154 / rule 4159；`columns` 简写同函数）。
- 布局：`MulticolGeometry.fromStyle` pg:358-383（只有「首列块」携带完整几何，`pg:239` 注释）。
- 绘制：`_paintColumnRules` pr:1038（背景之上、正文之下，符合 CSS Multicol §4 顺序）。
- 跨页列流：paginator 内「每列按本页可用高容行 → 一页 `column-count` 列 →
  剩余顺延下一页」；列块按列文本区间切片 runs/行内盒/注音/行内图片并平移偏移。
- **仍未覆盖**：`column-span`（跨栏元素）、`column-fill: auto` 的填充顺序
  （当前按均衡/顺序填列近似）、竖排 + 多列组合。

### 4.4 `display: inline-block`

- 分支：`bf:537` 归入 `FlowBranch.inline`。
- 尺寸：`ecs:2354`（行内 span 走 inline-block 盒）、`ecs:2785`（图片）。
- 绘制：`pr:1502`（`_paintInlineBoxPlacements`）、`pr:1592`（`_paintInlineBoxContent`）、`pr:1539`（盒子 opacity）。
- 裁剪：`pr:1624`（与 `overflow` 同一裁剪路径）。

### 4.5 断行三件套

- 入口：`lb:911` `planSoftBreaks`（`hyphens` 813 / `overflow-wrap` 814 / `word-break` 815）。
- 实现：断点用 U+200B 表达，偏移映射回原文；`hyphens: auto` 走「元音-辅音-元音」近似音节边界。
- **仍未覆盖**：断字词典（Top #1）、`hyphenate-limit-chars`、`text-autospace` 与断点的交互（Top #2）。

### 4.6 其余

- `font-variant: small-caps` → `lb:2681` `_fontFeatures(style.fontVariantCaps)`。
- `direction: rtl` → `isRtl` 贯穿 `lb`（测量）/`pr`（绘制）/`hit_test`（命中），三处同向（`lb:1760`、`pr:624`、`hit_test.dart:113`）。
- `filter` → `pr:800` `_withEffects` + `_filterLayerPaint`；`drop-shadow` 走 `pr:819`（`_paintFilterDropShadow`；解析在 `cs:3615`）。
- `transform` → `pr:641` 块空间 `canvas.transform`；`pr:661` 逐函数左乘累积；`pr:675` 绕 `transform-origin`。
- `overflow` → `pr:1624` 与 `pr:648`（`contentClip && clipsOverflow`）两层裁剪。

---

## 5. Top 19 待修（按影响 × 频率）

排序口径：**影响面**（P0 整类失真 / P1 明显偏差 / P2 局部）× 语料证据 × 成本（S ≤1 天 / M 2-3 天 / L ≥1 周）。

| 排名 | 缺口 | 影响 | 证据 | 成本 | 落点文件 |
| ---: | --- | --- | --- | --- | --- |
| 1 | `hyphens: auto` 无词典（元音-辅音启发式） | P1 | `lb:911` `planSoftBreaks`；西文断字位置与 Chrome 不同 | M | `packages/reader_core/lib/layout/line_breaker.dart`（`_wordBreakOffsets`）+ 新增断字数据 |
| 2 | `word-wrap` / `text-autospace` 与断点交互 | P1 | `lb:814` 断点与 `pr:3284` autospace 各自为政，长词断点后行首/行尾空白处理不一致 | M | `line_breaker.dart` + `paint/autospace` 路径 |
| 3 | `text-overflow` 截断点只在水平语境可靠 | P1 | `lb:2071` 用 `getPositionForOffset(Offset(available, y))`，竖排/多列下 y 轴不是行进方向 | M | `line_breaker.dart`（`_applyTextOverflow`） |
| 4 | `line-height: normal` 口径 | P1 | `lb:2677` `height: style.lineHeightFactor`（normal 时 null，交给 Flutter）；Chrome 用 `ascent+descent+lineGap` | M | `line_breaker.dart`（行盒合成）+ `TextStyle` 构造 |
| 5 | 竖排装饰线（`text-decoration` 沿列轴） | P1 | `pr:2459/2464` 装饰线绘制未读 `writingMode`；竖排重点线会横着画 | M | `page_renderer.dart`（`_paintDecorations` 系列） |
| 6 | ruby 行高撑高与多注音分配 | P1 | `ruby-position`/`ruby-align` 已接入；flat 管线仍按单个注音盒近似，注音不参与行高撑高 | M | `line_breaker.dart` + `page_renderer.dart` |
| 7 | 多列跨页 runs 分发 | P1 | `pg:239` 「只有首列块携带完整几何」；`MulticolGeometry` 自认一级近似 | L | `paginator.dart`、`page_renderer.dart` |
| 8 | `content` 的 `url()` 替换内容 | ~~P2~~ 已完成 | 生成 U+FFFC 占位与 `InlineImageSpec`；相对资源、伪元素宽高及文本偏移已由章节源回归覆盖 | — | — |
| 9 | `object-position` | ~~P2~~ 已完成 | `object-fit` 与声明位置均映射到背景尺寸/位置 | — | — |
| 10 | `transform` 3D（`translate3d`/`rotate3d`/`perspective`） | P2 | `pr:661` 只构造 2D 仿射，4×4 矩阵其余位补零（`pr:682-687`） | M | `page_renderer.dart`（`_affineOfTransform` / `_transformMatrixOf`） |
| 11 | `border-image` | ~~P2~~ 已完成 | 切割/repeat/fill 全部实现（`cs:_parseBorderImage` + `pr:_paintBorderImage`） | — | — |
| 12 | `background-attachment` | ~~P2~~ 已完成 | 218 次 / 3 本；分页介质下 `fixed` 等价为每页页背景，已由 `82` 用例对照验收 | — | — |
| 13 | `border-radius` 椭圆（`a / b`）与百分比 | ~~P1~~ 已完成 | 解析横向/纵向双半径；百分比横向按盒宽、纵向按盒高，绘制为四角椭圆 | — | — |
| 14 | `border-style` 3D 线型 | ~~P2~~ 已完成 | 解析保留原值 + `_paintSide` 画外/内两半明暗 | — | — |
| 15 | `display: flex` + `justify-content`/`align-items` | ~~P2~~ 已完成（单行） | 221/5 + 14/4 + 13/3；语料集中在头像/封面的单行居中 | — | `epub_chapter_source.dart`（单行 Flex 行块）+ `computed_style.dart` |
| 16 | `initial-letter` 完整多行绕排 | ~~P2~~ 已完成 | 首字浮动占 n 行，正文前 n 行绕排；两值下沉深度和自动字号保留近似 | — | — |
| 17 | `font-size-adjust` 字号补偿 | ~~P2~~ 已完成 | `TextLayoutEngine.textStyleFor` 按字体 x-height 比例补偿字号；内置宋体和书籍字体注册真实度量 | — | — |
| 18 | `sticky` 定位无效果 | P2 | `cs:4631` 能解析出 `sticky`，`bf:522` 只处理 absolute/fixed | M | `block_flow.dart`、`paginator.dart` |
| 19 | `orphans` / `widows` 孤行控制 | — | 明确不做：电子书排版不考虑孤行/寡行（产品决策） | — | — |

候补（低成本）：`unicode-bidi`/`bdo` 的文本重排；其余 D 组属性按第 9 章分类保持现状。

---

## 6. 别名层「伪支持」复核

| 别名族 | 目标 | 目标是否有消费 |
| --- | --- | --- |
| `duokan-line-break` / `webkit-line-break` | `line-break` | **否**（Top 候补） |
| `epub-hyphens` / `webkit-hyphens` | `hyphens` | 是（本轮接通；Top #1 是词典精度） |
| `epub-text-combine` / `webkit-text-combine` / `ms-text-combine-horizontal` | `text-combine-upright` | **否** |
| `duokan-text-orientation` / `epub-text-orientation` | `text-orientation` | 是（`lb:2504`） |
| `duokan-writing-mode` / `epub-writing-mode` / `webkit-writing-mode` / `duokan-block-progression` / `duokan-writing-orientation` | `writing-mode` | 是（`lb:768` 等） |
| `webkit-margin-*` / `-epub-*` / 逻辑属性族 | 物理属性 | 是（`alias:143` + `cas:222`） |

仍「改名后丢弃」的只剩 `line-break`（语料 0 次引用），已在别名表注释标注目标零消费。

---

## 7. 与 parity 用例对照

`tool/css_parity/cases/` 现有 **87 个用例**（编号 `01`–`90`，缺 65、85、87）。用例是靶子不是结论：里面的声明跑出来必然有差异，正好当回归。

| Top 19 | 现有用例 | 覆盖判断 |
| --- | --- | --- |
| #1 hyphens 词典 | `20-hyphens-quotes`、`62-word-wrap-content` | 已覆盖（差异即词典缺失） |
| #2 word-wrap/autospace | `62`、`56-cjk-spacing` | 部分 |
| #3 text-overflow 断点 | `40-text-overflow` | 已覆盖 |
| #4 normal 行高 | `01-text-basic`、`02-letter-word-spacing` | 已覆盖（比对行 y） |
| #5 竖排装饰线 | `04-decoration`、`35-writing-mode`、`64-vertical-rl` | 已覆盖 |
| #6 竖排 ruby | **无** | 建议新增 `68-vertical-ruby.json` |
| #7 多列跨页 runs | `34-columns`、`42-multipage-flow`、`63-columns-rule`、`66-vertical-multipage`、`67-vertical-columns` | 已覆盖（跨页 + 多列组合已有） |
| #8 content/counter | `62-word-wrap-content`、`78-counter-content` | `content` 的字符串/attr/counter/quote/url 与计数器均有回归；URL 图片未单列视觉用例 |
| #9 object-fit | **无** | 建议新增 `69-object-fit.json` |
| #10 transform 3D | `36-transform` | 2D 已覆盖，3D 缺 |
| #11 border-image | `82-border-image-background-attachment` | 已覆盖切割、`repeat`/`round`/`fill` 与 data URL |
| #12 background-attachment | `82-border-image-background-attachment` | 已覆盖 body 固定底纹的等价降级 |
| #13 椭圆 radius | `24-border-radius-corners`、`50/51-radius-longhand-*` | 已覆盖多值、`a / b` 与百分比双半径 |
| #14 border-style 四值 | `25-border-style-all` | 已覆盖 |
| #15 flex | `90-flex-basic` | 已覆盖 `center`/`space-between`/`flex-end`、`align-items` 起止/居中，以及背景图、`img` 子项；几何/样式失配 0，截图差异 0.41% 来自图片采样 |
| #16–17 initial-letter / font-size-adjust | `45-initial-letter`、`80-font-size-adjust` | `font-size-adjust` 已有对照；`initial-letter` 由三行浮动/绕排和代理对回归锁定 |
| #18 sticky | `53-display-position` | 已覆盖 |
| #19 orphans/widows | 不适用 | 产品决策不做孤行/寡行控制，不补用例 |

**当前还缺的对照面**：Flex 换行、`grow/shrink` 与 `grid`；竖排 ruby 已加入 77 用例但仍为 `engine_only`
（注音行高口径未稳定），`counter-*` 已由 78 用例覆盖，`border-image` 与
`background-attachment` 已由 82 用例对照。

---

## 附录 A：统计与校验命令

### A.1 真实书频率

```bash
cd <repo>
/usr/bin/python3 - <<'PY'
import zipfile, re, glob, collections
props = collections.Counter(); books = collections.Counter()
for path in sorted(glob.glob('test_corpus/real/*.epub')):
    z = zipfile.ZipFile(path); c = collections.Counter()
    for name in z.namelist():
        if not name.lower().endswith(('.css','.xhtml','.html','.htm')): continue
        text = re.sub(r'/\*.*?\*/', '', z.read(name).decode('utf-8','ignore'), flags=re.S)
        for m in re.finditer(r'\{([^{}]*)\}', text):
            for decl in m.group(1).split(';'):
                if ':' not in decl: continue
                p = decl.split(':',1)[0].strip().lower()
                if re.fullmatch(r'-?[a-z][a-z0-9-]*', p): c[p]+=1
    for p,v in c.items(): props[p]+=v; books[p]+=1
for p,v in props.most_common(): print(f'{v:6d} books={books[p]} {p}')
PY
```

### A.2 占位式实现（有字段、零消费）

```bash
cd <repo>
for f in initialLetterLines fontSizeAdjust; do
  n=$(grep -rn "\.$f\b" packages/reader_core/lib apps --include=*.dart \
      | grep -v "lib/css/computed_style.dart" | grep -v "/test/" | wc -l | tr -d ' ')
  echo "$f = $n"   # 0 = 占位式；当前两项均接入消费
done
```

### A.3 完全未处理

```bash
cd <repo>
for p in border-image background-attachment mix-blend-mode z-index object-fit \
         counter-reset counter-increment line-break unicode-bidi ruby-position \
         text-combine-upright tab-size orphans widows; do
  n=$(grep -rnE "'$p'|\"$p\"|$p:" packages/reader_core/lib apps/reader_mobile/lib \
      --include=*.dart | grep -v ua_stylesheet | grep -v property_aliases | wc -l | tr -d ' ')
  echo "$p = $n"
done
```

## 附录 B：行号锚点自愈脚本

本文行号取自 `2026-10-27 05:42 CST` 快照。树仍在被并发改动时，用锚点重新定位（锚点比行号稳定）：

```bash
cd <repo>
CS=packages/reader_core/lib/css/computed_style.dart
LB=packages/reader_core/lib/layout/line_breaker.dart
PR=packages/reader_core/lib/paint/page_renderer.dart
grep -n "explicitValue('writing-mode')\|explicitValue('hyphens')\|explicitValue('transform')\|explicitValue('quotes')\|explicitValue('overflow')" $CS
grep -n "static int? _parseFontWeight\|static CssColumns _resolveColumns\|_resolveColumns(\|static List<CssTransform> _parseTransforms\|static CssGradient? _parseGradient" $CS
grep -n "planSoftBreaks\|_applyTextOverflow\|static TextStyle textStyleFor" $LB
grep -n "_transformMatrixOf\|_withEffects\|_paintColumnRules\|_paintInlineBoxPlacements" $PR
```

## 附录 C：审计边界

- 只做静态审计 + 语料统计；数值偏差以 `tool/css_parity` 的 `report.md` 为准。
- 不覆盖 `@font-face` 描述符、`@supports`、`@page`、`@charset` 等 at-rule。
- 伪元素（`::before`/`::after`/`::first-letter`/`::first-line`）只审到 `content` 边缘（D 组 #106），未展开作用域规则。
- 「零消费」以「除 `lib/css/` 外无字段读取」为准；**经 `ComputedStyle` 派生 getter（`isRtl`、`verticalAlignShift`、`fontFamily`、`resolvedTextAlign`、`isOutOfFlow`、`layoutFingerprint`）间接消费的计入 A 组**——`direction` 与 `vertical-align` 长度值属此类。
- 语料 7 本只给量级参考；`duokan-*` 私有属性在非多看渠道书里可能完全不存在。

## 第 9 章 最终分类（需求 1 收口口径）

> 116 条审计条目按「当前实现状态 + 页阅读器是否需要」分类。判定标准：
> **需要** = 对分页阅读的书页有可见渲染影响；**不需要** = 阅读器无该交互面
> （光标/选区/滚动条/resize 等）或分页介质下语义等价。

| 类别 | 条数 | 说明 |
| --- | ---: | --- |
| 已实现并接入绘制/布局 | 111 | 含 `quotes`、`z-index`、`ruby-position`/`ruby-align`、`border-image`、`font-size-adjust`、`text-combine-upright`、`backdrop-filter`、`caption-side`/`empty-cells`、百分比圆角、3D 边框、`counter-*`、`object-fit`、`outline`、单行 Flex；部分条目仍有第 9 章列出的已知差异 |
| 有字段但尚未消费 | 0 | 已清零；`initial-letter` 已由章节源生成首字下沉 run |
| 明确不需要（阅读器无交互面） | 9 | `cursor`、`user-select`、`resize`、`will-change`、`contain`、`scrollbar-width`、`-ms-overflow-style`、`box-decoration-break`（分页切片已在 `Paginator` 侧处理）、`object-position`（图片块恒居中） |
| 分页介质下等价降级 | 2 | `background-attachment`（每页重绘页背景） |
| 已知差异，不追平 | 7 | `hyphens`（近似音节 vs Chrome 词典）、`text-autospace`/`text-spacing-trim`（CSS Text 4 新默认，Chrome 149 未实现）、`text-overflow` 断点、`line-height: normal` 取整、`border-collapse` 半边框、`font-variant` 合成 small-caps（对内置宋体收益为负）、`initial-letter` 两值下沉深度与自动字号近似 |
| 已补完的近期缺口 | 3 | `tab-size`（制表位展开）、`line-break`（`anywhere` 接入软断行）、`mix-blend-mode`（画布混合） |

**覆盖率口径**：`tool/css_parity/cases` 声明的属性 151/168（89.9%，用例只覆盖能在
350×800 静态页里量化的属性）；本表才是「实现状态」口径。

**技术限制**：`backdrop-filter` 的 backdrop 用「页面背景」近似（纯 Canvas 无法
采样已绘制内容；Flutter 的 `BackdropFilter` 需要 widget 层），真书里该属性
只用于半透明装饰框。

**验证入口**：
- 逐属性对照：`node tool/css_parity/render_browser.mjs`；
  `cd apps/reader_mobile && CSS_PARITY=1 flutter test test/css_parity/parity_dump_test.dart`；
  `/usr/bin/python3 tool/css_parity/compare.py`
- 最新结果（2026-10-30）：87 用例基线 / 几何与样式失配 **0** / 未配对 15 项；
  部分截图差异超过 2%，逐图复核后归因于字体栅格、断行或分页截图口径。
  `43-multipage-table` 的表格在第 2 页且 9 个单元格误差均不超过 2px；
  `74-outline` 修复直角轮廓被错误圆角化，已补像素回归。
- `77-ruby-position-align` 覆盖 `ruby-position` 与规范 `ruby-align` 值；
  flat 管线按单注音盒近似，未撑高行高，暂标 `engine_only`。
- `78-counter-content` 覆盖伪元素计数器、级联胜者和父子 margin 折叠；
  几何/样式失配 0，视觉差异 1.83% 来自字体栅格与行宽。
- `79-vendor-effect-aliases`、`80-font-size-adjust`、`81-font-variant-caps`
  几何/样式失配均为 0；`82-border-image-background-attachment` 几何/样式失配
  0、视觉差异 0.43%，覆盖九宫格 `fill` 平铺与 data URL 保真。
- `89-font-kerning` 几何/样式失配 0；修复前同一文本在 `font-kerning: none`
  与默认值间会错误复用布局，现布局指纹包含字偶距、大小写、连字、字宽与
  `font-size-adjust`。
- `border-radius: a / b` 已补齐四角双半径解析与绘制；`24-border-radius-corners`
  几何/样式失配 0、视觉差异 0.24%，并新增像素与解析回归。
- 真书回归：`方案/验收记录/全书回归-R11.md`（1541 章页数/空页/浮动块与基线一致）
- 多看私有属性：`apps/reader_mobile/test/reader/duokan_private_css_test.dart`（真实语料出现过的私有属性全部有映射断言）+ `duokan_real_book_test.dart`（真书落点）
