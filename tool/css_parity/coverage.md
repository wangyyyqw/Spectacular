# CSS 属性覆盖矩阵

> 由 `tool/css_parity/coverage.py` 生成（幂等，可重复运行）。
> 属性清单 = `docs/css-property-audit.md` 的 116 条审计（A/C/D 组）展开；
> 覆盖判定 = `tool/css_parity/cases/*.json` 的 `css` 与 `html`（含内联
> style）中出现该属性声明（含厂商前缀别名）即算覆盖。

- 审计条目 **116** 条，展开后属性名 **155** 个（同一条目里的多属性按名拆分）
- 已覆盖 **123** 个（79.4%），未覆盖 **32** 个
- 用例 **64** 个（编号 01–64）
- 下一个可用用例编号：**65**（未覆盖表的「建议用例」按 1-2 属性/例分配）

## 1. 分组覆盖概览

| 分组 | 属性数 | 已覆盖 | 覆盖率 |
| --- | --- | --- | --- |
| 解析且消费（审计 A 组） | 102 | 102 | 100.0% |
| 占位式（审计 C 组：有字段、零消费） | 15 | 15 | 100.0% |
| 完全未处理（审计 D 组：无字段） | 38 | 6 | 15.8% |

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
| `border-image` | #90 | border-image | 65 |
| `line-break` | #91 | line-break | 65 |
| `counter-reset` | #94 | counter-reset / counter-increment | 66 |
| `counter-increment` | #94 | counter-reset / counter-increment | 66 |
| `object-fit` | #95 | object-fit / object-position | 67 |
| `object-position` | #95 | object-fit / object-position | 67 |
| `backdrop-filter` | #96 | backdrop-filter | 68 |
| `mix-blend-mode` | #97 | mix-blend-mode | 68 |
| `z-index` | #98 | z-index | 69 |
| `background-attachment` | #99 | background-attachment | 69 |
| `justify-content` | #100 | justify-content / align-items | 70 |
| `align-items` | #100 | justify-content / align-items | 70 |
| `orphans` | #101 | orphans / widows | 71 |
| `widows` | #101 | orphans / widows | 71 |
| `ruby-align` | #103 | ruby-align | 72 |
| `ruby-position` | #104 | ruby-position | 72 |
| `tab-size` | #106 | tab-size | 73 |
| `text-combine-upright` | #107 | text-combine-upright | 73 |
| `font-kerning` | #108 | font-feature-settings / font-kerning / font-variant-ligatures | 74 |
| `font-size-adjust` | #109 | font-size-adjust | 74 |
| `outline` | #110 | outline | 75 |
| `cursor` | #111 | cursor | 75 |
| `user-select` | #112 | user-select / resize / will-change / contain | 76 |
| `resize` | #112 | user-select / resize / will-change / contain | 76 |
| `will-change` | #112 | user-select / resize / will-change / contain | 77 |
| `contain` | #112 | user-select / resize / will-change / contain | 77 |
| `scrollbar-width` | #113 | scrollbar-width / -ms-overflow-style | 78 |
| `-ms-overflow-style` | #113 | scrollbar-width / -ms-overflow-style | 78 |
| `box-decoration-break` | #114 | box-decoration-break | 79 |
| `caption-side` | #115 | caption-side / empty-cells | 79 |
| `empty-cells` | #115 | caption-side / empty-cells | 80 |
| `aspect-ratio` | #116 | aspect-ratio | 80 |

## 3. 已覆盖清单

### 解析且消费（审计 A 组）

