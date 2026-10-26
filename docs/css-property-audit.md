# CSS 属性实现审计：解析位置 → 消费位置 → 是否真正生效

> 目的：把「引擎认了但没用」的属性全部摊开，按「影响 × 真实书频率」排出待修顺序。
> 范围：`packages/reader_core/lib/css/*`（解析/层叠/计算）、`layout/*` 与 `paint/*`（布局与绘制）、`apps/reader_mobile/lib/reader/epub_chapter_source.dart`（flat 管线消费方）。
> 本文只做审计，不包含任何代码改动。
>
> 基线提交 `abc6ed1` + 未提交改动（刷新于 2026-10-27 03:00）。C/D 分类与行号按当前工作树重算。

## 0. 结论摘要

| 指标 | 数值 |
| --- | --- |
| 真实书语料（`test_corpus/real/*.epub`） | 7 本，105 个 CSS 文件 |
| 语料中出现的不同属性名 | 132 |
| 引擎有类型化字段并参与布局/绘制的属性 | 80（其中 55 条完整、25 条只覆盖部分子特性） |
| **解析出字段但零消费（占位式实现）** | **9**（`right`/`bottom`/`initial-letter`/`transform`/`columns`/`writing-mode`/`text-orientation`/`direction`/`overflow`） |
| **完全没有字段、值进 `values` 后被静默丢弃** | **27**（`border-image`、`line-break`、`background-attachment`、`text-combine-upright` 等） |
| 本文覆盖的属性条目总数 | **116**（80 + 9 + 27） |
| 语料频率最高的缺失项 | `background-attachment`（218 次 / 3 本）、`overflow`（25 次 / 4 本）、`transform`（21 次 / 2 本） |

三个必须记住的判断：

1. **引擎对未知属性是「静默接受」而不是「拒绝」。** 级联层 `Cascade._consider`（`packages/reader_core/lib/css/cascade.dart:488`）按属性名把任意 `property: value` 原样存进 `winners`，`ComputedStyle` 只对认识的属性做类型化解析，其余留在 `values` map 里无人读取。所以「支持 132 个属性」是假象，真正生效的是 80 个。
2. **最大的实际风险不是「没实现的属性」，而是「解析了却不消费」。** 这类属性在代码审查、`values` dump、`parity_dump_test` 里都看起来「有值」，但布局/绘制一行都没读。典型：`right`/`bottom`（绝对定位只接了 top/left）、`initial-letter`、`transform`、`columns`、`writing-mode`、`overflow`。详见第 3.3 与第 4 章。
3. **别名层会制造「伪支持」。** `property_aliases.dart` 把 `-webkit-text-combine`、`webkit-line-break`、`duokan-writing-mode` 等重命名到标准属性，但 `text-combine-upright`、`line-break` 没有字段，`writing-mode`/`text-orientation` 有字段无消费——改名后依旧不出效果。详见第 6 章。

基线提交 `abc6ed1` + 未提交改动（刷新于 2026-10-27 03:00）。未提交部分给 `computed_style.dart` 新增 transform、columns、writing-mode、text-orientation、direction、overflow、hyphens、word-break、overflow-wrap 字段与解析，`line_breaker.dart` 接入 `text-overflow: ellipsis` 与断词断字。本文的 C/D 分类与行号已按当前工作树重算，文中行号均经脚本校验不越界；`tool/css_parity/cases/` 已扩到 60 个。行号每行都附函数/分支锚点；并发改动会让行号漂移，定位时按锚点 `grep`，不要只信数字。

审计只回答「有没有消费点」，不回答「数值差多少」。要数值结论请用 `tool/css_parity` 跑 `report.md`（该套件已覆盖本文 Top 20 中的 14 项，见第 7 章）。

---

## 1. 审计方法与证据来源

| 环节 | 做法 |
| --- | --- |
| 枚举「解析了什么」 | `computed_style.dart` 里所有 `explicitValue(...)` / `fontValue(...)` / `backgroundValue(...)` 取值点，加上盒模型专用入口 `_resolveMargin` / `_resolvePadding` / `_resolveBorders` / `dimension()` |
| 枚举「层叠/继承认了什么」 | `cascade.dart:55`（23 项继承表）、`cascade.dart:281`（`_expandShorthand`：margin/padding/border/border-width/style/color）、`cascade.dart:245`（`list-style`） |
| 枚举「UA 表声明了什么」 | `ua_stylesheet.dart`（`uaStylesheetCss` 完整规则集 + `UaBlockDefaults` 块级覆盖层） |
| 判定「是否真正消费」 | 对每个类型化字段做全库检索（排除 `lib/css/`）：命中即视为消费，并记录第一个布局/绘制调用点；零命中判定为占位式 |
| 判定「完全没有字段」 | 属性名以 `'<prop>'` / `"<prop>"` / `<prop>:` 形式在全库检索，0 命中即确认未处理 |
| 真实书频率 | `/usr/bin/python3` 解压 `test_corpus/real/*.epub`，正则扫 CSS 文件与 `<style>` 块内的声明，统计「次数」与「出现在几本书里」 |

复现命令见附录 A。关键验证命令示例：

```bash
# 占位式实现的证据：字段存在但除 css/ 外无人读取
grep -rn "\.borderCollapse\b" packages/reader_core/lib apps --include=*.dart \
  | grep -v "lib/css/computed_style.dart"   # → 无输出

# 完全未处理的证据：属性名在全库不出现
grep -rnE "'transform'|\"transform\"|transform:" packages/reader_core/lib apps --include=*.dart
  # → 无输出
```

---

## 2. 真实书 CSS 频率统计

### 2.1 高频属性（对引擎支持情况的对照）

「频次」= 声明出现次数；「书数」= 7 本语料中出现该属性的书的数量。

| 属性 | 频次 | 书数 | 引擎状态 |
| --- | ---: | ---: | --- |
| font-family | 5482 | 7 | 完整 |
| text-align | 5077 | 7 | 完整 |
| font-size | 4707 | 7 | 完整 |
| color | 3752 | 7 | 完整 |
| margin（+四边） | 3450 / 2043 / 1901 / 627 / 431 | 7 | 完整 |
| text-indent | 3291 | 7 | 完整（含 `duokan-text-indent` 1527 次） |
| font-weight | 3266 | 7 | **部分：`bolder`/`lighter` 不解析（见 §4.3）** |
| padding（+四边） | 1906 / 298 / 295 / 79 / 22 | 6-7 | 完整 |
| width | 1614 | 7 | 完整 |
| background-color | 1441 | 6 | 完整 |
| line-height | 892 | 7 | 完整 |
| border（+四边） | 842 / 517 / 378 / 281 / 61 | 5-6 | 完整 |
| **border-radius** | 560 | 6 | **部分：只认单值半径** |
| letter-spacing | 382 | 3 | 完整 |
| float | 335 | 5 | 完整 |
| vertical-align | 319 | 7 | **部分：仅表格单元格生效** |
| background-size | 310 | 5 | 完整 |
| border-width / border-style | 305 / 280 | 5 | **部分：`groove/ridge/inset/outset` 丢值** |
| background-position / repeat | 268 / 251 | 5 | 完整 |
| display | 221 | 5 | **部分：`flex` 当 `block`** |
| **background-attachment** | **218** | **3** | **完全未处理** |
| background-image | 198 | 5 | 部分：无渐变/多图层 |
| list-style-type | 182 | 5 | 部分：无自定义 counter |
| font-style | 126 | 5 | 完整 |
| page-break-inside | 107 | 5 | 完整 |
| duokan-bleed | 81 | 4 | 完整 |
| **box-shadow** | 68 | 4 | 部分：无 blur/spread/inset |
| height | 66 | 7 | 完整 |
| text-shadow | 60 | 5 | 完整 |
| text-decoration | 57 | 6 | 完整 |
| white-space | 54 | 3 | **部分：`pre`/`pre-wrap` 换行处理错误** |
| **border-collapse** | **52** | **4** | 完整（collapse 半边框近似） |
| position | 41 | 4 | **部分：只摘出流、不定位** |
| text-transform | 40 | 3 | 完整 |
| text-align-last | 28 | 1 | 完整 |
| **overflow** | 25 | 4 | **完全未处理** |
| clear | 25 | 2 | 完整 |
| **transform** | 21 | 2 | **字段已解析、零消费** |
| max-width | 21 | 4 | 完整 |
| table-layout | 21 | 2 | 完整 |
| box-sizing | 20 | 2 | 部分：宽度未计入 padding/border |
| **border-spacing** | 19 | 1 | **解析但零消费** |
| **inset（top/left/bottom/right）** | 16 / 15 / 10 / 8 | 3-4 | **解析但零消费** |
| **justify-content / align-items** | 14 / 13 | 4 / 3 | **完全未处理** |
| **word-break** | 12 | 5 | **完全未处理** |
| page-break-before / after | 13 / 11 | 5 / 4 | 完整 |
| **border-image** | 11 | 3 | **完全未处理** |
| **writing-mode（含 6 条私有别名）** | 5 + 18 | 3 | **字段已解析、零消费** |
| **font-variant** | 7 | 1 | **完全未处理** |
| **orphans / widows** | 7 / 7 | 1 | **完全未处理** |
| opacity | 5 | 1 | 部分：仅块级 |
| **z-index** | 4 | 2 | **完全未处理** |
| text-justify / ruby-align | 5 / 4 | 3 | 部分 |
| **backdrop-filter** | 3 | 2 | **完全未处理** |
| **word-wrap** | 3 | 1 | **完全未处理** |
| **list-style-position** | 2 | 1 | **完全未处理** |
| overflow-x / overflow-y | 2 / 1 | 1 | 完全未处理 |
| **object-fit** | 1 | 1 | 完全未处理 |
| **hyphens（`-epub-hyphens`）** | 1 | 1 | **完全未处理（但别名层已认）** |
| **text-combine-upright（4 条别名）** | 4 | 1 | **完全未处理（但别名层已认）** |

