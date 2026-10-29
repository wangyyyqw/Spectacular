# CSS 属性覆盖矩阵

> 由 `tool/css_parity/coverage.py` 生成（幂等，可重复运行）。
> 属性清单 = `docs/css-property-audit.md` 的 116 条审计（A/C/D 组）展开；
> 覆盖判定 = `tool/css_parity/cases/*.json` 的 `css` 与 `html`（含内联
> style）中出现该属性声明（含厂商前缀别名）即算覆盖。

- 审计条目 **116** 条，展开后属性名 **168** 个（同一条目里的多属性按名拆分）
- 已覆盖 **141** 个（83.9%），未覆盖 **27** 个
- 用例 **80** 个（编号 01–81）
- 下一个可用用例编号：**82**（未覆盖表的「建议用例」按 1-2 属性/例分配）

## 1. 分组覆盖概览

| 分组 | 属性数 | 已覆盖 | 覆盖率 |
| --- | --- | --- | --- |
| 解析且消费（审计 A 组） | 122 | 122 | 100.0% |
| 占位式（审计 C 组：有字段、零消费） | 1 | 1 | 100.0% |
| 完全未处理（审计 D 组：无字段） | 45 | 18 | 40.0% |

## 2. 未覆盖清单（按分组，附建议用例编号）

### 解析且消费（审计 A 组）

| 属性 | 审计编号 | 审计原文 | 建议用例 |
| --- | --- | --- | --- |
| - | - | - | - |

### 占位式（审计 C 组：有字段、零消费）

| 属性 | 审计编号 | 审计原文 | 建议用例 |
| --- | --- | --- | --- |
| - | - | - | - |

### 完全未处理（审计 D 组：无字段）

| 属性 | 审计编号 | 审计原文 | 建议用例 |
| --- | --- | --- | --- |
| `border-image` | #99 | border-image | 82 |
| `background-attachment` | #100 | background-attachment | 82 |
| `backdrop-filter` | #102 | backdrop-filter | 83 |
| `text-combine-upright` | #111 | text-combine-upright | 83 |
| `orphans` | #113 | orphans / widows | 84 |
| `widows` | #113 | orphans / widows | 84 |
| `caption-side` | #115 | caption-side / empty-cells | 85 |
| `empty-cells` | #115 | caption-side / empty-cells | 85 |
| `aspect-ratio` | #116 | aspect-ratio | 86 |
| `scroll-behavior` | #117 | scroll-behavior / scrollbar-width / -ms-overflow-style | 86 |
| `scrollbar-width` | #117 | scroll-behavior / scrollbar-width / -ms-overflow-style | 87 |
| `-ms-overflow-style` | #117 | scroll-behavior / scrollbar-width / -ms-overflow-style | 87 |
| `cursor` | #119 | outline / cursor | 88 |
| `user-select` | #120 | user-select / resize / will-change / contain / isolation / pointer-events | 88 |
| `resize` | #120 | user-select / resize / will-change / contain / isolation / pointer-events | 89 |
| `will-change` | #120 | user-select / resize / will-change / contain / isolation / pointer-events | 89 |
| `contain` | #120 | user-select / resize / will-change / contain / isolation / pointer-events | 90 |
| `isolation` | #120 | user-select / resize / will-change / contain / isolation / pointer-events | 90 |
| `pointer-events` | #120 | user-select / resize / will-change / contain / isolation / pointer-events | 91 |
| `clip-path` | #121 | clip-path / mask | 91 |
| `mask` | #121 | clip-path / mask | 92 |
| `transition` | #122 | transition / animation | 92 |
| `animation` | #122 | transition / animation | 93 |
| `font-kerning` | #123 | font-feature-settings / font-kerning / font-variant-ligatures | 93 |
| `box-decoration-break` | #124 | box-decoration-break | 94 |
| `justify-content` | #125 | justify-content / align-items / grid-* / flex-* | 94 |
| `align-items` | #125 | justify-content / align-items / grid-* / flex-* | 95 |

## 3. 已覆盖清单

### 解析且消费（审计 A 组）