| 属性 | 审计编号 | 覆盖用例 |
| --- | --- | --- |
| `font-size` | #1 | 01、02、03、04、05、06、07、08、09、10、11、12、13、14、15、16、17、18、19、20、21、22、23、24、25、26、27、28、29、30、31、32、33、34、35、36、37、38、39、40、41、42、43、44、45、46、47、48、49、50、51、52、53、54、55、56、57、58、59、60、61、62、63、64 |
| `line-height` | #2 | 01、02、03、04、05、06、07、08、09、10、11、13、14、15、16、17、18、19、20、21、23、30、31、34、35、36、38、39、41、42、43、44、45、46、47、48、49、53、54、55、56、57、59、60、61、62、63、64 |
| `color` | #3 | 10、26、28、29、37、62 |
| `font-weight` | #4 | 07、12 |
| `font-style` | #5 | 07 |
| `font-family` | #6 | 01、02、03、04、05、06、07、08、09、10、11、12、13、14、15、16、17、18、19、20、21、22、23、24、25、26、27、28、29、30、31、32、33、34、35、36、37、38、39、40、41、42、43、44、45、46、47、48、49、50、51、52、53、54、55、56、57、58、59、60、61、62、63、64 |
| `font` | #7 | 58 |
| `text-align` | #8 | 03、12、17、18、32 |
| `text-indent` | #9 | 03、16、42、45 |
| `letter-spacing` | #10 | 01、02 |
| `word-spacing` | #11 | 02 |
| `margin` | #12 | 01、02、03、04、05、06、07、08、09、10、11、12、13、14、15、16、17、18、19、20、21、22、23、24、25、26、27、28、29、30、31、32、33、34、35、36、37、38、39、40、41、42、43、44、45、46、47、48、49、50、51、52、53、54、55、56、57、58、59、60、61、62、63、64 |
| `margin-top` | #13 | 46 |
| `margin-right` | #13 | 14、23、38 |
| `margin-bottom` | #13 | 46 |
| `margin-left` | #13 | 23、38 |
| `padding` | #14 | 01、02、03、04、05、06、07、08、09、10、11、12、13、14、15、16、17、18、19、20、21、22、23、24、25、26、27、28、29、30、31、32、33、34、35、36、37、38、39、40、41、42、43、44、45、46、47、48、49、50、51、52、53、54、55、56、57、58、59、60、61、62、63、64 |
| `padding-top` | #15 | 23、48 |
| `padding-right` | #15 | 47、48 |
| `padding-bottom` | #15 | 47、49 |
| `padding-left` | #15 | 11、16、30、31、49、54 |
| `border` | #16 | 09、12、21、24、27、28、32、33、35、40、43、47、50、51、52、62、64 |
| `border-top` | #17 | 48 |
| `border-right` | #17 | 48 |
| `border-bottom` | #17 | 49 |
| `border-left` | #17 | 49 |
| `border-width` | #18 | 25 |
| `border-style` | #19 | 25 |
| `border-color` | #20 | 25 |
| `border-radius` | #21 | 09、24 |
| `border-top-left-radius` | #22 | 50 |
| `border-top-right-radius` | #22 | 50 |
| `border-bottom-right-radius` | #22 | 51 |
| `border-bottom-left-radius` | #22 | 51 |
| `width` | #23 | 09、12、14、21、24、25、32、33、38、40、43、53、62 |
| `height` | #24 | 14、22、24、25、26、27、29、35、38、50、51、53、64 |
| `min-width` | #25 | 22 |
| `max-width` | #26 | 22 |
| `min-height` | #27 | 22 |
| `max-height` | #28 | 22 |
| `box-sizing` | #29 | 09、21 |
| `background-color` | #30 | 09、10、12、13、14、21、22、23、24、28、32、36、37、38、41、43、46、47、48、49、50、51、53、61 |
| `background-image` | #31 | 27、29、52 |
| `background-repeat` | #32 | 27、29、52 |
| `background-size` | #33 | 27、29、52 |
| `background-position` | #34 | 27、29 |
| `background-origin` | #35 | 52 |
| `background-clip` | #36 | 28 |
| `background` | #37 | 10、26 |
| `display` | #38 | 53 |
| `position` | #39 | 53 |
| `float` | #40 | 14、38 |
| `clear` | #41 | 38 |
| `visibility` | #42 | 54 |
| `white-space` | #43 | 06、40、62 |
| `list-style-type` | #44 | 11、30、31 |
| `list-style` | #45 | 54 |
| `table-layout` | #46 | 33 |
| `text-decoration` | #47 | 04 |
| `text-decoration-line` | #47 | 55 |
| `text-decoration-style` | #48 | 55 |
| `text-decoration-color` | #49 | 55 |
| `text-shadow` | #50 | 13 |
| `text-transform` | #51 | 08 |
| `text-align-last` | #52 | 17 |
| `text-justify` | #53 | 18 |
| `hanging-punctuation` | #54 | 44 |
| `text-spacing-trim` | #55 | 56 |
| `text-autospace` | #56 | 56 |
| `text-emphasis-style` | #57 | 57 |
| `text-emphasis-position` | #58 | 19 |
| `text-emphasis-color` | #59 | 19、57 |
| `text-emphasis` | #60 | 13、19 |
| `vertical-align` | #61 | 05 |
| `page-break-before` | #62 | 41、43 |
| `break-before` | #62 | 59 |
| `page-break-after` | #63 | 59 |
| `break-after` | #63 | 59 |
| `break-inside` | #64 | 41 |
| `page-break-inside` | #64 | 41 |
| `break-after` | #65 | 59 |
| `opacity` | #66 | 13、37 |
| `box-shadow` | #67 | 13 |
| `text-overflow` | #68 | 40 |
| `duokan-bleed` | #69 | 60 |
| `-duokan-bleed` | #69 | 60 |
| `top` | #70 | 53 |
| `left` | #71 | 53 |
| `border-collapse` | #72 | 12、32、33、43 |
| `border-spacing` | #73 | 33 |
| `filter` | #74 | 37 |
| `list-style-position` | #75 | 30 |
| `content` | #76 | 62 |
| `margin-inline-start` | #77 | 61 |
| `margin-inline-end` | #77 | 61 |
| `padding-inline-start` | #77 | 61 |
| `padding-inline-end` | #77 | 61 |
| `border-inline-start` | #77 | 61 |
| `border-inline-end` | #77 | 61 |
| `hyphens` | #78 | 20 |
| `word-break` | #79 | 20、62 |
| `overflow-wrap` | #80 | 20、40 |
| `word-wrap` | #80 | 62 |