### 2.2 频率读法

- 中文 EPUB 的属性分布极度长尾：前 12 个属性覆盖约 80% 的声明量，`font-family`/`text-align`/`font-size`/`color`/`margin`/`text-indent` 六项就占一半。
- 因此**只按频次排序会误导**：`background-attachment` 218 次排第一，但分页阅读器里它的语义（视口固定底纹）天然可以「明确忽略」，不影响可读性；而 `font-weight: bolder` 在语料里看似低频（书籍多用数值 400/700），实际却是 `<b>`/`<strong>` 的唯一实现路径（UA 表 `b, strong { font-weight: bolder }`），影响面覆盖所有书的加粗文本。
- 排序口径因此定为：**影响面（是否整类内容失真）× 语料频次 × 修复成本**，见第 5 章。

---

## 3. 属性总表

判定图例：
- **完整**：解析 → 类型化 → 布局或绘制真实读取。
- **部分**：有消费点，但只覆盖子特性（括号内注明缺什么）。
- **零消费**：解析出了字段，但除 `lib/css/` 外无人读取。
- **未处理**：连字段都没有，值停在 `values` map 里。

### 3.1 A 组：解析且真正参与布局/绘制（80 条）

「解析位置」统一在 `packages/reader_core/lib/css/computed_style.dart`（下表简写为 `cs.dart`），
「消费位置」在 `packages/reader_core/lib/layout`（`lb`=line_breaker, `bf`=block_flow, `pg`=paginator, `bm`=box_model）、
`packages/reader_core/lib/paint/page_renderer.dart`（`pr`）、`apps/reader_mobile/lib/reader/epub_chapter_source.dart`（`ecs`）。

