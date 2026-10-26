# CSS 属性对照工具（引擎 vs 浏览器）

目标：逐条 CSS 属性对比「引擎渲染」与「Chromium 渲染」，把差异收敛到接近浏览器。
当前 45 组用例，覆盖文字、盒模型、背景、列表、表格、多列、书写模式、变换、
滤镜、浮动等属性组。

## 组成

| 文件 | 作用 |
| --- | --- |
| `cases/*.json` | 用例：`{name, tags, css, html, multipage?}`，`tags` 首个为主属性维度 |
| `render_browser.mjs` | Chrome CDP（350×800、dpr=1）渲染：截图 + 每个元素的 `getBoundingClientRect`、文本行几何、关键计算样式、表格单元格几何 |
| `../../apps/reader_mobile/test/css_parity/parity_dump_test.dart` | 引擎侧渲染：同尺寸截图 + 每页块/行/表格单元格几何与计算样式（`CSS_PARITY=1` 才跑） |
| `compare.py` | 几何/样式/单元格/视觉逐项比对，输出 `report.md`（Top 失配、维度汇总、逐用例明细）与 `side_<case>.png`（左浏览器 / 右引擎） |

## 用法

```bash
node tool/css_parity/render_browser.mjs
cd apps/reader_mobile && CSS_PARITY=1 flutter test test/css_parity/parity_dump_test.dart && cd ../..
/usr/bin/python3 tool/css_parity/compare.py            # 全部用例
/usr/bin/python3 tool/css_parity/compare.py 12-table 32-table-colspan-rowspan
```

产物在 `/tmp/css_parity/`：

- `browser_<case>.json|png`、`engine_<case>.json|png`
- `report.md`（含 Top 失配清单、按属性维度汇总、视觉差异表、逐用例明细）
- `side_<case>.png`（左浏览器 / 右引擎，仅第 1 页）

## 用例清单（45 组）

| 编号 | 用例 | 覆盖属性 |
| --- | --- | --- |
| 01 | text-basic | font-size、line-height、CJK 标点 |
| 02 | letter-word-spacing | letter-spacing、word-spacing |
| 03 | indent-align | text-indent、text-align（含 justify） |
| 04 | decoration | text-decoration（含 wavy/dotted） |
| 05 | vertical-align | vertical-align、sup/sub |
| 06 | white-space | pre / nowrap / pre-wrap |
| 07 | font-weight-style | font-weight（300/700/900）、font-style、混排字号、`<b>/<strong>` 与 `font-weight: bolder` 相对字重 |
| 08 | text-transform | uppercase/lowercase/capitalize/full-width/small-caps |
| 09 | box-model | margin/padding/border、border-radius、box-sizing |
| 10 | background | background-color、渐变简写 |
| 11 | list | list-style-type（disc/decimal/roman/alpha/square） |
| 12 | table | 表格基础、border-collapse、单元格对齐 |
| 13 | shadow-opacity | text-shadow、box-shadow、opacity、text-emphasis |
| 14 | float-overflow | float、overflow、绕排 |
| 15 | font-variant-stretch | font-variant、font-stretch、font-variant-ligatures |
| 16 | text-indent-percent | text-indent 百分比 / em / 负值 |
| 17 | text-align-last | text-align-last（center/right/justify） |
| 18 | text-justify | text-justify（inter-word/inter-character/distribute） |
| 19 | text-emphasis | 着重号样式、位置、颜色 |
| 20 | hyphens-quotes | hyphens、quotes、word-break、overflow-wrap |
| 21 | box-sizing | content-box / border-box / auto 宽 |
| 22 | min-max-size | min/max-width、min/max-height、百分比 max-width |
| 23 | percent-padding-margin | 百分比 padding/margin、负 margin |
| 24 | border-radius-corners | 两值/四值/斜杠椭圆/50% |
| 25 | border-style-all | solid/dashed/dotted/double/groove/ridge/inset/outset/hidden、四边混排 |
| 26 | background-gradient | 线性/径向/重复渐变、硬边双色 |
| 27 | background-repeat-size | repeat/no-repeat/repeat-x、size cover/contain、position |
| 28 | background-clip-origin | content-box/padding-box/border-box 裁切 |
| 29 | background-multi | 双背景层叠加 |
| 30 | list-style-position | inside/outside、list-style-image、type |
| 31 | list-nested | 三层嵌套 ul/ol、嵌套类型覆盖 |
| 32 | table-colspan-rowspan | colspan、rowspan |
| 33 | table-layout-fixed | table-layout、border-spacing、border-collapse |
| 34 | columns | column-count / column-width / column-gap / column-rule |
| 35 | writing-mode | vertical-rl / vertical-lr / horizontal-tb |
| 36 | transform | translate / scale / rotate / 组合与原点 |
| 37 | filter-opacity | blur / grayscale / sepia / opacity / 叠加 |
| 38 | float-clear | 左右浮动、clear: both、文字绕排 |
| 39 | font-size-units | px/em/%/pt/rem、line-height normal/px/% |
| 40 | text-overflow | ellipsis / clip、nowrap+overflow、overflow-wrap |
| 41 | page-break-control | page-break-before/inside（跨页，2 页） |
| 42 | multipage-flow | 12 段长文跨页（跨页，2 页） |
| 43 | multipage-table | 表格被 page-break 推到第 2 页（跨页，2 页） |
| 44 | hanging-punctuation | hanging-punctuation: allow-end（Chrome 不支持，仅记录引擎行为） |
| 45 | initial-letter | initial-letter: 3（Chrome 不支持，仅记录引擎行为） |

