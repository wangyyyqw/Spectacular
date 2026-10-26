# 多看、掌阅与微信读书私有 CSS 属性调研

调研时间 2026-10-27。语料为 `test_corpus/real/` 下 7 本真实 EPUB。引擎状态按当次工作区快照判定，快照为 `HEAD 2daf15d` 加未提交改动（`property_aliases.dart` 等文件当时正被并行修改）。行号会漂移，实施前请复核。

本文只做调研与映射建议，不修改源码与测试。

## 1. 证据分级与来源

| 代号 | 类型 | 来源 |
| --- | --- | --- |
| E33 | 官方标准 | [EPUB 3.3 附录 E：Prefixed CSS properties](https://www.w3.org/TR/epub-33/#e-prefixed-css-properties) |
| E33-HY | 官方标准 | [-epub-hyphens](https://www.w3.org/TR/epub-33/#sec-css-prefixed-text-epub-hyphens) |
| E33-LB | 官方标准 | [-epub-line-break](https://www.w3.org/TR/epub-33/#sec-css-prefixed-text-epub-line-break) |
| E33-AL | 官方标准 | [-epub-text-align-last](https://www.w3.org/TR/epub-33/#sec-css-prefixed-text-epub-text-align-last) |
| E33-WB | 官方标准 | [-epub-word-break](https://www.w3.org/TR/epub-33/#sec-css-prefixed-text-epub-word-break) |
| E33-WM | 官方标准 | [E.1 CSS writing modes](https://www.w3.org/TR/epub-33/#e-1-css-writing-modes) |
| E33-TD | 官方标准 | [E.3 CSS text decoration level 3](https://www.w3.org/TR/epub-33/#e-3-css-text-decoration-level-3) |
| DK-README | 社区提取 | [Eninix/sigil-template README](https://github.com/Eninix/sigil-template/blob/master/README.md)，作者提取多看 EPUB 的 CSS 并逐项说明 |
| DK-CSS | 社区提取 | [Eninix/sigil-template duokanstyle.css](https://github.com/Eninix/sigil-template/blob/master/duokanstyle.css)，声称是多看 EPUB 原样式表 |
| RD | 第三方实现 | [Readest style.ts](https://github.com/readest/readest/blob/main/apps/readest-app/src/utils/style.ts)，实现了 `duokan-bleed` 到负外边距的转换 |
| FX | 第三方修复器 | [SamLaio/epubCssFixer](https://github.com/SamLaio/epubCssFixer)，其 [css.js](https://github.com/SamLaio/epubCssFixer/blob/main/src/css.js) 列出了一批私有属性名单 |
| SX | 第三方清洗工具 | [SeptimusX/ebook-xhtml-clean SKILL.md](https://github.com/SeptimusX/ebook-xhtml-clean/blob/main/SKILL.md)，记录了多看、掌阅、微信读书的 HTML 与类名约定 |
| MDN | 标准参考 | [writing-mode](https://developer.mozilla.org/en-US/docs/Web/CSS/writing-mode)、[text-orientation](https://developer.mozilla.org/en-US/docs/Web/CSS/text-orientation)、[text-emphasis](https://developer.mozilla.org/en-US/docs/Web/CSS/text-emphasis)、[line-break](https://developer.mozilla.org/en-US/docs/Web/CSS/line-break)、[hyphens](https://developer.mozilla.org/en-US/docs/Web/CSS/hyphens)、[text-combine-upright](https://developer.mozilla.org/en-US/docs/Web/CSS/text-combine-upright) |
| BOOK | 书内位置 | 写法为 `书名 + CSS 文件 + 行号`。两本多看渠道书的 CSS 文件名被混淆成 `_*:*...`，完整名见附录 A |

没有找到多看公开的 CSS 规范文档，因此多看私有属性只有三类证据：社区从多看 EPUB 提取的样式表、真实书里的声明与作者注释、第三方阅读器的兼容代码。三者的可靠性依次下降，本文在表中标注来源，不把二手材料写成官方规范。

## 2. 属性总表

状态图例。✅ 完整生效。⚠️ 部分生效。🟡 只加了别名，目标属性没有消费点。❌ 未处理。状态以第 6 节的引擎快照为准。

### 2.1 多看私有属性

| 属性 | 来源 | 语义 | 取值 | 标准映射 | 引擎状态 | 风险 |
| --- | --- | --- | --- | --- | --- | --- |
| `duokan-text-indent` | DK-README；BOOK zhushen L169 等 1527 处 | 首行缩进 | `0em` 1368 次、`0` 140 次、`2em` 17 次、`5em 2em` 2 次 | `text-indent` | ✅ | `5em 2em` 不是合法标准值，引擎忽略该声明；书内通常同时写 `text-indent` 兜底 |
| `duokan-paragraph-align` | BOOK zhushen L5740、L5783；cloverfield L5620、L5663 | 段落对齐 | `center` 3 次、`end` 3 次 | `text-align` | ✅ | 与 `text-align` 落到同一属性，级联顺序决定胜负 |
| `duokan-text-align` | BOOK zhushen L5701；cloverfield L5581 | 多看 7.3 文本对齐 | `justify` 3 次 | `text-align` | ✅ | 同属性三名并存，`duokan-text-align` 覆盖前两者 |
| `duokan-line-height` | BOOK zhushen L5757 | 行高 | `2`（3 次，倍数） | `line-height` | ✅ | 纯数字按倍数解析，与标准一致 |
| `duokan-letter-spacing` | BOOK zhushen L5755 | 字距 | `0.2em`（3 次） | `letter-spacing` | ✅ | 无 |
| `duokan-text-color` | BOOK zhushen L3495；cloverfield L3410 | 文字颜色，作者注为多看 7.0+ | `#d4af37`（带前缀共 6 次） | `color` | ✅ | 与 `-duokan-text-color` 双写，值相同，无冲突 |
| `duokan-text-fill` | BOOK zhushen L3499；cloverfield L3414 | 文字填充色，作者注为多看 7.0+ | `#d4af37`（带前缀共 6 次）；渐变写法无多看侧证据 | `color`，遇到渐变取第一个色标 | ⚠️ | 若书里写渐变，会退化成纯色；语料未出现渐变，无法用真实书验收 |
| `duokan-bleed` | RD L1312；FX；BOOK mj-003 L1102、L1231、L1296；shiji L391 | 背景与边框出血到页面边缘 | `lefttopright` 67 次、`right` 10 次、`leftright` 4 次 | 负外边距或版心外绘制 | ⚠️ | 上、下出血已解析但未应用；分页层只消费 `bleedLeft` 与 `bleedRight` |
| `duokan-break-inside` | BOOK zhushen L15114、L15270 | 块内禁止分页 | `avoid`（4 次） | `break-inside: avoid` | ✅ | 与 `page-break-inside` 双写；两者同义，取先命中者 |
| `duokan-margin-before` | BOOK zhushen L5767 | 段前距 | `0.5em`（3 次） | `margin-top` | ✅ | 中文段前距按上边距近似，可接受 |
| `duokan-margin-after` | BOOK zhushen L5765 | 段后距 | `0.5em`（3 次） | `margin-bottom` | ✅ | 同上 |
| `duokan-writing-mode` | BOOK zhushen L5692；cloverfield L5572 | 竖排 | `vertical-rl`（3 次） | `writing-mode` | 🟡 | 目标属性在引擎中没有字段与消费点，整章竖排不生效 |
| `duokan-writing-orientation` | BOOK zhushen L5697，作者注为多看 7.3 专属 | 竖排方向 | `vertical`（3 次） | `writing-mode`，值需规整成 `vertical-rl` | 🟡 | 值 `vertical` 不是标准关键字；即使有字段也要先归一化 |
| `duokan-text-orientation` | BOOK zhushen L5694，作者注为多看 7.3 专属 | 竖排文字朝向 | `upright`（3 次） | `text-orientation` | 🟡 | 不能并入 `writing-mode`，否则 `upright` 会把竖排改回横排 |
| `duokan-block-progression` | BOOK zhushen L5699，作者注为多看 7.3 专属 | 块级进纸方向 | `rl`（3 次） | `writing-mode` 的块方向 | 🟡 | `rl` 需要和书写模式联合解释，不能单独当 `writing-mode` 值 |
| `vertical-align: duokan-middle-line` | DK-CSS；FX README；BOOK DK 样式表 5 处 | 多看的垂直居中值 | `duokan-middle-line` | `vertical-align: middle` | ✅ | 值级归一化已实现并有测试 |
| `duokan-drop-caps-style` | DK-CSS；DK-README | 首字下沉行数 | `duokan-two-line-caps`、`duokan-three-line-caps` | `initial-letter` 或浮动加字号 | ❌ | 未识别；书内只有 `float` 与 `font-size` 的近似写法 |
| `duokan-page-fullscreen` | DK-README；BOOK mj-003 OPF、zhushen OPF | OPF `itemref` 属性，封面或插图整页显示 | 无值（2 本书各 1 处） | 全屏页布局 | ❌ | OPF 解析只保留 manifest 的 `properties`，没有保留 spine itemref 的 `properties` |
| `duokan-page-fitwindow` | DK-README | OPF 属性，插图上下居中 | 无值 | 图片页垂直居中 | ❌ | 同上 |
| `duokan-page-fullscreen-spread-left/right` | DK-README | OPF 属性，全屏跨页的左右页 | 无值 | 跨页布局 | ❌ | 同上，且与双页模式绑定 |

### 2.2 标准前缀与掌阅、QQ 阅读私有属性

| 属性 | 来源 | 语义 | 取值 | 标准映射 | 引擎状态 | 风险 |
| --- | --- | --- | --- | --- | --- | --- |
| `-epub-writing-mode` | E33-WM | EPUB 3 的竖排前缀 | `horizontal-tb`、`vertical-rl`、`vertical-lr` | `writing-mode` | 🟡 | 同 `duokan-writing-mode`，别名存在但没有消费点 |
| `-epub-text-orientation` | E33-WM | 文字朝向 | `mixed`、`upright`、`sideways`，兼容 `vertical-right` 等旧值 | `text-orientation` | 🟡 | 目标属性零消费；旧值需要映射 |
| `-epub-text-combine` | E33-WM；BOOK ludingji L369 | 縦中横的旧前缀 | `horizontal`（书内 1 次）；规范值 `none`、`horizontal` | `text-combine-upright` | 🟡 | 目标属性零消费，竖排数字不会并排 |
| `-epub-text-combine-horizontal` | E33-WM | 縦中横的另一个旧前缀 | `none`、`all` | `text-combine-upright` | ❌ | 别名表里没有这一条，连名义支持都没有 |
| `-epub-hyphens` | E33-HY；BOOK ludingji L43 | 西文断字 | `auto`（书内 1 次）；规范值 `none`、`manual`、`auto` | `hyphens` | 🟡 | 目标属性零消费，长西文词会产生大空隙 |
| `-epub-line-break` | E33-LB | 断行严格度 | `auto`、`loose`、`normal`、`strict` | `line-break` | ❌ | 别名表里没有，目标属性也没有消费点 |
| `-epub-text-align-last` | E33-AL | 末行对齐 | `auto`、`start`、`end`、`left`、`right`、`center`、`justify` | `text-align-last` | ❌ | 别名表里没有；目标属性本身已支持，补别名即可生效 |
| `-epub-word-break` | E33-WB | 断词策略 | `normal`、`keep-all`、`break-all` | `word-break` | ❌ | 别名与目标属性都缺 |
| `-epub-text-emphasis-style` | E33-TD | 着重号样式 | `filled`、`open` 加 `dot`、`circle`、`sesame` 等 | `text-emphasis-style` | ✅ | 别名已加，渲染端有着重号绘制，但缺真实书与回归测试 |
| `-epub-text-emphasis-color` | E33-TD | 着重号颜色 | 颜色值 | `text-emphasis-color` | ✅ | 同上 |
| `-epub-text-emphasis-position` | E33-TD | 着重号位置 | `over`、`under` 与 `left`、`right` 组合 | `text-emphasis-position` | ✅ | 同上 |
| `-epub-text-underline-position` | E33-TD | 下划线位置 | `auto`、`under`、`left`、`right` | `text-underline-position` | ❌ | 目标属性没有字段 |
| `-webkit-writing-mode` | BOOK ludingji L39、L44；zhushen 里还有漏写前导横线的 `webkit-writing-mode` 3 处 | WebKit 竖排旧写法 | `vertical-rl` 3 次；鹿鼎记 2 条为空值 | `writing-mode` | 🟡 | 空值声明会被解析层丢弃；漏写横线的变体靠别名表兜住 |
| `-webkit-margin-start` | BOOK ludingji L305 | 逻辑起始外边距 | `2em`（1 次） | `margin-left` | ✅ | 中文横排 LTR 下近似成立；右到左排版会错边 |
| `-webkit-text-combine` | BOOK ludingji L371 | WebKit 縦中横 | `horizontal`（1 次） | `text-combine-upright` | 🟡 | 目标属性零消费 |
| `-ms-text-combine-horizontal` | BOOK ludingji L370 | IE 縦中横 | `all`（1 次） | `text-combine-upright` | 🟡 | 目标属性零消费 |
| `-webkit-font-smoothing` | BOOK zhushen L13883 | 字体抗锯齿 | `antialiased`（2 次） | 无标准等价物 | ❌ | 可安全忽略，不影响版式 |
| `-ms-overflow-style` | BOOK monk-and-robot reset.css L30 | 隐藏滚动条 | `none`（1 次） | `scrollbar-width: none` | ❌ | 滚动条可能出现在代码块里，影响小 |
| `zybleed` | FX css.js L3 | 掌阅的出血属性 | 方向关键字（未在语料出现） | 同 `duokan-bleed` | ❌ | 只有第三方修复器的名单证据，没有掌阅书样本 |
| `qrbleed` | FX css.js L3 | QQ 阅读的出血属性 | 方向关键字（未在语料出现） | 同 `duokan-bleed` | ❌ | 同上 |
| `qrfullpage` | FX css.js L3 | QQ 阅读的整页标记 | 无值 | 全屏页 | ❌ | 同上 |

## 3. 任务点名但证据不足的属性

下面这些属性在任务清单里被点名，但在 7 本真实书、Eninix 提取的多看样式表、Reeden 反编译字符串、Readest 与 epubCssFixer 中都没有找到实例或说明。它们不应按「已知多看规范」实现。

| 属性 | 现有线索 | 引擎状态 | 结论 |
| --- | --- | --- | --- |
| `duokan-text-emphasis` | 只在别名层出现 | 🟡 映射到 `text-emphasis` | 语义可按标准 `text-emphasis` 推断，但缺多看侧证据；先补测试，不急改渲染 |
| `duokan-text-emphasis-style` | 同上 | 🟡 | 同上 |
| `duokan-text-emphasis-color` | 同上 | 🟡 | 同上 |
| `duokan-text-emphasis-position` | 同上 | 🟡 | 同上 |
| `duokan-line-break` | 只在别名层出现 | 🟡 映射到 `line-break` | 语义可按 `-epub-line-break` 推断；没有书内实例，优先级低于 `-epub-line-break` |
| `duokan-page-break-before` | 别名层已有 | ✅ 映射到 `page-break-before` | 语义与标准一致，但多看是否真的写过没有证据；保留别名即可 |
| `duokan-page-break-after` | 别名层已有 | ✅ | 同上 |
| `duokan-page-break-inside` | 别名层已有 | ✅ | 同上，书内实际写的是 `duokan-break-inside` |
| `duokan-hyphenate` | 无 | ❌ | 未证实存在，暂不建议实现；西文断字应先支持 `-epub-hyphens` |
| `duokan-text-justify` | 无 | ❌ | 未证实存在，暂不建议实现；书内两端对齐用 `duokan-text-align: justify` |
| `duokan-text-decoration-width` | 仅 Reeden 反编译字符串 | ❌ | 第三方字符串不能证明多看支持；先观察 |
| `duokan-text-decoration-color` | 仅 Reeden 反编译字符串 | ❌ | 同上 |

## 4. 书内真实用法片段

CSS 文件行号来自解压后的原始文件。两本多看渠道书的文件名被混淆，见附录 A。

### 4.1 缩进、对齐、行距、字距

`test_corpus/real/agatha-linear-no.epub!OEBPS/Styles/style0001.css`：

```css
p.copyright-text {
    margin: 2em;
    text-indent: 0em;
    duokan-text-indent: 0em;
}
```

`test_corpus/real/zhushen-yuxi.epub!主样式表` L5745 到 L5770：

```css
.poem-content {
  font-family: "宋体", "SimSun", "STSong", serif;
  font-size: 1.2em;
  line-height: 2;
  color: #333333;
  duokan-letter-spacing: 0.2em;
  duokan-line-height: 2;
}

.poem-line {
  margin: 0 0.5em;
  duokan-margin-after: 0.5em;
  duokan-margin-before: 0.5em;
}
```

`test_corpus/real/mj-003.epub!OEBPS/Styles/main.css` L365 到 L369：

```css
p.InformationpA4 {
    margin: 1em 0em 0.4em -1em;
    text-indent: 2em;
    duokan-text-indent: 5em 2em;
    font-family: "cc", "楷体", serif;
    font-size: 90%;
}
```

`5em 2em` 在标准 `text-indent` 里非法，浏览器与当前引擎都会丢这条声明，后面的 `text-indent: 2em` 继续生效。

### 4.2 颜色与填充

`test_corpus/real/zhushen-yuxi.epub!主样式表` L3479 到 L3501：

```css
.chinese-title-duokan {
  font-family: "jj", "DK-Hei", "黑体", "SimHei", sans-serif;
  font-size: 2em;
  font-weight: bold;
  color: #ecd6a8;
  margin: 0.2em 0;
  letter-spacing: 0.1em;
  /* 多看专属文本颜色属性 - 确保金色在多看阅读器中显示 */
  -duokan-text-color: #d4af37;
  /* 多看老版本专属文本颜色 */
  duokan-text-color: #d4af37;
  /* 多看7.0+版本文本颜色 */
  -duokan-text-fill: #d4af37;
  /* 多看专属文本填充色 */
  duokan-text-fill: #d4af37;
  /* 多看7.0+版本文本填充色 */
}
```

`test_corpus/real/cloverfield-multi-author.epub!主样式表` L3394 起是同一段模板：

```css
.chinese-title-duokan {
  font-family: "jj", "DK-Hei", "黑体", "SimHei", sans-serif;
  font-size: 2em;
  font-weight: bold;
  color: #ecd6a8;
  margin: 0.2em 0;
  letter-spacing: 0.1em;
  -duokan-text-color: #d4af37;  /* 多看老版本专属文本颜色 */
  duokan-text-color: #d4af37;   /* 多看7.0+版本文本颜色 */
  -duokan-text-fill: #d4af37;   /* 多看专属文本填充色 */
  duokan-text-fill: #d4af37;    /* 多看7.0+版本文本填充色 */
}
```

### 4.3 出血

`test_corpus/real/mj-003.epub!OEBPS/Styles/main.css` L1098 到 L1103：

```css
div.fmdC2 {
    text-align: center;
    text-indent: 0em;
    duokan-text-indent: 0em;
    duokan-bleed: lefttopright;  /*多看贴边贴顶代码*/
}
```

同一文件 L1225 到 L1232：

```css
div.fmdF1 {  /*外圈*/
    padding: 5px;
    border: 1px solid rgba(220, 20, 60, 0.9);
    border-width: 3px 0px 3px 3px;
    vertical-align: middle;
    margin: 30% -10px 0px 25%;
    duokan-bleed: right;  /*多看贴边贴顶代码*/
    border-radius: 10px 0px 0px 10px;
}
```

`test_corpus/real/shiji-yuewei.epub!OEBPS/Styles/stylesheets.css` L384 到 L392：

```css
.logo {
  text-align: right;
  text-indent: 0em;
  duokan-text-indent: 0em;
  margin: 0em 0 -5% 0;
  margin-left: auto;
  page-break-before: always;
  duokan-bleed: lefttopright;
}
```

### 4.4 分页与断页

`test_corpus/real/zhushen-yuxi.epub!主样式表` L15105 起：

```css
div.multi-card {
  margin: 0 0 16px 0;
  padding: 12px;
  background-color: rgba(19, 18, 29, 0.8);
  border: 1px solid #2d2638;
  border-left: 4px solid #a87bc7;
  text-indent: 0;
  duokan-text-indent: 0;
  page-break-inside: avoid;
  duokan-break-inside: avoid;
}
```

同一文件 L15261 起的 `div.orig-card` 是同一套写法的第二例：

```css
div.orig-card {
  margin: 0 0 16px 0;
  padding: 12px;
  background-color: rgba(16, 14, 17, 0.8);
  border: 1px solid #3d2b1f;
  border-left: 4px solid #d4af37;
  text-indent: 0;
  duokan-text-indent: 0;
  page-break-inside: avoid;
  duokan-break-inside: avoid;
}
```

### 4.5 竖排族

`test_corpus/real/zhushen-yuxi.epub!主样式表` L5684 到 L5723：

```css
/* 竖排诗词 - 7.3版本兼容修正 */
.vertical-poem {
  webkit-writing-mode: vertical-rl;      /* WebKit竖排，漏写前导横线 */
  writing-mode: vertical-rl;             /* 标准竖排 */
  duokan-writing-mode: vertical-rl;      /* 多看专属竖排 */
  duokan-text-orientation: upright;      /* 文字直立显示 */
  duokan-writing-orientation: vertical;  /* 多看7.3专属属性 */
  duokan-block-progression: rl;          /* 多看7.3块级进展方向 */
  duokan-text-align: justify;            /* 多看7.3文本对齐 */
  display: inline-block;
  max-height: 400px;
  overflow: auto;
  margin: 2em auto;
  padding: 1.5em 1em;
  background-color: #f9f5e9;
  border: 1px solid #d0c8b0;
  border-radius: 8px;
  box-shadow: 2px 2px 10px rgba(0, 0, 0, 0.1);
}
```

`test_corpus/real/cloverfield-multi-author.epub!主样式表` L5565 起是同一段模板：

```css
.vertical-poem {
  webkit-writing-mode: vertical-rl;
  writing-mode: vertical-rl;
  duokan-writing-mode: vertical-rl;
  duokan-text-orientation: upright;
  duokan-writing-orientation: vertical;
  duokan-block-progression: rl;
  duokan-text-align: justify;
}
```

### 4.6 段前后距

`test_corpus/real/zhushen-yuxi.epub!主样式表` L5762 到 L5769：

```css
.poem-line {
  margin: 0 0.5em;
  duokan-margin-after: 0.5em;
  duokan-margin-before: 0.5em;
}
```

`test_corpus/real/cloverfield-multi-author.epub!主样式表` L5642 起为同一写法：

```css
.poem-line {
  margin: 0 0.5em;
  duokan-margin-after: 0.5em;
  duokan-margin-before: 0.5em;
}
```

### 4.7 OPF 全屏属性

`test_corpus/real/mj-003.epub!OEBPS/content.opf`：

```xml
<itemref idref="cover.xhtml" properties="duokan-page-fullscreen"/>
```

`test_corpus/real/zhushen-yuxi.epub!OEBPS/content.opf` 中同样有这一行：

```xml
<itemref idref="cover.xhtml" properties="duokan-page-fullscreen"/>
```

### 4.8 `-epub-` 与 WebKit 前缀

`test_corpus/real/ludingji-1.epub!stylesheet.css` L369 到 L373：

```css
.tcy {
  -epub-text-combine: horizontal;
  -ms-text-combine-horizontal: all;
  -webkit-text-combine: horizontal;
  text-combine-horizontal: all;
  text-combine-upright: all;
}
```

同一文件 L39 到 L44：

```css
.calibre {
  -webkit-writing-mode: ;
  writing-mode: ;
}
.calibre1 {
  -epub-hyphens: auto;
  -webkit-writing-mode: ;
```

空值写法是导出工具留下的残渣，浏览器会丢掉整条声明。

同一文件 L305：

```css
.footnote {
  -webkit-margin-start: 2em;
  border-bottom-width: 0;
  ...
}
```

`test_corpus/real/zhushen-yuxi.epub!主样式表` L13883：

```css
.dk-toc-wrapper {
  -webkit-font-smoothing: antialiased;
}
```

## 5. 引擎阵营与版本差异

### 5.1 多看 6.0 之后

多看没有公开的 CSS 变更日志，无法逐版本核对 6.0 引入或删除了什么。能确认的只有真实书里的作者注释，这些注释把写法分成三代。

| 代际线索 | 书内证据 | 含义 |
| --- | --- | --- |
| 老版本 | zhushen L3494 注释「多看老版本专属文本颜色」 | 用带前导横线的 `-duokan-text-color` 和 `-duokan-text-fill` |
| 7.0+ | zhushen L3496、L3500 注释 | 改成不带横线的 `duokan-text-color` 与 `duokan-text-fill` |
| 7.3 | zhushen L5684 注释「7.3版本兼容修正」，L5696 到 L5702 注释 | 新增 `duokan-writing-orientation`、`duokan-block-progression`、`duokan-text-align`，并有 `duokan-text-orientation: upright` |

这些是书籍制作者的注释，不是多看官方声明。可以据此判断「新书会同时写新旧两套」，不能据此断言 6.0 的具体变化。语料里没有 6.0 时代单独标注的 CSS，这一项保持未知。

### 5.2 掌阅 iReader

掌阅的 EPUB 导出以标准 CSS 与 WebKit 前缀为主，私有痕迹更多在 class 与 HTML 结构，而不是 CSS 属性前缀。`SX` 记录掌阅稿的类名有 `zhangyue-*`、`text-title-*`、`bodytext`、`noteref_N`，没有记录 `ireader-*` CSS 属性。第三方修复器 `FX` 把 `zybleed` 视作与 `duokan-bleed` 同类的私有出血属性，这是目前能找到的唯一 CSS 私有属性证据，且只有一份低星工具名单，可靠性低。

### 5.3 微信读书与 QQ 阅读

微信读书没有发现私有 CSS 属性前缀。`SX` 记录的特征是 HTML 私有属性 `data-wr-bd`、`data-wr-id`、`data-wr-footernote`，以及 `readerChapterContent`、`p.content`、`p.quotation` 等类名，CSS 走标准子集与内联样式。QQ 阅读与微信读书共用清洗 profile，第三方修复器只列出 `qrbleed` 与 `qrfullpage` 两个私有属性，同样缺少一手证据。

### 5.4 只有多看支持的属性

下面这些属性目前只在多看的材料里出现，掌阅与微信读书没有对应物。

- 文本类 `duokan-text-indent`、`duokan-paragraph-align`、`duokan-text-align`、`duokan-text-fill`、`duokan-text-color`、`duokan-line-height`、`duokan-letter-spacing`
- 间距类 `duokan-margin-before`、`duokan-margin-after`
- 竖排类 `duokan-writing-mode`、`duokan-writing-orientation`、`duokan-text-orientation`、`duokan-block-progression`
- 特殊排版 `duokan-middle-line`、`duokan-drop-caps-style`
- 出血 `duokan-bleed`（掌阅与 QQ 有同类 `zybleed`、`qrbleed`，前缀不同，语义相近）
- OPF 页属性 `duokan-page-fullscreen`、`duokan-page-fitwindow`、`duokan-page-fullscreen-spread-left/right`

`-epub-*` 属于 EPUB 3 标准前缀，`-webkit-*` 属于 WebKit 遗留，`page-break-*` 属于标准旧属性，都不能算多看独有。

### 5.5 阵营对照

| 能力 | 多看 | 掌阅 | 微信读书 | QQ 阅读 |
| --- | --- | --- | --- | --- |
| 私有 CSS 前缀 | `duokan-*` 与 `-duokan-*` | `zybleed`（仅出血） | 未发现 | `qrbleed`、`qrfullpage` |
| 出血 | `duokan-bleed` | `zybleed` | 未发现 | `qrbleed` |
| 整页插图 | OPF `duokan-page-fullscreen` 等 | 未发现 | 未发现 | `qrfullpage` |
| 竖排 | `duokan-writing-mode` 族 | 标准 `writing-mode` 子集 | 标准 CSS 子集 | 未发现 |
| 着重号 | `-epub-text-emphasis-*` 与标准 | 未发现 | 未发现 | 未发现 |

与 6.0 之后的多看相比，掌阅与微信读书的私有 CSS 面窄得多。多看把文本、竖排、出血、整页插图都做成了私有属性，掌阅目前只找到出血一个私有属性，微信读书没有私有 CSS 前缀，主要靠 HTML 属性与类名控制排版。

## 6. 引擎现状统计

### 6.1 快照

- 仓库 `HEAD` 为 `2daf15d`，工作区有未提交改动，`property_aliases.dart` 与 `computed_style.dart` 在调研期间被并行修改。
- 别名表当时有 48 条映射，文件为 [`property_aliases.dart`](../packages/reader_core/lib/css/property_aliases.dart)。
- 解析入口在 [`parser.dart`](../packages/reader_core/lib/css/parser.dart) 调用 `CssPropertyAliases.resolve`，层叠与计算在 [`computed_style.dart`](../packages/reader_core/lib/css/computed_style.dart)。
- `duokan-line-break`、`duokan-text-emphasis*`、`-epub-text-emphasis-*`、`-webkit-*` 等别名是工作区里的未提交改动，`HEAD` 版本没有这些条目。本文按工作区判定，提交前需用 `git show HEAD:packages/reader_core/lib/css/property_aliases.dart` 复核。

### 6.2 声明级统计

7 本书共 1670 条私有属性声明。按当前工作区引擎的行为分类。

| 结果 | 声明数 | 占比 | 主要来源 |
| --- | --- | --- | --- |
| 完整生效 | 1565 | 93.7% | `duokan-text-indent` 1527、`duokan-paragraph-align`、`duokan-break-inside`、`duokan-text-color/fill`、`duokan-line-height`、`duokan-letter-spacing`、`duokan-margin-*`、`-webkit-margin-start` |
| 部分生效 | 81 | 4.85% | `duokan-bleed`，左右生效，上下未应用 |
| 只加别名、无消费 | 19 | 1.14% | 竖排族 17 条与 `-epub-hyphens`、`-epub-text-combine`、`-webkit-text-combine`、`-ms-text-combine-horizontal` |
| 空值被丢弃 | 2 | 0.12% | 鹿鼎记的 `-webkit-writing-mode: ;` |
| 忽略 | 3 | 0.18% | `-webkit-font-smoothing` 2、`-ms-overflow-style` 1 |

完整生效里包含 6 条纯色 `duokan-text-fill`，渐变能力另算。另有 2 条 `duokan-text-indent: 5em 2em` 计在完整生效里，但值本身非法，实际不起作用。

按书分布。

| 书 | 私有声明数 | 其中多看属性 | 备注 |
| --- | --- | --- | --- |
| zhushen-yuxi | 1070 | 1066 | 竖排模板、诗词、卡片、全屏封面 |
| cloverfield-multi-author | 441 | 440 | 与 zhushen 共用的模板 |
| agatha-linear-no | 87 | 87 | 每章一个 CSS，只有缩进 |
| mj-003 | 62 | 62 | 封面出血、全屏封面 |
| shiji-yuewei | 2 | 2 | 单个出血规则 |
| ludingji-1 | 7 | 0 | `-epub-*` 与 WebKit 前缀 |
| monk-and-robot | 1 | 0 | `-ms-overflow-style` |

### 6.3 属性级状态

书内实际出现的私有属性与支持情况。

| 书内属性 | 出现次数 | 引擎状态 |
| --- | --- | --- |
| `duokan-text-indent` | 1527 | ✅ |
| `duokan-bleed` | 81 | ⚠️ 仅左右 |
| `duokan-paragraph-align` | 6 | ✅ |
| `duokan-break-inside` | 4 | ✅ |
| `duokan-text-color` 与 `-duokan-text-color` | 6 | ✅ |
| `duokan-text-fill` 与 `-duokan-text-fill` | 6 | ✅ 纯色，渐变不支持 |
| `duokan-line-height` | 3 | ✅ |
| `duokan-letter-spacing` | 3 | ✅ |
| `duokan-margin-before` | 3 | ✅ |
| `duokan-margin-after` | 3 | ✅ |
| `duokan-text-align` | 3 | ✅ |
| `duokan-writing-mode` | 3 | 🟡 |
| `duokan-writing-orientation` | 3 | 🟡 |
| `duokan-text-orientation` | 3 | 🟡 |
| `duokan-block-progression` | 3 | 🟡 |
| `webkit-writing-mode`（漏写前导横线） | 3 | 🟡 |
| `-webkit-writing-mode`（空值） | 2 | 解析层丢弃 |
| `-webkit-margin-start` | 1 | ✅ |
| `-epub-hyphens` | 1 | 🟡 |
| `-epub-text-combine` | 1 | 🟡 |
| `-webkit-text-combine` | 1 | 🟡 |
| `-ms-text-combine-horizontal` | 1 | 🟡 |
| `-webkit-font-smoothing` | 2 | ❌ 可忽略 |
| `-ms-overflow-style` | 1 | ❌ 可忽略 |
| 合计 | 1670 | 完整生效 1565、部分生效 81、别名空转 19、空值丢弃 2、忽略 3 |

- 真正生效的多看属性有 10 组：`duokan-text-indent`、`duokan-paragraph-align`、`duokan-text-align`、`duokan-line-height`、`duokan-letter-spacing`、`duokan-text-color`、`duokan-text-fill`（纯色）、`duokan-bleed`（左右）、`duokan-break-inside`、`duokan-margin-before/after`。
- 名义支持、实际不生效的有 6 个：`duokan-writing-mode`、`duokan-writing-orientation`、`duokan-text-orientation`、`duokan-block-progression`、`duokan-line-break`、`-epub-hyphens`。它们都映射到了没有字段或没有消费点的标准属性。
- 完全没处理的有 `duokan-drop-caps-style`、`duokan-page-fullscreen`、`duokan-page-fitwindow`、`duokan-page-fullscreen-spread-*`、`zybleed`、`qrbleed`、`qrfullpage`。

### 6.4 伪支持风险

[`docs/css-property-audit.md`](css-property-audit.md) 已经指出同一问题。别名把私有属性改名成标准属性，但标准属性本身零消费时，覆盖率看起来提高，排版没有任何变化，排查「为什么竖排不生效」时还会先怀疑别名层。竖排族就是典型。

`duokan-text-orientation: upright` 必须映射到 `text-orientation`，不能并入 `writing-mode`。真实书里这两条声明紧挨着，同特异性下后写的 `upright` 会把 `writing-mode: vertical-rl` 覆盖成非法值，最终整章从竖排退回横排。当前工作区已经分开映射，后续重构不能合并。

## 7. 建议实现顺序 Top 10

排序依据是真实书影响面、当前失效程度、实现依赖，不是「属性看起来重要」。

| 顺序 | 事项 | 影响面 | 依赖 | 改动位置 | 验收 |
| --- | --- | --- | --- | --- | --- |
| 1 | 竖排族落地，`writing-mode`、`text-orientation`、`block-progression` 统一建模 | 2 本书 17 条声明，`.vertical-poem` 整块失效 | 无 | `computed_style.dart` 新字段、`cascade.dart` 继承、`layout/line_breaker.dart`、`paint/page_renderer.dart` | zhushen 竖排诗词按 `vertical-rl` 排；`upright` 不反覆盖方向 |
| 2 | `duokan-bleed` 补齐上下出血 | 81 条声明，多数 `lefttopright`，目前顶部与底部不出血 | 1 可选 | [`paginator.dart`](../packages/reader_core/lib/layout/paginator.dart)、[`page_renderer.dart`](../packages/reader_core/lib/paint/page_renderer.dart) | mj-003 封面、shiji 页眉图顶到页边 |
| 3 | `duokan-text-fill` 渐变兜底 | 6 条声明，当前纯色可用；渐变写法无多看侧证据，属于防御性支持 | 无 | `computed_style.dart` 存填充模型、`page_renderer.dart` 用着色器或渐变绘制 | 合成用例 `linear-gradient` 渲染出渐变，纯色仍正确 |
| 4 | `line-break` 与 `-epub-line-break` 真正消费 | 无真实书实例，但多看排版常用；决定标点禁则严格度 | 1 | `property_aliases.dart` 补 `-epub-line-break`、`computed_style.dart`、`layout/line_breaker.dart` | 长标点序列断行点与 Chrome 对齐 |
| 5 | `text-emphasis` 全家族补测试与值兼容 | 别名已加，渲染端已有着重号；缺真实书验证 | 无 | `private_properties_test.dart`、必要时 `computed_style.dart` 值解析 | `filled sesame`、`open dot`、位置与颜色用例通过 |
| 6 | `page-break-*` 与 `break-inside` 统一收口 | 书内 4 条 `duokan-break-inside`，模板大量 `page-break-before: always` | 无 | `computed_style.dart`、分页器 | `duokan-break-inside` 与 `break-inside` 同结果；前后分页不重复触发 |
| 7 | `text-combine-upright` 縦中横 | 鹿鼎记 4 条，竖排年份与数字需要 | 1 | `computed_style.dart`、`page_renderer.dart` | `.tcy` 数字横排并占一格 |
| 8 | OPF `duokan-page-fullscreen`、`fitwindow`、`spread-*` | 2 本书的封面，真实可见 | 无 | [`models.dart`](../packages/reader_core/lib/src/api/models.dart) 给 `SpineItem` 加 `properties`，[`opf.dart`](../packages/reader_core/lib/epub/opf.dart) 解析 `itemref` 时传入，渲染层识别全屏页 | 封面整页无页边距；插图页上下居中 |
| 9 | `duokan-drop-caps-style` | 多看模板中的首字下沉 | 1 可选 | `computed_style.dart` 映射到 `initial-letter` 或浮动参数 | 两行、三行首字下沉与多看模板一致 |
| 10 | 掌阅与 QQ 出血别名 | 语料无样本，属于前瞻兼容 | 2 | `property_aliases.dart` 把 `zybleed`、`qrbleed` 映射到同一出血模型；`qrfullpage` 单独处理 | 合成用例生效；真实掌阅书待补样本 |

暂不建议实现 `duokan-hyphenate`、`duokan-text-justify`、`duokan-text-decoration-width/color`，理由见第 3 节。西文断字应先做 `-epub-hyphens`，它至少有官方规范和鹿鼎记实例。

## 8. 需要改的文件（建议，未实际修改）

| 文件 | 建议改动 |
| --- | --- |
| [`packages/reader_core/lib/css/property_aliases.dart`](../packages/reader_core/lib/css/property_aliases.dart) | 补 `-epub-line-break`、`-epub-text-align-last`、`-epub-word-break`、`-epub-text-underline-position`；补 `-epub-text-combine-horizontal`；评估 `zybleed`、`qrbleed`、`qrfullpage`；保持 `text-orientation` 与 `writing-mode` 分开 |
| [`packages/reader_core/lib/css/computed_style.dart`](../packages/reader_core/lib/css/computed_style.dart) | 新增 `writingMode`、`textOrientation`、`lineBreak`、`hyphens`、`wordBreak`、`textCombineUpright` 字段与解析；`textFill` 从单色升级为填充模型；`CssBleed.top/bottom` 接进盒模型 |
| [`packages/reader_core/lib/css/cascade.dart`](../packages/reader_core/lib/css/cascade.dart) | 为新增字段补继承表；`writing-mode`、`text-orientation`、`line-break`、`hyphens` 都是可继承属性 |
| [`packages/reader_core/lib/layout/line_breaker.dart`](../packages/reader_core/lib/layout/line_breaker.dart) | 消费 `line-break` 与 `hyphens`；竖排下的行内推进 |
| [`packages/reader_core/lib/layout/paginator.dart`](../packages/reader_core/lib/layout/paginator.dart) | 出血从左右扩展到上下；全屏页分页 |
| [`packages/reader_core/lib/paint/page_renderer.dart`](../packages/reader_core/lib/paint/page_renderer.dart) | 竖排绘制、渐变文字、上下出血、首字下沉、縦中横 |
| [`packages/reader_core/lib/src/api/models.dart`](../packages/reader_core/lib/src/api/models.dart) | 给 `SpineItem` 增加 `properties` 字段 |
| [`packages/reader_core/lib/epub/opf.dart`](../packages/reader_core/lib/epub/opf.dart) | 解析 `itemref` 时保留 `duokan-page-*`，传入 `SpineItem`；与 manifest 属性区分 |
| [`packages/reader_core/test/css/private_properties_test.dart`](../packages/reader_core/test/css/private_properties_test.dart) | 补竖排族、`duokan-line-break`、`-epub-*`、`duokan-text-fill` 渐变、`duokan-break-inside` 用例 |
| [`tool/css_parity/cases/`](../tool/css_parity/cases) | 新增或扩展真实书片段，与 Chrome 对照；竖排、出血、渐变各一组 |

## 9. 风险与未决问题

1. 多看没有公开规范。Eninix 的样式表是社区提取，无法证明覆盖全部多看属性；本文的「多看语义」有一部分来自标准属性的类比。
2. 版本差异只有书中注释作为二手证据。6.0 的具体变化无法验证，7.0 与 7.3 的结论也只来自《诸神愚戏》与《克洛弗菲尔德》两本模板书。
3. 语料只有 7 本，5 本含多看属性。`duokan-text-emphasis*`、`duokan-page-break-*`、`duokan-line-break` 在语料中零出现，不能用「已支持」对外宣称。
4. 伪支持面已经存在。竖排族、断行、断字、縦中横的别名目标都没有消费点，覆盖率数字会误导。
5. 上、下出血已解析但未应用，`lefttopright` 只兑现了左右两侧。
6. OPF 的 `itemref` 属性被丢弃，多看全屏封面在引擎里只能按普通封面页处理。
7. 工作区在调研期间有并行改动，本文状态与行号可能已过期。实施前应重新跑第 6 节统计并复核别名表。
8. `-webkit-writing-mode: ;` 这类空值导出残渣会被丢弃，但别名表仍认这个属性名；测试里要区分「有声明」与「有有效值」。

## 10. 附录

### A. 混淆的 CSS 文件名

两本多看渠道书的主样式表文件名长度为 146，内容为明文 CSS，文件名被替换为下面的字符串。

`zhushen-yuxi.epub`：

```text
OEBPS/Styles/_*:*:***:::*:*::::*::*****::*::::::::*****::***:*:**:***:::*::::**:***:*::**:*::*:::*:*:::*::**::******::*::*:::****::*:::::**:**.css
```

`cloverfield-multi-author.epub`：

```text
OEBPS/Styles/_*:*:***:::*:*::::*::*****::*::::::::*****::***:*:**:***:::*::::**:***:*::**:*::*:::*:*:::*::**::******::*::*:::****::*:::::**:**.css
```

### B. 复现统计

在仓库根目录执行。只读，不改仓库文件。

```bash
/usr/bin/python3 - <<'PY'
import zipfile, re, glob, collections, os
counter = collections.Counter()
for path in sorted(glob.glob('test_corpus/real/*.epub')):
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if not name.lower().endswith('.css'):
                continue
            text = z.read(name).decode('utf-8', 'ignore')
            for m in re.finditer(r'(?m)^\s*([-a-zA-Z][-a-zA-Z0-9_]*)\s*:\s*([^;{}]+)', text):
                prop = m.group(1).lower()
                base = prop[1:] if prop.startswith('-') else prop
                if re.match(r'^(duokan|epub|webkit|ms)-', base):
                    counter[prop] += 1
print(sum(counter.values()))
for prop, count in counter.most_common():
    print(f'{prop}\t{count}')
PY
```

### C. 外部来源

- EPUB 3.3 附录 E，W3C Recommendation：<https://www.w3.org/TR/epub-33/#e-prefixed-css-properties>
- 多看 EPUB CSS 模板与样式表提取，Eninix/sigil-template：<https://github.com/Eninix/sigil-template>
- Readest 的 `duokan-bleed` 转换实现：<https://github.com/readest/readest/blob/main/apps/readest-app/src/utils/style.ts>
- epubCssFixer 私有属性名单：<https://github.com/SamLaio/epubCssFixer/blob/main/src/css.js>
- 微信读书、掌阅、多看清洗约定：<https://github.com/SeptimusX/ebook-xhtml-clean/blob/main/SKILL.md>
- MDN CSS 参考：<https://developer.mozilla.org/en-US/docs/Web/CSS>