| 属性 | 审计编号 | 覆盖用例 |
| --- | --- | --- |
| `font-size` | #1 | 01、02、03、04、05、06、07、08、09、10、11、12、13、14、15、16、17、18、19、20、21、22、23、24、25、26、27、28、29、30、31、32、33、34、35、36、37、38、39、40、41、42、43、44、45、46、47、48、49、50、51、52、53、54、55、56、57、58、59、60、61、62、63、64、66、67、68、69、70、71、72、73、74、75、76、77、78、79、80、81 |
| `line-height` | #2 | 01、02、03、04、05、06、07、08、09、10、11、13、14、15、16、17、18、19、20、21、23、30、31、34、35、36、38、39、41、42、43、44、45、46、47、48、49、53、54、55、56、57、59、60、61、62、63、64、66、67、69、70、71、72、73、74、75、76、78、79、80、81 |
| `color` | #3 | 10、26、28、29、37、62、75、76、78、79、80、81 |
| `font-weight` | #4 | 07、12 |
| `font-style` | #5 | 07 |
| `font-family` | #6 | 01、02、03、04、05、06、07、08、09、10、11、12、13、14、15、16、17、18、19、20、21、22、23、24、25、26、27、28、29、30、31、32、33、34、35、36、37、38、39、40、41、42、43、44、45、46、47、48、49、50、51、52、53、54、55、56、57、58、59、60、61、62、63、64、66、67、68、69、70、71、72、73、74、75、76、77、78、79、80、81 |
| `font` | #7 | 58 |
| `text-align` | #8 | 03、12、17、18、32 |
| `text-indent` | #9 | 03、16、42、45 |
| `letter-spacing` | #10 | 01、02 |
| `word-spacing` | #11 | 02 |
| `margin` | #12 | 01、02、03、04、05、06、07、08、09、10、11、12、13、14、15、16、17、18、19、20、21、22、23、24、25、26、27、28、29、30、31、32、33、34、35、36、37、38、39、40、41、42、43、44、45、46、47、48、49、50、51、52、53、54、55、56、57、58、59、60、61、62、63、64、66、67、68、69、70、71、72、73、74、75、76、77、78、79、80、81 |
| `margin-top` | #13 | 46、73 |
| `margin-right` | #13 | 14、23、38 |
| `margin-bottom` | #13 | 46、79 |
| `margin-left` | #13 | 23、38 |
| `padding` | #14 | 01、02、03、04、05、06、07、08、09、10、11、12、13、14、15、16、17、18、19、20、21、22、23、24、25、26、27、28、29、30、31、32、33、34、35、36、37、38、39、40、41、42、43、44、45、46、47、48、49、50、51、52、53、54、55、56、57、58、59、60、61、62、63、64、66、67、68、69、70、71、72、73、74、75、76、77、78、79、80、81 |
| `padding-top` | #15 | 23、48 |
| `padding-right` | #15 | 47、48 |
| `padding-bottom` | #15 | 47、49 |
| `padding-left` | #15 | 11、16、30、31、49、54 |
| `border` | #16 | 09、12、21、24、27、28、32、33、35、40、43、47、50、51、52、62、64、66、67、69、70、73、74、76 |
| `border-top` | #17 | 48 |
| `border-right` | #17 | 48 |
| `border-bottom` | #17 | 49 |
| `border-left` | #17 | 49 |
| `border-width` | #18 | 25 |
| `border-style` | #19 | 25 |
| `border-color` | #20 | 25 |
| `border-radius` | #21 | 09、24、69、74 |
| `border-top-left-radius` | #22 | 50 |
| `border-top-right-radius` | #22 | 50 |
| `border-bottom-right-radius` | #22 | 51 |
| `border-bottom-left-radius` | #22 | 51 |
| `width` | #23 | 09、12、14、21、24、25、32、33、38、40、43、53、62、68、69、71、72、73、74、75、76、79 |
| `height` | #24 | 14、22、24、25、26、27、29、35、38、50、51、53、64、68、69、72、73、75、76、79 |
| `min-width` | #25 | 22 |
| `max-width` | #26 | 22 |
| `min-height` | #27 | 22、75 |
| `max-height` | #28 | 22 |
| `box-sizing` | #29 | 09、21、75、76 |
| `background-color` | #30 | 09、10、12、13、14、21、22、23、24、28、32、36、37、38、41、43、46、47、48、49、50、51、53、61 |
| `background-image` | #31 | 27、29、52 |
| `background-image` | #32 | 27、29、52 |
| `background-repeat` | #33 | 27、29、52 |
| `background-size` | #34 | 27、29、52 |
| `background-position` | #35 | 27、29 |
| `background-origin` | #36 | 52 |
| `background-clip` | #37 | 28 |
| `background` | #38 | 10、26、68、69、71、73、74、75、76、79、80、81 |
| `display` | #39 | 53、72 |
| `position` | #40 | 53、68、75、76 |
| `top` | #41 | 53、68、76 |
| `right` | #42 | 53、76 |
| `bottom` | #43 | 53、76 |
| `left` | #44 | 53、68、76 |
| `float` | #45 | 14、38 |
| `clear` | #46 | 38 |
| `visibility` | #47 | 54 |
| `white-space` | #48 | 06、40、62 |
| `list-style-type` | #49 | 11、30、31 |
| `list-style-position` | #50 | 30 |
| `list-style` | #51 | 54 |
| `table-layout` | #52 | 33 |
| `border-collapse` | #53 | 12、32、33、43 |
| `border-spacing` | #54 | 33 |
| `text-decoration` | #55 | 04 |
| `text-decoration-line` | #55 | 55 |
| `text-decoration-style` | #56 | 55 |
| `text-decoration-color` | #57 | 55 |
| `text-shadow` | #58 | 13 |
| `text-transform` | #59 | 08 |
| `text-align-last` | #60 | 17 |
| `text-justify` | #61 | 18 |
| `hanging-punctuation` | #62 | 44 |
| `text-spacing-trim` | #63 | 56 |
| `text-autospace` | #64 | 56 |
| `text-emphasis-style` | #65 | 57 |
| `text-emphasis-position` | #66 | 19 |
| `text-emphasis-color` | #67 | 19、57 |
| `text-emphasis` | #68 | 13、19 |
| `vertical-align` | #69 | 05 |
| `page-break-before` | #70 | 41、43 |
| `break-before` | #70 | 59 |
| `page-break-after` | #71 | 59 |
| `break-after` | #71 | 59 |
| `break-inside` | #72 | 41 |
| `page-break-inside` | #72 | 41 |
| `break-after` | #73 | 59 |
| `opacity` | #74 | 13、37 |
| `filter` | #75 | 37、79 |
| `-webkit-filter` | #75 | 79 |
| `transform` | #76 | 36、79 |
| `-webkit-transform` | #76 | 79 |
| `transform-origin` | #77 | 36 |
| `writing-mode` | #78 | 35、64、66、67 |
| `text-orientation` | #79 | 64、66、67 |
| `direction` | #80 | 61 |
| `hyphens` | #81 | 20 |
| `word-break` | #82 | 20、62 |
| `overflow-wrap` | #83 | 20、40 |
| `word-wrap` | #83 | 62 |
| `font-variant` | #84 | 15 |
| `font-variant-caps` | #84 | 81 |
| `overflow` | #85 | 14、22、40 |
| `overflow-x` | #85 | 62 |
| `column-count` | #86 | 63 |
| `column-width` | #87 | 63 |
| `column-gap` | #88 | 34、63 |
| `column-rule` | #89 | 34、63 |
| `columns` | #90 | 34 |
| `text-overflow` | #91 | 40 |
| `box-shadow` | #92 | 13 |
| `duokan-bleed` | #93 | 60 |
| `-duokan-bleed` | #93 | 60 |
| `margin-inline-start` | #94 | 61 |
| `margin-inline-end` | #94 | 61 |
| `padding-inline-start` | #94 | 61 |
| `padding-inline-end` | #94 | 61 |
| `border-inline-start` | #94 | 61 |
| `border-inline-end` | #94 | 61 |
| `font-stretch` | #95 | 15 |
| `quotes` | #96 | 20 |
| `font-size-adjust` | #97 | 80 |