| # | 属性 | 解析位置 | 消费位置 | 判定 | 缺失子特性 |
| ---: | --- | --- | --- | --- | --- |
| 1 | `font-size` | cs.dart:468 | lb:1218；pr:1298 | 完整 | `_resolveLength`（cs.dart:2070）覆盖 px/pt/pc/em/rem/%，无 `ch`/`ex`/`vw`/`calc()` |
| 2 | `line-height` | cs.dart:489 | lb:1219 | 完整 | 无 `normal` 之外的按字体度量解算（按 1.2 近似） |
| 3 | `color` | cs.dart:520 | pr:356、pr:466 | 完整 | — |
| 4 | `font-weight` | cs.dart:525 | lb:1221 | **部分** | `bolder`/`lighter` 返回 null 后回落父级字重（`_parseFontWeight` cs.dart:2120 无这两个分支）；无 100-900 之外的相对插值 |
| 5 | `font-style` | cs.dart:530 | lb:1222 | 完整 | `oblique` 按 `italic` 近似 |
| 6 | `font-family` | cs.dart:535 | lb:1225-1229 | 完整 | 无 `font-feature-settings`/`font-stretch` |
| 7 | `font`（简写） | cs.dart:458（`parseFontShorthand` cs.dart:1741，已被级联层复用） | 同上 | **部分** | `small-caps` 被显式丢弃（cs.dart:1793 注释）；`font: caption` 等系统字体关键字返回 null |
| 8 | `text-align` | cs.dart:540 | pr:717-720；lb:751 | 完整 | `justify` 的最后一行/单个西文词的分配策略与 Chrome 有差（README 待收敛 #1） |
| 9 | `text-indent` | cs.dart:576 | lb:431 | 完整 | 只作用于段首行（书籍语义正确）；`hanging` 关键字与负值未特殊处理 |
| 10 | `letter-spacing` | cs.dart:590 | lb:1231 | 完整 | — |
| 11 | `word-spacing` | cs.dart:656 | lb:1232 | 完整 | — |
| 12 | `margin` | cs.dart:607 → `_resolveMargin` cs.dart:1985 | bm:55；pr:445 | 完整 | 相邻块 margin 塌陷未实现（flat 管线按单一基准样式拼合） |
| 13 | `margin-top/-right/-bottom/-left` | cs.dart:1985（`_resolveMargin` 逐边） | bm:56；pr:445-446 | 完整 | 同上 |
| 14 | `padding` | cs.dart:866 → `_resolvePadding` cs.dart:1439 | bm:52；pr:446、669-672 | 完整 | 百分比 padding 按 containingWidth 解算，纵向未按包含块高度 |
| 15 | `padding-top/-right/-bottom/-left` | cs.dart:1439（`_resolvePadding` 逐边） | bm:52；pr:446、669-672 | 完整 | 同上 |
| 16 | `border` | cs.dart:839 → `_resolveBorders` cs.dart:1496 | pr:661、668、880、1043-1164 | 完整 | 不支持 `border-image`；非均匀四边组合靠 `_paintBorders` 拼接 |
| 17 | `border-top/-right/-bottom/-left` | `_resolveBorders` cs.dart:1496（`parseSide`） | pr:668-672 | 完整 | — |
| 18 | `border-width` | cascade.dart:259 → cs.dart:1562（`applyWidths`） | pr:668-672 | 完整 | `thin/medium/thick` 固定 1/3/5px |
| 19 | `border-style` | cascade.dart:259 → cs.dart:1580（`applyStyles`）、`_parseBorderStyle` cs.dart:1722 | pr:1139-1164 | **部分** | `groove`/`ridge`/`inset`/`outset` 解析为 null → 该边样式保持初始 `none`，整条边框消失 |
| 20 | `border-color` | cascade.dart:261 → cs.dart:1598（`applyColors`） | pr:668 | 完整 | 四值 `border-color` 里含函数时靠 `_splitFourValues` 保护括号 |
| 21 | `border-radius` | cs.dart:1676 | pr:900、935-941、1049 | **部分** | 只取单值；不支持 `a / b` 椭圆半径；百分比半径不支持 |
| 22 | `border-top-left-radius` 等四角 | cs.dart:1692 | 同上 | **部分** | 同上 |
| 23 | `width` | cs.dart:860（`dimension`） | bm:52 | 完整 | `auto` 之外无 shrink-to-fit |
| 24 | `height` | cs.dart:861 | bm:53 | 完整 | 百分比高度按 containingWidth 近似（bm 注释已声明） |
| 25 | `min-width` | cs.dart:862 | bm:58 | 完整 | — |
| 26 | `max-width` | cs.dart:863 | bm:59 | 完整 | — |
| 27 | `min-height` | cs.dart:864 | bm:60 | 完整 | — |
| 28 | `max-height` | cs.dart:865 | bm:61 | 完整 | — |
| 29 | `box-sizing` | cs.dart:873 | bm:41 | **部分** | README 待收敛 #5：`border-box` 下可用行宽未扣 padding/border |
| 30 | `background-color` | cs.dart:835 | pr:360-361、655-658、905、944-948 | 完整 | — |
| 31 | `background-image` | cs.dart:838 | pr:1021（`_resolveBackgroundImage`） | **部分** | 只支持单张 `url()`；渐变返回 null（cs.dart:1827 `_parseUrl`）；无多背景层 |
| 32 | `background-repeat` | cs.dart:746 | pr:969 | 完整 | — |
| 33 | `background-size` | cs.dart:749 | pr:970 | 完整 | `cover`/`contain`/显式尺寸均支持（`_parseBackgroundSize` cs.dart:2386） |
| 34 | `background-position` | cs.dart:756 | pr:993 | 完整 | 三/四值语法部分支持（`_parseBackgroundPosition` cs.dart:2436） |
| 35 | `background-origin` | cs.dart:767 | pr:993 | 完整 | — |
| 36 | `background-clip` | cs.dart:770 | pr:980 | **部分** | `text` 降级为 `padding-box`（pr:978 注释） |
| 37 | `background`（简写） | cs.dart:740（`_parseBackgroundShorthand` cs.dart:1922） | pr:969-971 | **部分** | 不含 `attachment`；不解析多背景逗号分层 |
| 38 | `display` | cs.dart:619 | bf:528（`resolveFlowBranch`）；pg:576 | **部分** | `flex`/`inline-flex` 归为 block，`table-row-group`/`table-column`/`table-caption` 未建模（flat 管线） |
| 39 | `position` | cs.dart:617 | bf:522；ecs:2355 | **部分** | 只把 `absolute`/`fixed` 摘出流，不按 inset 定位（`top/right/bottom/left` 零消费）；`relative`/`sticky` 完全无效果 |
| 40 | `float` | cs.dart:618 | bf:525、614 | 完整 | 无 `float: inline-start/end` |
| 41 | `clear` | cs.dart:772 | bf:356 | 完整 | — |
| 42 | `visibility` | cs.dart:622 | pr:440 | 完整 | `collapse` 按 `hidden` 处理 |
| 43 | `white-space` | cs.dart:628 | lb:373-374 | **部分** | README 待收敛 #2：`pre`/`pre-wrap` 的 `\n` 未转硬断行；`pre-line` 折叠规则不完整 |
| 44 | `list-style-type` | cs.dart:786 | ecs:2372（`nextMarker`） | **部分** | disc/circle/square/decimal/lower-roman/upper-roman/lower-alpha/upper-alpha；无 `counter()`/`symbols()` |
| 45 | `list-style`（简写） | cascade.dart:245（展开为 `list-style-type`） | 同上 | 完整 | 只取类型关键字，`position`/`image` 丢弃（`parseListStyleTypeKeyword`） |
| 46 | `table-layout` | cs.dart:793 | ecs:2119 | 完整 | — |
| 47 | `text-decoration` / `-line` | cs.dart:686（`_parseTextDecoration` cs.dart:2602） | lb:1233（`_decoration` lb:1260） | 完整 | 多值合并（`underline line-through`）支持 |
| 48 | `text-decoration-style` | cs.dart:691 | lb:1236（`_decorationStyle` lb:1250） | 完整 | — |
| 49 | `text-decoration-color` | cs.dart:695 | lb:1235 | 完整 | — |
| 50 | `text-shadow` | cs.dart:731 | lb:1237-1245 | 完整 | 多层阴影支持（`_parseTextShadows` cs.dart:2318） |
| 51 | `text-transform` | cs.dart:668 | lb:428 | 完整 | — |
| 52 | `text-align-last` | cs.dart:551 | lb:741、719 | 完整 | — |
| 53 | `text-justify` | cs.dart:544 | lb:736 | **部分** | `auto`/`inter-word`/`inter-character`/`distribute`/`justify-all`，无 `inter-character` 的逐字模式区分细节 |
| 54 | `hanging-punctuation` | cs.dart:634 | lb:730 | **部分** | 只实现 `allow-end`，`allow-start`/`first`/`last`/`force-end` 按 none |
| 55 | `text-spacing-trim` | cs.dart:642 | pr:1535 | **部分** | `space-first`/`trim-start`/`trim-both` 按相邻折叠近似 |
| 56 | `text-autospace` | cs.dart:648 | pr:1539 | **部分** | 只有 `normal`/`none`；未声明时默认 none（与规范默认 normal 有偏差，cs.dart:66 已注明） |
| 57 | `text-emphasis-style` | cs.dart:698 | pr:1374-1392 | 完整 | dot/filled/open/sesame（cs.dart:2622） |
| 58 | `text-emphasis-position` | cs.dart:704 | pr:1415 | **部分** | 只区分 `over`/`under`，不支持 `left`/`right`（竖排向） |
| 59 | `text-emphasis-color` | cs.dart:710 | pr:1398 | 完整 | — |
| 60 | `text-emphasis`（简写） | cs.dart:698 | 同上 | 完整 | — |
| 61 | `vertical-align` | cs.dart:674 | pr:684 | **部分** | 只在表格单元格里对 top/middle/bottom 生效；行内 `sup`/`sub`/`text-top`/`middle` 只做基线位移、不扩行高（README 待收敛 #3） |
| 62 | `page-break-before` / `break-before` | cs.dart:715 | pg:97、620 | 完整 | — |
| 63 | `page-break-after` / `break-after` | cs.dart:718 | pg:98、715 | 完整 | — |
| 64 | `break-inside` / `page-break-inside` | cs.dart:721 | pg:99、627 | 完整 | — |
| 65 | `break-after: avoid` | cs.dart:726 | pg:100、638 | 完整 | — |
| 66 | `opacity` | cs.dart:562 | pr:528（`_withOpacity`） | **部分** | 只在块级用 `saveLayer` 近似；`opacity` 不参与颜色 alpha 合成，嵌套 opacity 不叠乘 |
| 67 | `box-shadow` | cs.dart:571 | pr:544（`_paintBoxShadow`） | **部分** | 无 blur/spread/inset（cs.dart:273 注释已声明）；跨页切片不画 |
| 68 | `text-overflow` | cs.dart:566 | pr:556（`_needsEllipsis`） | **部分** | 只支持 `ellipsis`；`clip` 之外无 `fade` |
| 69 | `duokan-bleed` / `-duokan-bleed` | cs.dart:783（`_parseBleed` cs.dart:1852） | ecs:1660、1718、2459 | 完整 | 多看私有扩展，非标准 |