浏览器渲染：45/45 成功，无 skip。第 1 页截图用于视觉对照，第 2 页只导出几何。
44/45 在用例 JSON 里标 `engine_only: true`：Chrome 尚未支持这两个属性，
`compare.py` 只打印引擎块数、不计失配也不算视觉差异。

## 口径

### 几何

- 浏览器：`getBoundingClientRect` = 边框盒。文本行取文本节点 `client rects` 后
  按纵向重叠合并成「视觉行」（行内 span、上下标不另算一行），行 y/h 取面积
  最大的 run，避免上下标把行顶拉偏。
- 引擎：块顶 = 版面 y + 段前扩展；行 y 相对块顶；行宽见下。
- 块盒折算：引擎导出 `x` 是内容左缘、`h` 是内容高；`rect.w` 是
  `longestLineW`（最长行宽，仅留档，不当盒宽），`contentWidth` 是可用内容宽，
  `bboxW` 是边框盒宽（= `contentWidth` + padding + border）。`compare.py` 用
  `bboxW` 比块宽、把 `x`/`h` 补回 padding/border 折算成边框盒，行宽仍用行几何。
  引擎未知（`contentWidth` 为 Infinity，如 `pre`/`nowrap` 的无限测量）时
  `bboxW` 为 null，按「未知」跳过，不算失配。表格块同法。
- **行宽用主布局宽**：引擎导出 `LineBox.advanceWidth`（= `width + justifyExtra`，
  即绘制端实际占据宽，含 justify 均分），不是自然宽 `width`；浏览器量的是
  绘制宽。字段名仍是 `w`，值已换成 `advanceWidth`。
- 表格单元格：引擎导出 `cells: [{row, col, rect, text, lines, style}]`，坐标是
  页面绝对坐标（块顶 + 格偏移 + padding/border + vertical-align 偏移）；浏览器
  导出 `cells`（`rowIndex`/`cellIndex`/`rect`/`text`/`lines`）。配对优先级 =
  同 (行,列) 且文本一致 → 文本一致 → 放弃；逐格比 rect、文本、格内行。
- 跨页用例（`multipage: true`）：引擎分页、浏览器连续流，**只比相对关系**
  （行距、页内相邻块间距、宽度），不比绝对 y；页界断裂与「块从第 n 行续排」
  只作为说明记录，不计入失配。跨页表格只比格宽/格高与行列间距。
- 容差：块/单元格 1.5px，行宽 4px，行 y 按 `(line-height - font-size)/2 + 0.5`
  放宽（字体盒 vs 行盒差异），跨页间距 2px。

### 样式与属性维度

- 样式比对项：font-size、line-height、letter-spacing、word-spacing、text-indent、
  font-weight、text-align、white-space、text-transform、box-sizing、vertical-align。
  浏览器 computed 为 `normal` 的 line-height、以及保留百分比的值（如 `text-indent:10%`）
  跳过数值比对，由几何反映；枚举值按 kebab-case 归一后比较。
- 行内 run：多 run 块导出每段文本的字重/斜体/字号，`compare.py` 按 run 文本到
  浏览器内联元素（`<b>/<strong>/<span>/<i>/<em>`）里找同文本项再比，覆盖
  `<b>/<strong>`、`font-weight: bolder` 这类块级样式看不出来的相对字重。