### 占位式（审计 C 组：有字段、零消费）

| 属性 | 审计编号 | 覆盖用例 |
| --- | --- | --- |
| `initial-letter` | #98 | 45 |

### 完全未处理（审计 D 组：无字段）

| 属性 | 审计编号 | 覆盖用例 |
| --- | --- | --- |
| `mix-blend-mode` | #101 | 71 |
| `z-index` | #103 | 68 |
| `line-break` | #105 | 71 |
| `tab-size` | #106 | 71 |
| `mix-blend-mode` | #97 | 71 |
| `object-fit` | #104 | 72 |
| `object-position` | #104 | 72 |
| `counter-reset` | #105 | 78 |
| `counter-increment` | #105 | 78 |
| `content` | #106 | 62、78 |
| `line-break` | #107 | 71 |
| `unicode-bidi` | #108 | 61 |
| `ruby-align` | #109 | 77 |
| `ruby-position` | #110 | 77 |
| `tab-size` | #112 | 71 |
| `list-style-image` | #114 | 30 |
| `overflow-y` | #118 | 73 |
| `outline` | #119 | 74 |
| `font-feature-settings` | #123 | 15 |
| `font-variant-ligatures` | #123 | 15 |
| `inset` | #126 | 75 |

## 4. 编号 ≥46 的长尾用例