| 70 | `top` | cs.dart:1413（`_parseOffset` cs.dart:4478） | bf:522；ecs:3284、3258（仅 absolute/fixed） | **部分** | 只对绝对/固定定位生效；常规流与 relative 不读 |
| 71 | `left` | cs.dart:1434（`_parseOffset` cs.dart:4478） | ecs:3287、3259（仅 absolute/fixed） | **部分** | 同上；`right`/`bottom` 仍零消费 |
| 72 | `border-collapse` | cs.dart:1375（`_parseBorderCollapse` cs.dart:4440） | ecs:2539（表格测量与拼接） | 完整 | `collapse` 半边框近似，未逐边求交 |
| 73 | `border-spacing` | cs.dart:1402（`_parseBorderSpacing` cs.dart:4447） | ecs:2540、table_layout.dart:369 | 完整 | collapse 模式下按 0 处理 |
| 74 | `filter` | cs.dart:1106（`_parseFilters` cs.dart:3030） | pr:760（`_withEffects`） | 完整 | 不支持 `url()` 滤镜；`backdrop-filter` 另见 D 组 |
| 75 | `list-style-position` | cs.dart:1391 | ecs:3130、3361 | 完整 | inside/outside 已接入标记宽度 |
| 76 | `content` | ecs:968（`_pseudoContent`） | ecs:3088-3093 | **部分** | 只取字符串与 `attr()`，`counter()`/`url()`/引号形式不支持 |
| 77 | 逻辑属性 `margin-inline-start` 等 | property_aliases.dart:78-81 | margin 路径（cs.dart:2040 起） | 完整 | 横排 LTR 近似；RTL 会错边 |
| 78 | `hyphens` | cs.dart:1143（`_parseHyphens` cs.dart:3522） | lb:563（`planSoftBreaks`）、pr:313（行尾连字符） | 完整 | 断点、行宽与行尾连字符都已绘制 |
| 79 | `word-break` | cs.dart:1147（`_parseWordBreak` cs.dart:3532） | lb:563、lb:622 | 完整 | `keep-all`/`break-all` 已参与断点 |
| 80 | `overflow-wrap` / `word-wrap` | cs.dart:1153（`_parseOverflowWrap` cs.dart:3542） | lb:562 | 完整 | 与 `word-break` 共用断点规划 |

### 3.2 B 组汇总：只消费一部分的 25 条

上表判定为「部分」的条目，按缺失性质归类：

这 25 条与上表编号 4、7、19、21、22、29、31、36、37、38、39、43、44、53、54、55、56、58、61、66、67、68、70、71、76 一一对应，按缺失性质归为 5 类：

| 缺失性质 | 属性（对应编号） | 一句话后果 |
| --- | --- | --- |
| 值解析不全，值被丢后回退初始值 | `font-weight`(4)、`border-style`(19)、`border-radius`(21/22) | 加粗失效 / 该边边框整条消失 / 圆角变直角 |
| 只实现一个或部分枚举成员 | `text-justify`(53)、`hanging-punctuation`(54)、`text-spacing-trim`(55)、`text-autospace`(56)、`text-emphasis-position`(58) | 声明了但落到默认分支 |
| 消费点只覆盖一种布局上下文 | `vertical-align`(61)、`opacity`(66)、`box-shadow`(67)、`text-overflow`(68)、`top`(70)、`left`(71) | 行内上下标不扩行高 / 嵌套透明度不叠乘 / 阴影没模糊 / 非 ellipsis 不裁 |
| 简写展开丢成员 | `font`(7)、`background`(37)、`list-style-type`(44)、`content`(76) | `font: small-caps …` / `background: … fixed` 丢效果 / 自定义计数无解 |
| 布局盒与绘制层近似 | `box-sizing`(29)、`display`(38)、`position`(39)、`background-image`(31)、`background-clip`(36)、`white-space`(43) | `border-box` 行宽超界 / `flex` 退化为块 / absolute 不定位 / 渐变丢失 / `pre` 挤成一行 |

### 3.3 C 组：解析出字段但零消费（占位式实现，9 条）

「解析位置」= 有类型化字段与解析函数；「消费位置」= 全库检索（排除 `lib/css/`）无任何读取点。

| # | 属性 | 解析位置 | 字段 | 消费位置 | 判定 |
| ---: | --- | --- | --- | --- | --- |
| 81 | `right` | cs.dart:1420（`_parseOffset` cs.dart:4478） | `ComputedStyle.right` cs.dart:2081 | **无**（`style.right` 0 命中） | 零消费 |
| 82 | `bottom` | cs.dart:1427 | `ComputedStyle.bottom` cs.dart:2084 | **无** | 零消费 |
| 83 | `initial-letter` | cs.dart:1082（`_parseInitialLetter` cs.dart:4162） | `ComputedStyle.initialLetterLines` cs.dart:1915 | **无**（`.initialLetterLines` 除 css/ 外 0 命中） | 零消费 |
| 84 | `transform` / `transform-origin` | cs.dart:1114、1118（`_parseTransforms` cs.dart:3223、`_parseTransformOrigin` cs.dart:3367） | `transforms` cs.dart:1939、`transformOriginX/Y` cs.dart:1942 | **无**（`.transforms` 0 命中） | 零消费 |
| 85 | `columns` / `column-count` / `column-width` / `column-gap` / `column-rule` | cs.dart:1042（`_resolveColumns` cs.dart:3560） | `columnCount/Width/Gap/Rule` cs.dart:1972-1981 | **无**（四个字段在 layout/paint 0 命中） | 零消费 |
| 86 | `writing-mode` | cs.dart:1124（`_parseWritingMode` cs.dart:3473） | `ComputedStyle.writingMode` cs.dart:1948 | **无**（`page_snapshot.dart:24` 的默认字符串不算消费） | 零消费 |
| 87 | `text-orientation` | cs.dart:1130（`_parseTextOrientation` cs.dart:3483） | `ComputedStyle.textOrientation` cs.dart:1951 | **无** | 零消费 |
| 88 | `direction` | cs.dart:1136（`_parseDirection` cs.dart:3494） | `ComputedStyle.direction` cs.dart:1954 | **无** | 零消费 |
| 89 | `overflow`（含 `overflow-x`） | cs.dart:1163（`_parseOverflow` cs.dart:3503） | `ComputedStyle.overflow` cs.dart:1969 | **无**（绘制层尚未按此裁剪） | 零消费 |

补充说明：

- `top` / `left` 已从 C 组移入 A 组：章节源只在 `position: absolute/fixed` 时读它们，常规流与 `relative` 仍不定位。`right` / `bottom` 没有对应消费，留在 C 组。
- `border-collapse` / `border-spacing` 已从 C 组移入 A 组：表格测量与单元格拼接已经读取，collapse 用半边框近似。
- `transform`、`columns`、`writing-mode`、`text-orientation`、`direction`、`overflow` 在本轮工作树里完成「字段 + 解析」，但没有任何布局/绘制读取。它们比 D 组多走了一步，仍属占位式实现。
- `overflow-x` 会并入 `overflow` 字段（cs.dart:1161），`overflow-y` 直接丢失；当前字段本身也没有消费点。

### 3.4 D 组：连字段都没有，值被静默丢弃（27 条）

这些属性在 CSS 里被 `Cascade._consider`（cascade.dart:488）按名字存入 `winners`，随后进入 `ComputedStyle.values`，但**没有对应类型化字段，也没有任何消费点**。`grep` 属性名在全库（排除 `ua_stylesheet.dart` 与 `property_aliases.dart`）0 命中。