- 属性维度取用例 `tags` 的首个标签，每条失配计入主维度；`report.md` 顶部按
  维度汇总失配项数、涉及用例数与代表用例，用于排优先级。
- 视觉差异 = 两页 PNG 的差异像素占比（忽略 ≤7 的量化噪声），>2% 标「显著差异」。
  背景/图片/滤镜/变换类属性不改几何，只能靠这一列和 `side_*.png` 人工核对。

### 浏览器参数

必须带 `--allow-file-access-from-files`，否则 `@font-face` 读不到本地 OTF，
会回退系统字体导致字宽不可比。

## 报告怎么读

1. **Top 失配清单（按维度）**：先看这里，失配项数最多的属性组优先处理。
2. **按属性维度汇总**：维度 → 失配项 → 涉及用例。
3. **视觉差异（像素占比）**：几何全对但像素差大的用例（背景/滤镜/分页）在这里暴露。
4. **逐用例明细**：每条失配写成「浏览器 / 引擎」两个值；表格按 `格[行,列]` 标注。

## 已发现并修掉

1. **盒类简写被 UA 长属性压制**（P9-27）：作者 `p { margin: 8px 0 }` 输给 UA
   `p { margin: 1em 0 }` 拆出的 `margin-top`，首段凭空多 9px 且段距全错。
   修法：级联阶段把 margin/padding/border/border-width/style/color 展开成长属性
   （与浏览器一致），按同一属性名比优先级。
2. **justify 行宽口径不一致**：引擎 `width` 不含 `justifyExtra`，两端对齐行
   行宽比浏览器短 10px（03 用例 340 / 350）。已按 `LineBox.advanceWidth`
   导出，03-indent-align 现在几何 0 失配（视觉差异 2.85% 仍在，见待收敛第 9 条）。
3. **box-sizing 宽度**：border-box 的宽度此前未扣 padding/border（09 用例
   引擎盒宽 281.5 / 浏览器 200）。当前 09-box-model 几何 0 失配。
4. **`<b>/<strong>` 不加粗**：`font-weight: bolder` 未解析，UA 的
   `b, strong { font-weight: bolder }` 落空，相对字重退化成 400。T2 修复后
   07 用例 `<b>/<strong>/bolder` 三处均为 700，几何与行内 run 比对 0 失配；
   对照工具新增行内 run 比对，防止回归。
5. **块宽口径混用**：此前引擎块 `w` 报「最长行宽」，与浏览器的边框盒宽比，
   `pre`/`nowrap` 被当成 2 条永久假失配。现 dump 分开导出
   `contentWidth`/`longestLineW`/`bboxW`，块宽改用 `bboxW`；06-white-space
   几何失配从 2 降到 0。

## 待收敛（按维度失配数排序，对应 2026-10-27 工作区状态）

> 数字随引擎改动变化，以 `report.md` 为准；建议归属供 Lead 分派。

1. **列表（list-style-type 101 项 / list-style-position 69 项）**
   - 首个列表项丢失 ul/ol 的 `margin-top`（11-list 引擎 y=0 / 浏览器 6），
     列表组之间也少 6px，10 项累积偏差 29px。
   - `li` 缩进写死 40px，不随 `ul { padding-left: 28px }` 变化（30 用例
     引擎 x=40 / 浏览器 28）。
   - `list-style-position: inside` 未给首行预留标记宽度（30 用例首行
     x 40 / 50，行数 2 / 4）；`list-style-image` 未生效。建议 T2。
2. **浮动与清除（float 79 项）**
   - 浮动块声明高度被忽略（14 用例 60 → 25，38 用例 56 → 25）。
   - 文字未绕排：两侧浮动时引擎行 x=0 且行宽 340，浏览器 x=98 / 行宽 153。
     建议 T2。
3. **表格（table 78 项、table-layout 36 项）**
   - 表格块 `margin-top` 丢失（12 用例表格 y 引擎 0 / 浏览器 8，单元格整体偏移）。
   - `rowspan` 未实现：32 用例引擎 10 格（跨行格重复占两行）/ 浏览器 9 格，
     第 3 行整体错位（格 C x 0 / 131）。
   - `border-spacing` 未计入（33 用例格 x 0 / 4，第二张表 y 69 / 103）。
   - 单元格行高偏大 3px（12 用例格高 33 / 30），`colspan` 列宽分配偏差
     （32 用例跨列格宽 277 / 218）。建议 T2。