### 占位式（审计 C 组：有字段、零消费）

| 属性 | 审计编号 | 覆盖用例 |
| --- | --- | --- |
| `right` | #81 | 53 |
| `bottom` | #82 | 53 |
| `initial-letter` | #83 | 45 |
| `transform` | #84 | 36 |
| `transform-origin` | #84 | 36 |
| `columns` | #85 | 34 |
| `column-count` | #85 | 63 |
| `column-width` | #85 | 63 |
| `column-gap` | #85 | 34、63 |
| `column-rule` | #85 | 34、63 |
| `writing-mode` | #86 | 35、64 |
| `text-orientation` | #87 | 64 |
| `direction` | #88 | 61 |
| `overflow` | #89 | 14、22、40 |
| `overflow-x` | #89 | 62 |

### 完全未处理（审计 D 组：无字段）

| 属性 | 审计编号 | 覆盖用例 |
| --- | --- | --- |
| `font-variant` | #92 | 15 |
| `quotes` | #93 | 20 |
| `unicode-bidi` | #102 | 61 |
| `list-style-image` | #105 | 30 |
| `font-feature-settings` | #108 | 15 |
| `font-variant-ligatures` | #108 | 15 |

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

## 5. 审计外的新增解析点

`computed_style.dart` 里有取值点、但审计 116 条未列出的属性
（审计基线之后新增，需 T7 复核是否真的消费）：

`-webkit-filter`、`-webkit-transform`、`font-variant-caps`

## 6. 口径说明

- 「声明出现即算覆盖」是保守判据：只有写法与属性名完全一致才算；
  简写（`margin`、`border`、`background`）不自动覆盖其长属性，
  因此 `margin-top` 等长属性仍会出现在未覆盖表里，需要单独声明。
- 审计分组沿用 `docs/css-property-audit.md`：A 组解析且消费、C 组占位式、
  D 组完全未处理；引擎后续改动可能让分组过期，第 5 节列出审计外变化。
- 未覆盖表的建议编号只是排期建议，新增用例后重跑本脚本会自动前移。