| # | 属性 | 解析位置 | 消费位置 | 语料频次/书数 | 缺失后果 |
| ---: | --- | --- | --- | --- | --- |
| 90 | `border-image` | 无（值仅存 `values`） | 无 | 11 / 3 | 图片边框（花纹分隔线、老式卡片）退化为 `border` 纯色或完全无边框 |
| 91 | `line-break` | 别名层映射（property_aliases.dart:47-48） | 无（全库检索 0 命中） | 0（别名 6 处） | `strict`/`loose` 标点禁则严格度不生效 |
| 92 | `font-variant` | 无（`font` 简写里的 `small-caps` 被显式丢弃，cs.dart:2647） | 无 | 7 / 1 | `small-caps` 小体大写字母全部按普通字重渲染 |
| 93 | `quotes` | 无（值仅存 `values`） | 无 | 0 | `q` 元素与 `content: open-quote` 无引号 |
| 94 | `counter-reset` / `counter-increment` | 无（值仅存 `values`） | 无 | 0 | 自动编号目录、图表序号失效 |
| 95 | `object-fit` / `object-position` | 无（值仅存 `values`） | 无 | 1 / 1 | 图片按 `contain` 拉伸近似，`cover`/`fill`/`none` 无法表达 |
| 96 | `backdrop-filter` | 无（值仅存 `values`） | 无 | 3 / 2 | 背景模糊失效；`filter` 已实现，但 backdrop 是另一条绘制路径 |
| 97 | `mix-blend-mode` | 无（值仅存 `values`） | 无 | 0 | 叠加模式失效 |
| 98 | `z-index` | 无（值仅存 `values`） | 无 | 4 / 2 | 绝对定位元素的层叠顺序退化为遍历顺序 |
| 99 | `background-attachment` | 无（`background` 简写也不解析，cs.dart:3866 注释） | 无（全库检索 0 命中） | **218 / 3** | `fixed` 底纹按 scroll 处理（分页阅读器里合理降级，但需显式记录） |
| 100 | `justify-content` / `align-items` | 无（值仅存 `values`） | 无 | 14 / 13 | `display:flex` 容器退化为块，居中/两端排布失效 |
| 101 | `orphans` / `widows` | 无（值仅存 `values`） | 无 | 7 / 7 | 页底/页首孤行控制失效 |
| 102 | `unicode-bidi` | UA 表有（`bdi`/`bdo`），引擎未消费 | 无 | 0 | `bdo` 覆写不生效 |
| 103 | `ruby-align` | 继承表有（cascade.dart:72） | 无 | 4 / 3 | 注音对齐方式不生效 |
| 104 | `ruby-position` | 无（值仅存 `values`） | 无 | 0 | 注音恒在上方 |
| 105 | `list-style-image` | 无（值仅存 `values`） | 无 | 0 | 图片列表标记不支持 |
| 106 | `tab-size` | 无（值仅存 `values`） | 无 | 0 | `pre` 里的制表符按固定宽近似 |
| 107 | `text-combine-upright` | 别名层映射（property_aliases.dart:73-75） | 无（全库检索 0 命中） | 4 别名 / 1 | 竖排「縦中横」（年份/数字横倒转）不支持 |
| 108 | `font-feature-settings` / `font-kerning` / `font-variant-ligatures` | 无（值仅存 `values`） | 无 | 0 | OpenType 特性无法开启 |
| 109 | `font-size-adjust` | 无（值仅存 `values`） | 无 | 0 | 字体 x-height 补偿不支持 |
| 110 | `outline` | 无（值仅存 `values`） | 无 | 0 | 焦点框（阅读器无交互，影响 0） |
| 111 | `cursor` | 无（值仅存 `values`） | 无 | 3 / 2 | 指针形状（阅读器无交互，影响 0） |
| 112 | `user-select` / `resize` / `will-change` / `contain` | 无（值仅存 `values`） | 无 | 1 / 0 | 交互与渲染提示（阅读器无影响） |
| 113 | `scrollbar-width` / `-ms-overflow-style` | 无（值仅存 `values`） | 无 | 2 / 1 | 无滚动条（分页阅读器无影响） |
| 114 | `box-decoration-break` | 无（值仅存 `values`） | 无 | 1 / 1 | 跨页切片时边框/圆角/背景不重复，语义上接近当前取舍 |
| 115 | `caption-side` / `empty-cells` | 无（值仅存 `values`） | 无 | 0 | 表格标题位置与空单元格边框 |
| 116 | `aspect-ratio` | 无（值仅存 `values`） | 无 | 0 | 图片容器比例约束 |

> 本轮从 D 组移出的条目：`transform`、`columns`、`writing-mode`、`text-orientation`、`direction`、`overflow`/`overflow-x` 移入 C 组（字段已解析、消费为零）；`hyphens`、`word-break`、`overflow-wrap`/`word-wrap` 移入 A 组（断点与行尾连字符已消费）；`filter` 移入 A 组；`list-style-position`、`content`、逻辑属性移入 A 组；`backdrop-filter` 从原 `filter` 行拆出，留在 D 组。

### 3.5 本轮 C/D 变更摘要

| 变更 | 属性 | 旧分类 | 新分类 | 证据 |
| --- | --- | --- | --- | --- |
| 移入 A | `top` / `left` | C | A（部分） | ecs:3284、3108 只在 absolute/fixed 读 |
| 移入 A | `border-collapse` / `border-spacing` | C | A | ecs:2539、2368 |
| 移入 A | `filter` | D | A | pr:760 `_withEffects` |
| 移入 A | `list-style-position` | D | A | ecs:3130、3361 |
| 移入 A | `content` | D | A（部分） | ecs:968、3088 |
| 移入 A | 逻辑属性 | D | A | property_aliases.dart:78-81 |
| A 内更新 | `text-overflow` | A（部分） | A（部分，省略号截断进断行器） | lb:1128 `_applyTextOverflow`、pr:1261 |
| 移入 A | `hyphens` | D | A | lb:563、609、pr:313 |
| 移入 A | `word-break` | D | A | lb:563、622 |
| 移入 A | `overflow-wrap` / `word-wrap` | D | A | lb:562 |
| 移入 C | `transform` | D | C | cs.dart:1939、3223，零消费 |
| 移入 C | `columns` 组 | D | C | cs.dart:1972-1981、3560，零消费 |
| 移入 C | `writing-mode` | D | C | cs.dart:1948、3473，零消费 |
| 移入 C | `text-orientation` | D | C | cs.dart:1951、3483，零消费 |
| 移入 C | `direction` | D | C | cs.dart:1954、3494，零消费 |
| 移入 C | `overflow` / `overflow-x` | D | C | cs.dart:1969、3503，零消费 |
| 保持 D | `backdrop-filter` | D（原与 filter 同行） | D | 无字段；filter 已独立实现 |

## 4. 占位式实现专项（C 组 + 关键 D 组）

> 下列条目录自审计基线，已修复的保留作对照；当前分类以第 3.3、3.4、3.5 节为准。

### 4.1 `top` / `right` / `bottom` / `left`（inset）

- 浏览器语义：绝对定位盒相对包含块四边的偏移；`absolute` 下决定位置，`relative` 下做相对位移。
- 引擎现状：`_parseOffset`（cs.dart:4478）把值解析成 `CssLength` 存进四个字段。章节源在 `position: absolute/fixed` 时读 `top`（ecs:3284）与 `left`（ecs:3287），换算成覆盖切片的页内坐标；`right`/`bottom` 仍无消费。
- 缺失子特性：`right`/`bottom`、`position: relative` 的偏移、`sticky`、`inset` 简写（`inset: 0`）。
- 影响示例：`tool/css_parity/cases/09-box-model.json` 可加一组 `position:absolute; top:0; left:0` 的徽标块；真实书里封面页「书名贴在图片左上角」、章节装饰线全部错位。
- 实现难度：**M**。需要给 `AbsoluteFlowBlock` 引入包含块概念，并在 paginator 定页后换算 y。
- 建议文件：`packages/reader_core/lib/layout/block_flow.dart`（`AbsoluteFlowBlock`）、`packages/reader_core/lib/layout/paginator.dart`；消费入口在 `apps/reader_mobile/lib/reader/epub_chapter_source.dart:2252`。

### 4.2 `border-collapse` / `border-spacing`