4. **边框（border-style 40 项、border-radius 14 项）**
   - 块级 `height` 未生效，导致每个 div 高出 5px 并逐块累积（25 用例 h 33 / 28，
     最后一块 y 偏差 45px）。
   - `border-style: hidden` 边宽未归零（25 用例行 x 2 / 6，块宽 164 / 172）。
     建议 T2。
5. **字体度量（font-size 24 项、font-variant 4 项）**
   - 引擎默认行高因子 1.5，浏览器 `line-height: normal` 用字体度量（约 1.4），
     无显式行高的用例整体 y 漂移（39 用例 10 行累积 10px，37 用例每块 +2px）。
     是否对齐浏览器需要产品裁决（阅读器常用 1.5）。
   - `font-variant: small-caps` / `font-stretch` 未实现（15 用例行宽 255 / 244）。
     建议 T1/T3。
6. **未实现属性组（口径性缺失，建议 T3 或明确不支持）**
   - `columns`（34 用例：浏览器 2/3 列、行宽 154/98，引擎单列 350）。
   - `writing-mode`（35 用例：浏览器竖排宽 98/高 202，引擎横排 350/50）。
   - `transform`（36 用例：translate 位移、scale 缩放、rotate 包围盒全部未应用）。
   - `filter`（37 用例：blur/grayscale/sepia 无效果）。
7. **文本细节（hyphens 19 项、text-overflow 9 项、text-indent 4 项）**
   - `hyphens` / `quotes` 未实现（20 用例：浏览器 4 行、引擎 5 行；q 引用
     浏览器 2 行、引擎 1 行无引号）。
   - `text-overflow: ellipsis` 与块级 `width` 未生效（40 用例第 3/5 行行宽
     165 / 76.5、126 / 164，断行位置不同）；`nowrap` 块的 `bboxW` 为未知
     （可用宽 Infinity），块宽不参与比较。
   - 负 `text-indent` 被钳到 0（16 用例首行 x 34 / 0）。建议 T1/T3。
8. **背景与视觉（background-image 16 项、background-repeat 14 项、filter 16 项）**
   - 引擎绘制层未接图片解码器（`PagePainter.imageLookup` 为 null），
     背景图/渐变一律不绘制；渐变本身也未实现。视觉差异只能证明「未绘制」，
     不能区分解码器缺失与属性未实现。

9. **视觉残留（几何一致但像素不同，需看 `side_*.png` 人工判定）**
   - 03-indent-align 2.85%：justify 行宽已一致，差异集中在行内间隙分布
     （引擎按字距均分，Chrome 的 CJK 挤压/间隙策略不同）。
   - 17-text-align-last 5.60%、18-text-justify 5.46%：同上，属绘制期 gap 分摊。
   - 10-background 5.66%、13-shadow-opacity 3.22%：背景/阴影绘制差异。
   - 07-font-weight-style 2.19%：`<b>/<strong>/bolder` 字重已与浏览器一致
     （行内 run 比对 0 失配），残差属粗体栅格化差异。
   - 42-multipage-flow 21.73%、43-multipage-table 16.96%：分页位移导致第 1 屏
     内容不同构，属预期（见「已知对照限制」）。

## 已知对照限制

- 背景图/渐变的差异来自「dump 未注入图片解码器」，属对照工具限制；要判定
  引擎背景能力，需在 dump 里接 `imageLookup` 或改用真机截图。
- 跨页用例的 `side_*.png` 只拼第 1 页：引擎第 1 页内容与浏览器连续流第 1 屏
  不一定同构，视觉差异大是预期现象，不作为失配计数。
- 单元格配对依赖「(行,列) + 文本」：同一表格内文本完全重复的格只能按顺序配，
  极端表格需人工核对（当前用例无此情况）。
- 引擎 `nowrap`/`pre` 的 `contentWidth` 可能是 Infinity，`bboxW` 导出为 null，
  块宽按「未知」跳过；T1 改成有限宽 measure 后会自动参与比较。
- 浏览器渲染线程与引擎字体一致（同一 OTF），字宽可比；换字体需同步更新
  `render_browser.mjs` 的 `@font-face`。
- `/tmp/css_parity` 是默认输出目录，多人同时跑会互相覆盖 JSON/PNG/report。
  并行验证时给三个脚本设同一个 `CSS_PARITY_OUT`（如
  `CSS_PARITY_OUT=/tmp/css_parity_t5`），浏览器调试端口用 `CSS_PARITY_PORT`
  错开，避免抢占 9333。