每个用例聚焦 1-2 个此前零覆盖、且引擎有解析/有消费的属性；
下表只列该用例「首次覆盖」的属性（通用属性如 font-size 不重复列）。

| 用例 | 覆盖属性 |
| --- | --- |
| 46 | `margin-bottom`、`margin-top` |
| 47 | `padding-bottom`、`padding-right` |
| 48 | `border-right`、`border-top` |
| 49 | `border-bottom`、`border-left` |
| 50 | `border-top-left-radius`、`border-top-right-radius` |
| 51 | `border-bottom-left-radius`、`border-bottom-right-radius` |
| 52 | `background-origin` |
| 53 | `bottom`、`display`、`left`、`position`、`right`、`top` |
| 54 | `list-style`、`visibility` |
| 55 | `text-decoration-color`、`text-decoration-line`、`text-decoration-style` |
| 56 | `text-autospace`、`text-spacing-trim` |
| 57 | `text-emphasis-style` |
| 58 | `font` |
| 59 | `break-after`、`break-before`、`page-break-after` |
| 60 | `-duokan-bleed`、`duokan-bleed` |
| 61 | `border-inline-end`、`border-inline-start`、`direction`、`margin-inline-end`、`margin-inline-start`、`padding-inline-end`、`padding-inline-start`、`unicode-bidi` |
| 62 | `content`、`overflow-x`、`word-wrap` |
| 63 | `column-count`、`column-width` |
| 64 | `text-orientation` |
| 68 | `z-index` |
| 71 | `line-break`、`mix-blend-mode`、`tab-size` |
| 72 | `object-fit`、`object-position` |
| 73 | `overflow-y` |
| 74 | `outline` |
| 75 | `inset` |
| 77 | `ruby-align`、`ruby-position` |
| 78 | `counter-increment`、`counter-reset` |
| 79 | `-webkit-filter`、`-webkit-transform` |
| 80 | `font-size-adjust` |
| 81 | `font-variant-caps` |

## 5. 审计外的新增解析点

`computed_style.dart` 里有取值点、但审计 116 条未列出的属性
（审计基线之后新增，需 T7 复核是否真的消费）：

`-webkit-backdrop-filter`、`border-image-source`

## 6. 口径说明

- 「声明出现即算覆盖」是保守判据：只有写法与属性名完全一致才算；
  简写（`margin`、`border`、`background`）不自动覆盖其长属性，
  因此 `margin-top` 等长属性仍会出现在未覆盖表里，需要单独声明。
- 审计分组沿用 `docs/css-property-audit.md`：A 组解析且消费、C 组占位式、
  D 组完全未处理；引擎后续改动可能让分组过期，第 5 节列出审计外变化。
- 未覆盖表的建议编号只是排期建议，新增用例后重跑本脚本会自动前移。