- 浏览器语义：`collapse` 合并相邻单元格边框为单线；`separate` 保留间距（`border-spacing`）。
- 引擎现状：字段与解析齐备（cs.dart:2051/2054、4440/4447）。章节源在表格测量与拼接时读 `borderCollapse`（ecs:2539）与 `borderSpacing`（ecs:2540），collapse 用半边框近似，spacing 进入 `table_layout.dart`。
- 缺失子特性：collapse 的相邻边精确求交（当前半宽近似）、`border-spacing` 的两值（横/纵）完整语义。
- 影响示例：真实语料 `border-collapse` 52 次 / 4 本、`border-spacing` 19 次 / 1 本；双线已消除，边框宽度与 Chrome 仍有小差。
- 实现难度：剩余收口 **S**（精确半宽分配）。
- 建议文件：`packages/reader_core/lib/paint/page_renderer.dart`（`_paintCellBorders`）、`packages/reader_core/lib/layout/table_layout.dart`。

### 4.3 `font-weight: bolder / lighter`（已修复）

- 浏览器语义：相对父元素字重上/下一档（`bolder` 从 400 → 700）。
- 引擎现状：已修复。`_parseFontWeight`（cs.dart:4031 起）按父级映射 `bolder`/`lighter`，`<b>/<strong>` 正常加粗。
- 剩余边界：1000 以上没有更高档，非整百字重按规范中点映射。
- 验证：`tool/css_parity/cases/07-font-weight-style.json` 已覆盖 `b/strong`。

### 4.4 `initial-letter`（首字下沉）

- 浏览器语义：段首字放大并占据 N 行。
- 引擎现状：`_parseInitialLetter`（cs.dart:4162）解析出行数，字段 `initialLetterLines` 存在（cs.dart:1915），**零消费**。
- 影响示例：中文古籍/文艺类书常见首字下沉；`ecs` 里已有 `_firstLetterRun`（ecs:1034）做首字提取，但没有放大逻辑，可复用该入口。
- 实现难度：**M**（要参与首行行高计算）。
- 建议文件：`packages/reader_core/lib/layout/line_breaker.dart`（首行行盒）、`apps/reader_mobile/lib/reader/epub_chapter_source.dart`（`_firstLetterRun`）。

### 4.5 `writing-mode`（含 6 条私有别名）

- 浏览器语义：`vertical-rl` 竖排、列方向从右到左、标点与数字竖排变形。
- 引擎现状：别名层把多看族统一成 `writing-mode`（property_aliases.dart:56-62），工作树已新增 `CssWritingMode` 字段与解析（cs.dart:1948、3473），但**布局/绘制没有消费点**；`bf:519` 仍写着「竖排分支尚未接入」。
- 影响示例：`test_corpus/cjk-vertical.epub` 是按竖排声明的书；真实语料 5 次 + 18 条私有别名 / 3 本。
- 实现难度：**L**（竖排要重做列布局、标点旋转、注音位置、分页方向）。最小可行方案见 [`docs/duokan-private-css.md`](duokan-private-css.md) 第 7 节。
- 建议文件：`paginator.dart`、`line_breaker.dart`、`page_renderer.dart`、`epub_chapter_source.dart`；字段已在 `computed_style.dart`。

### 4.6 `overflow`（含 UA 表的 `hidden`）

- 浏览器语义：内容超出盒时裁剪（hidden）/滚动（auto/scroll）。
- 引擎现状：工作树已新增 `CssOverflow` 字段与解析（cs.dart:1969、3503），但绘制层没有按它裁剪；`ua_stylesheet.dart:33` 的 `overflow: hidden` 仍只是文本。
- 影响示例：作者用 `overflow:hidden` 裁掉绝对定位装饰（扫码/水印/花纹）的老式排版书会露出溢出的图；`tool/css_parity/cases/14-float-overflow.json` 已存在该主题用例。
- 实现难度：**S**（块级 `clipRect`）。
- 建议文件：`packages/reader_core/lib/paint/page_renderer.dart`（块绘制前 `canvas.clipRect`）。

### 4.7 `transform`

- 浏览器语义：2D/3D 变换。
- 引擎现状：工作树已新增 `CssTransform` 列表与 `transform-origin` 字段（cs.dart:1939/1942、3223/3367），但绘制层没有读取，仍无视觉效果。
- 影响示例：书封/横幅图 `transform: scale(1.1)` 或 `rotate(-90deg)` 的装饰；21 次 / 2 本。
- 实现难度：**M**（要落到 `canvas.transform`，且与分页切片的坐标变换交互）。
- 建议文件：`packages/reader_core/lib/paint/page_renderer.dart`；解析新增于 `packages/reader_core/lib/css/computed_style.dart`。

### 4.8 `border-image`

- 浏览器语义：用图片九宫格替换 `border-style` 绘制。
- 引擎现状：无字段、无消费。真实书 11 次 / 3 本（花纹分隔线）。
- 实现难度：**M**（九宫格切片 + `ImageShader`）。
- 建议文件：`packages/reader_core/lib/paint/page_renderer.dart`（`_paintBorders` pr:1043 旁路）。

### 4.9 `box-shadow` 的 blur / spread / inset（已修复）

- 引擎现状：已支持 offset/blur/spread/inset（cs.dart:739 起），`_paintBoxShadow` 与 `_paintInsetBoxShadow`（pr:993/1000 起）分别绘制外阴影与内阴影。
- 剩余边界：多层阴影只取第一个；跨页切片不重复投影。
- 实现难度：剩余收口 **S**。
- 建议文件：`packages/reader_core/lib/paint/page_renderer.dart`。

### 4.10 `vertical-align` 的行内一侧

- 引擎现状：`verticalAlignShift`（cs.dart:1339）提供基线位移，但行高不扩；`pr:684` 的 `switch` 只处理表格单元格的 middle/bottom/top。
- 影响示例：README 待收敛 #3 已记录（浏览器 32.5 / 引擎 31）；`tool/css_parity/cases/05-vertical-align.json` 是该主题的既有用例。
- 实现难度：**M**（行盒需按 run 的最大上/下伸出重算行高）。
- 建议文件：`packages/reader_core/lib/layout/line_breaker.dart`（行高合成处）。

---

## 5. Top 20 待修清单（影响 × 真实书频率）

排序口径：**影响面**（P0 整类内容失真 / P1 明显偏差 / P2 局部瑕疵）× **语料证据** × **修复成本**。
「成本」= S（≤1 天）/ M（2-3 天）/ L（1 周以上）。

| 排名 | 属性 / 缺陷 | 影响 | 证据（频次/书数 或 代码事实） | 成本 | 落点文件 |
| ---: | --- | --- | --- | --- | --- |
| 1 | `font-weight: bolder/lighter` 不解析 → `<b>/<strong>` 不加粗 | P0（已修复） | `_parseFontWeight` 已按父级映射；用例 `07` 覆盖 | S | `packages/reader_core/lib/css/computed_style.dart:2120`（`_parseFontWeight`）+ 用例 `tool/css_parity/cases/07-font-weight-style.json` |
| 2 | `top/right/bottom/left` 零消费 → absolute 定位只有「摘出流」没有「定位」 | P0（top/left 已部分修复） | ecs:3284/3287 只读 top/left；right/bottom 仍零 | M | `packages/reader_core/lib/layout/block_flow.dart:521`（`AbsoluteFlowBlock`）、`packages/reader_core/lib/layout/paginator.dart` |
| 3 | `border-collapse` / `border-spacing` 零消费 → 表格恒双线 | P0（已修复，精度待收口） | ecs:2539/2540 已消费；语料 52/4 本 + 19/1 本 | M | `packages/reader_core/lib/paint/page_renderer.dart:661`（`_paintCellBorders`）、`packages/reader_core/lib/layout/table_layout.dart` |
| 4 | `white-space: pre/pre-wrap` 换行未转硬断行 | P0 | README 待收敛 #2；语料 54/3 本 | S | `packages/reader_core/lib/layout/line_breaker.dart:373` |
| 5 | `box-sizing: border-box` 行宽未扣 padding/border | P1 | README 待收敛 #5；语料 20/2 本 | S | `packages/reader_core/lib/layout/box_model.dart:41`、`packages/reader_core/lib/layout/line_breaker.dart:338`（`effectiveWidth`） |
| 6 | `border-style` 的 `groove/ridge/inset/outset` 解析为 null → 边框整条消失 | P1 | `_parseBorderStyle` `cs.dart:1722` 只有 5 个分支；语料 `border-style` 280/5 本 | S | `packages/reader_core/lib/css/computed_style.dart:1722`、降级映射至 `packages/reader_core/lib/paint/page_renderer.dart:1139` |
| 7 | `display: flex` 退化为 block，`justify-content`/`align-items` 无效 | P1 | `resolveFlowBranch` `bf:528` 无 flex 分支；语料 221/5 + 14/4 + 13/3 | L | `packages/reader_core/lib/layout/block_flow.dart:528`（新增 flex 分派） |
| 8 | `border-radius` 只认单值、无椭圆/百分比 | P1 | `cs.dart:1676` 只取 `tokens` 循环；语料 560/6 本（最高频的「部分实现」） | M | `packages/reader_core/lib/css/computed_style.dart:1676`、`packages/reader_core/lib/paint/page_renderer.dart:935` |
| 9 | `box-shadow` 无 blur/spread/inset | P1（已修复） | `_parseBoxShadow` 与 `_paintInsetBoxShadow` 已覆盖；多层阴影仍只取第一个 | S | `packages/reader_core/lib/paint/page_renderer.dart:544`（`_paintBoxShadow`） |
| 10 | `overflow` 完全未处理（含 UA `overflow:hidden`） | P1（字段已解析、零消费） | 语料 25/4 本；cs.dart:1969 有字段，绘制未裁剪 | S | `packages/reader_core/lib/paint/page_renderer.dart`（块绘制前 `clipRect`） |
| 11 | `vertical-align` 行内不扩行高（sup/sub/text-top） | P1 | README 待收敛 #3；语料 319/7 本 | M | `packages/reader_core/lib/layout/line_breaker.dart`（行高合成） |
| 12 | `writing-mode` 无字段无消费（含 6 条私有别名） | P1（竖排书为 P0；字段已解析） | `bf:519` 注释「尚未接入」；语料 5 + 18 别名 / 3 本 | L | `packages/reader_core/lib/css/computed_style.dart`（新增字段）、`packages/reader_core/lib/layout/line_breaker.dart` |
| 13 | `transform` 完全未处理 | P1（字段已解析、零消费） | 语料 21/2 本 | M | `packages/reader_core/lib/paint/page_renderer.dart` |
| 14 | `word-break`（`break-all`/`keep-all`）未处理 | P1（已消费） | 语料 12/5 本 | S | `packages/reader_core/lib/layout/line_breaker.dart`（断行候选点） |
| 15 | `background-attachment` 未处理（简写里也丢） | P2（可显式声明不支持） | 语料 **218/3 本**（最高频缺失项） | S | `packages/reader_core/lib/css/computed_style.dart:1922`（`_parseBackgroundShorthand`）+ 文档化降级 |
| 16 | `border-image` 未处理 | P1 | 语料 11/3 本 | M | `packages/reader_core/lib/paint/page_renderer.dart:1043`（`_paintBorders` 旁路） |
| 17 | `initial-letter` 零消费（首字下沉） | P2 | 字段齐备、`.initialLetterLines` 0 命中 | M | `packages/reader_core/lib/layout/line_breaker.dart`、`apps/reader_mobile/lib/reader/epub_chapter_source.dart:676`（`_firstLetterRun`） |
| 18 | `background-clip: text` 降级 + `duokan-text-fill` 渐变文字退化为纯色 | P2 | `pr:978` 注释；别名 `duokan-text-fill` 取首色标（property_aliases.dart:25） | M | `packages/reader_core/lib/paint/page_renderer.dart:980` |
| 19 | `font-variant: small-caps` 丢弃（简写内也丢） | P2 | `cs.dart:1793` 显式忽略；语料 7/1 本 | M（需小型大写合成） | `packages/reader_core/lib/css/computed_style.dart:1793`（`small-caps` 丢弃分支）、`packages/reader_core/lib/layout/line_breaker.dart:1218`（`textStyleFor`） |
| 20 | `orphans`/`widows` 未处理 | P2 | 语料 7/7 各 1 本 | M | `packages/reader_core/lib/layout/paginator.dart`（分页决策） |

本轮状态刷新（按 `abc6ed1` + 未提交改动）：

| 排名 | 当前状态 |
| ---: | --- |
| 1 | 已修复：`bolder`/`lighter` 按父级映射，`b/strong` 正常加粗 |
| 2 | 部分修复：`top`/`left` 在 absolute/fixed 下生效；`right`/`bottom` 仍在 C 组 |
| 3 | 已修复：`border-collapse`/`border-spacing` 进入表格测量与拼接，collapse 用半边框近似 |
| 6 | 部分降级：`groove/ridge/inset/outset` 映射为 solid，不再整条消失，但与 Chrome 线型不同 |
| 9 | 已修复：`box-shadow` 支持 blur/spread/inset，多层阴影仍只取第一个 |
| 10 | 字段与解析已加，绘制仍未按 `overflow` 裁剪（C 组 #89） |
| 12 | 字段与解析已加，布局/绘制仍不消费（C 组 #86） |
| 13 | 字段与解析已加，绘制层仍不消费（C 组 #84） |
| 14 | 已消费：`word-break` 进入断点规划（A 组 #79） |
| 15 | 未变：`background-attachment` 仍无字段，按 scroll 降级 |
| 17 | 未变：`initial-letter` 字段仍零消费（C 组 #83） |
| 18 | 未变：`duokan-text-fill` 渐变仍取首色 |

补充两条「低成本高确定性」的候补，若排期允许应与 Top 5 合并处理：

- `z-index` 未处理（语料 4/2 本）→ 与第 2 名 inset 一起做，绝对定位栈序需要它才有意义；落点 `packages/reader_core/lib/paint/page_renderer.dart`。
- `text-decoration: overline` 已支持但 `text-decoration-line` 的多值合并未覆盖（`cs.dart:686`），属 S 级收口。

---

## 6. 别名层「伪支持」风险（必须先处理）

`packages/reader_core/lib/css/property_aliases.dart` 把大量私有属性重命名到标准属性。审计发现**4 个映射目标本身零消费**，等于把「明确不支持」变成「看起来支持」：

| 别名（含当前工作树新增） | 映射目标 | 目标是否有消费点 |
| --- | --- | --- |
| `duokan-line-break` / `webkit-line-break` | `line-break` | **否**（无字段） |
| `epub-hyphens` / `webkit-hyphens` | `hyphens` | **是**（断点与行尾连字符都已消费） |
| `epub-text-combine` / `webkit-text-combine` / `ms-text-combine-horizontal` | `text-combine-upright` | **否**（无字段） |
| `duokan-text-orientation` / `epub-text-orientation` | `text-orientation` | **否**（有字段，布局不读） |
| `duokan-writing-mode` / `epub-writing-mode` / `webkit-writing-mode` / `duokan-block-progression` / `duokan-writing-orientation` | `writing-mode` | **否**（有字段，布局不读） |

风险：这些别名让「私有属性兼容」的覆盖率数字变好看，但排版结果没有任何变化；后续排查「为什么竖排没生效」时会先怀疑别名，实际卡在消费点。竖排族已有字段，比纯别名好排查，但在消费点落地前仍是伪支持。建议给每个「别名目标」补一条消费点断言（或至少在该文件注释里标注「目标属性当前零消费」）。

正向对照：`webkit-margin-start` → `margin-left`（property_aliases.dart:72-75）是**有效别名**的样板——目标属性有完整消费链，映射后立即生效。

---

## 7. 与现有 parity 用例的对照

审计期间 `tool/css_parity/cases/` 已从 14 个扩到 **60 个**（`01`–`60`），原计划的「新增用例」基本都已落地。对照结论：

| Top 20 条目 | 现有用例 | 覆盖判断 |
| --- | --- | --- |
| #1 `font-weight: bolder` / `<b>/<strong>` | `07-font-weight-style.json` | **已覆盖**：用例含 `bolder`、`<b>`、`<strong>`，可作回归 |
| #2 inset / `position:absolute` / `z-index` | `09-box-model.json`（只有普通盒与 `box-sizing`） | **未覆盖**：无绝对定位、无 inset、无 z-index |
| #3 `border-collapse` / `border-spacing` | `12-table.json`、`32-table-colspan-rowspan.json`、`33-table-layout-fixed.json`、`43-multipage-table.json` | **已覆盖**：字段已消费，双线消除，剩余半宽精度差异可继续对照 |
| #4 `white-space: pre/pre-wrap` | `06-white-space.json`（`pre`/`nowrap`/`pre-wrap` 三态）、`40-text-overflow.json` | **已覆盖** |
| #5 `box-sizing` | `09-box-model.json`（`.bb` 行）、`21-box-sizing.json`、`23-percent-padding-margin.json` | **已覆盖** |
| #6 `border-style` 全枚举 | `25-border-style-all.json` | **已覆盖**（`groove/ridge/inset/outset` 应有对比行） |
| #7 `display:flex` + `justify-content`/`align-items` | 无 flex 用例 | **未覆盖** |
| #8 `border-radius` 椭圆/百分比 | `24-border-radius-corners.json`（`4px 12px` 等多值） | 部分覆盖；`a / b` 椭圆与 `%` 未覆盖 |
| #9 `box-shadow` blur/spread/inset | `13-shadow-opacity.json`（`3px 3px 6px` 带 blur） | **已覆盖**（引擎必然少模糊） |
| #10 `overflow` | `14-float-overflow.json`（`.ov` 恰好 `overflow:hidden` + 固定高）、`40-text-overflow.json` | **已覆盖**（`14` 的 `.ov` 是现成失败样本） |
| #11 行内 `vertical-align` 不扩行高 | `05-vertical-align.json`（`sub`/`6px`/`text-top`/`text-bottom`/`middle`） | **已覆盖** |
| #12 `writing-mode` | `35-writing-mode.json`（`vertical-rl` 等） | **已覆盖** |
| #13 `transform` | `36-transform.json`（`translate` 等） | **已覆盖** |
| #14 `word-break` | `20-hyphens-quotes.json`（同一文件含 `hyphens`/`quotes`/`word-break`/`overflow-wrap`） | **已覆盖** |
| #15 `background-attachment` | 无 | **未覆盖** |
| #16 `border-image` | 无 | **未覆盖** |
| #17 `initial-letter` | 无 | **未覆盖** |
| #18 `background-clip: text` / 渐变文字 | `26-background-gradient.json`、`28-background-clip-origin.json` | 部分覆盖；`clip:text` 与 `duokan-text-fill` 降级未覆盖 |
| #19 `font-variant: small-caps` | `15-font-variant-stretch.json` | **已覆盖** |
| #20 `orphans` / `widows` | 无（`41-page-break-control.json` 只覆盖 `break-*`） | **未覆盖** |
| — `filter` / `opacity` | `37-filter-opacity.json` | 已覆盖 |
| — `columns` | `34-columns.json` | 已覆盖 |
| — `list-style-position` | `30-list-style-position.json`、`31-list-nested.json` | 已覆盖 |

**真正还缺的用例只有 6 个**（按优先级）：

| 建议新增 | 覆盖内容 | 对应条目 |
| --- | --- | --- |
| `44-inline-bold.json` | `<b>/<strong>`、`font-weight: bolder/lighter`、`font: bolder 16px serif` | Top #1（影响面最大且零覆盖） |
| `45-position-inset.json` | `position: absolute/relative` + `top/right/bottom/left` + `z-index` 叠放 | Top #2 |
| `46-flex-basic.json` | `display:flex` + `justify-content`/`align-items` 三种对齐 | Top #7 |
| `47-background-attachment.json` | `background-attachment: fixed/scroll/local` | Top #15 |
| `48-border-image.json` | 九宫格 `border-image` 与 `border` 降级对照 | Top #16 |
| `49-initial-letter.json` | `initial-letter: 3` 首字下沉 | Top #17 |
| `50-orphans-widows.json` | `orphans`/`widows` 跨页行为 | Top #20 |

用例格式沿用现有约定 `{name, css, html}`，跑法见 `tool/css_parity/README.md`。

> 注意：`05`、`06`、`09`、`13`、`14`、`12`、`20`、`25`、`35`、`36` 等用例的 `css` 里已写入本文判定「未实现/零消费」的声明。这些用例跑出来必然有差异——它们本身就是最好的失败回归靶子，不需要再造新用例。

---

## 附录 A：统计与校验命令

### A.1 真实书属性频率

```bash
cd <repo>
/usr/bin/python3 - <<'PY'
import zipfile, re, glob, collections, os
props = collections.Counter(); books = collections.Counter()
for path in sorted(glob.glob('test_corpus/real/*.epub')):
    z = zipfile.ZipFile(path); c = collections.Counter()
    for name in z.namelist():
        if not name.lower().endswith(('.css', '.xhtml', '.html', '.htm')):
            continue
        raw = z.read(name).decode('utf-8', 'ignore')
        text = re.sub(r'/\*.*?\*/', '', raw, flags=re.S)
        for m in re.finditer(r'\{([^{}]*)\}', text):
            for decl in m.group(1).split(';'):
                if ':' not in decl:
                    continue
                p = decl.split(':', 1)[0].strip().lower()
                if not re.fullmatch(r'-?[a-z][a-z0-9-]*', p):
                    continue
                c[p] += 1
    for p, v in c.items():
        props[p] += v; books[p] += 1
for p, v in props.most_common():
    print(f'{v:6d} books={books[p]} {p}')
PY
```

### A.2 「解析了但没消费」的一键排查

```bash
# 逐字段统计 css/ 之外的读取次数（0 = 占位式）
cd <repo>
for f in borderCollapse borderSpacing initialLetterLines top right bottom left; do
  n=$(grep -rn "\.$f\b" packages/reader_core/lib apps --include=*.dart \
      | grep -v "lib/css/computed_style.dart" | grep -v "/test/" | wc -l | tr -d ' ')
  echo "$f = $n"
done
```

### A.3 「完全未处理」的一键排查

```bash
cd <repo>
for p in transform border-image writing-mode columns overflow word-break \
         line-break font-variant hyphens quotes counter-reset object-fit \
         filter mix-blend-mode background-attachment z-index; do
  n=$(grep -rnE "'$p'|\"$p\"|$p:" packages/reader_core/lib apps/reader_mobile/lib \
      --include=*.dart | grep -v ua_stylesheet | grep -v property_aliases | wc -l | tr -d ' ')
  echo "$p = $n"   # 0 = 连属性名都没出现
done
```

---

## 附录 B：本审计的边界

- **只做静态审计。** 除 §4.3 的 `bolder` 结论用一次性探针实测（`flutter test /tmp/...`，未落库、未改仓库）外，其余判定均来自源码阅读 + 全库检索。布局的实际数值偏差应以 `tool/css_parity` 的 `report.md` 为准。
- **未覆盖 `@font-face` 描述符、`@supports`、`@page`、`@charset` 等 at-rule。** 它们不属于「CSS 属性」范畴，见 `font_face.dart` / `parser.dart` 的独立审计。
- **未覆盖伪元素（`::before`/`::after`/`::first-letter`/`::first-line`）的样式作用域。** `content` 只在 D 组列了一条边缘观察。
- **行号会漂移。** 基线提交 `abc6ed1` + 未提交改动；并发改动仍在修改 `computed_style.dart`、`line_breaker.dart`。定位时优先用文中给出的函数名/分支锚点。
- **语料规模有限。** 7 本真实书只能给出量级参考；`duokan-*` 私有属性在非多看渠道的书里可能完全不存在。
