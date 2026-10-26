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
/usr/bin/python3 tool/css_parity/compare.py --threshold 40   # 门禁：超阈值退出码 2
CSS_PARITY_THRESHOLD=40 /usr/bin/python3 tool/css_parity/compare.py  # 同上，CI 友好
```

退出码：`0` 正常（或未启用门禁）、`2` 门禁失败（任一属性维度失配项数超过
阈值，stderr 会列出超限维度）、`1` 运行异常（数据缺失等）。

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
- 配对按「文本 + 角色」：`ul/ol/dl/menu/table` 等容器元素不参与文本块配对；
  引擎列表项块（dump 的 `role=li`，无标记时兜底按文本配 `li`）只与 `li` 配对；
  表格块只与 `table` 配。配不上记「未配对」并在报告里单列，不计入失配。
- 部分配对：浏览器元素文本是引擎块文本的超集（如 `li` 里嵌 `ul`），只比块顶
  与前 `min(行数)` 行，块高/行数/宽度不可比，用例说明里会标「部分配对」。
- 失配去重：同一用例内完全相同的失配行只计一次；报告顶部的失配总数是去重后。
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
3. **未配对（不计失配）**：按不上角色的块单列在这里，先确认是工具口径还是
   引擎真缺块，不要当失配排期。
4. **视觉差异（像素占比）**：几何全对但像素差大的用例（背景/滤镜/分页）在这里暴露。
5. **逐用例明细**：每条失配写成「浏览器 / 引擎」两个值；表格按 `格[行,列]` 标注。

## 已发现并修掉

1. **盒类简写被 UA 长属性压制**（P9-27）：作者 `p { margin: 8px 0 }` 输给 UA
   `p { margin: 1em 0 }` 拆出的 `margin-top`，首段凭空多 9px 且段距全错。
   修法：级联阶段把 margin/padding/border/border-width/style/color 展开成长属性
   （与浏览器一致），按同一属性名比优先级。
2. **justify 行宽口径不一致**：引擎 `width` 不含 `justifyExtra`，两端对齐行
   行宽比浏览器短 10px（03 用例 340 / 350）。已按 `LineBox.advanceWidth`
   导出，03-indent-align 现在几何 0 失配（视觉差异 2.85% 仍在，见待收敛第 8 条）。
3. **box-sizing 宽度**：border-box 的宽度此前未扣 padding/border（09 用例
   引擎盒宽 281.5 / 浏览器 200）。当前 09-box-model 几何 0 失配。
4. **`<b>/<strong>` 不加粗**：`font-weight: bolder` 未解析，UA 的
   `b, strong { font-weight: bolder }` 落空，相对字重退化成 400。T2 修复后
   07 用例 `<b>/<strong>/bolder` 三处均为 700，几何与行内 run 比对 0 失配；
   对照工具新增行内 run 比对，防止回归。
5. **配对口径（ul/ol 抢 li）**：此前浏览器 `ul` 会与引擎 li 块配对，30-list
   因此多出 8 项块级 x/w/h/行数假差异。现按「文本 + 角色」配对，容器不参与，
   li 只对列表项块，配不上进「未配对」；30-list 几何失配 10 → 0。
6. **块宽口径混用**：此前引擎块 `w` 报「最长行宽」，与浏览器的边框盒宽比，
   `pre`/`nowrap` 被当成 2 条永久假失配。现 dump 分开导出
   `contentWidth`/`longestLineW`/`bboxW`，块宽改用 `bboxW`；06-white-space
   几何失配从 2 降到 0。

## 待收敛（45 用例全量重跑：失配 165 项 / 18 个用例 / 未配对 0）

> 数字来自 2026-10-27 02:30 全量重跑（render_browser + dump，含 T2/T4 引擎改动），
> 引擎仍在改，数字会继续下降，以 `report.md` 为准；归属建议供 Lead 分派。

| # | 属性维度 | 失配项 | 用例 |
| --- | --- | --- | --- |
| 1 | line-height | 36 | 37-filter-opacity、39-font-size-units |
| 2 | transform | 21 | 36-transform |
| 3 | column-count | 20 | 34-columns |
| 4 | hyphens | 19 | 20-hyphens-quotes |
| 5 | table | 15 | 12-table、32-table-colspan-rowspan |
| 6 | list-style-type | 14 | 31-list-nested |
| 7 | writing-mode | 10 | 35-writing-mode |
| 8 | text-overflow | 9 | 40-text-overflow |
| 9 | float | 5 | 14-float-overflow、38-float-clear |
| 10 | font-variant | 4 | 15-font-variant-stretch |

1. **默认行高口径（line-height 36 项）**：引擎默认因子 1.5，浏览器
   `line-height: normal` 用字体度量（约 1.4）；37 每块 +2px、39 十行累积 10px。
   阅读器常用 1.5，是否对齐浏览器需要产品裁决（建议 T1 + 你）。
2. **未实现属性组（transform 21 / column-count 20 / writing-mode 10 / hyphens 19）**：
   `columns`（34：浏览器 2/3 列、行宽 154/98，引擎单列 350）、`transform`（36：
   位移/缩放/旋转全未应用）、`writing-mode`（35：浏览器竖排 98×202，引擎横排
   350×50）、`hyphens`/`quotes`（20：浏览器 4 行 / 引擎 5 行；`q` 引用 2 行 /
   1 行无引号）。建议 T3 或明确不支持。
3. **嵌套列表（list-style-type 14 项）**：嵌套 ul/ol 的段前与缩进仍差 2px
   （三级方块 y 浏览器 114 / 引擎 116，一级第三项 169 / 172）；另有 3 个
   「部分配对」（li 内含子列表，只比块顶与前几行）。建议 T2。
4. **表格（table 15 项 / 2 用例 + table-layout 2 项）**：
   - 12-table 4 项：表高 93 / 91，右对齐格首行 x 差 1.7px。
   - 32-colspan/rowspan 11 项：表高 100 / 105；rowspan 之后各行整体偏移
     2.5–3px（格[2,0] 58 / 60.5、格[3,0] 83 / 86.5）。
   - 33-table-layout 2 项：表高 46 / 49（`border-spacing` 未计入）。建议 T2。
5. **text-overflow（9 项）**：块级 `width` 未生效，`white-space: normal` 段
   第 3/5 行行宽 165 / 76.5、126 / 164（断行位置不同）；`nowrap` 块的
   `bboxW` 为未知（可用宽 Infinity），块宽不参与比较。建议 T1/T3。
6. **浮动（float 5 项）**：右浮动块整体下移（14：y 166 / 160.8；38：268.7 / 267），
   其余为浮动块间距偏差。建议 T2。
7. **其余单项（每题 2–4 项）**：font-variant/ligatures 行宽 255 / 244、235 / 240（15）；
   负 `text-indent` 被钳到 0（16：首行 x 34 / 0）；box-sizing 的 auto 宽块 y 差
   2.5px（21）；text-decoration 末块 y 差 1.6px（04）；text-emphasis 行高 68 / 70
   （19）。text-indent → T1/T3，其余 T2 顺手处理。
8. **视觉残留（几何一致但像素不同，看 `side_*.png` 人工判定）**：
   03-indent-align 2.85%（justify 行内 gap 分摊）、17-text-align-last 5.60%、
   18-text-justify 5.46%（同源）、10-background 3.00%、13-shadow-opacity 3.21%、
   21-box-sizing 15.05%、24-border-radius 12.94%、25-border-style 11.07%、
   38-float-clear 14.78%、07-font-weight-style 2.19%（粗体栅格化）。
   背景图/渐变（26/27/28/29）差异包含「dump 未注入图片解码器」的工具限制，
   见「已知对照限制」。
9. **分页类（预期现象）**：42-multipage-flow 21.73%、43-multipage-table 16.96%，
   引擎第 1 页与浏览器连续流第 1 屏内容不同构，不作为失配依据。

## 已知对照限制

- 背景图/渐变的差异来自「dump 未注入图片解码器」，属对照工具限制；要判定
  引擎背景能力，需在 dump 里接 `imageLookup` 或改用真机截图。
- 跨页用例的 `side_*.png` 只拼第 1 页：引擎第 1 页内容与浏览器连续流第 1 屏
  不一定同构，视觉差异大是预期现象，不作为失配计数。
- 单元格配对依赖「(行,列) + 文本」：同一表格内文本完全重复的格只能按顺序配，
  极端表格需人工核对（当前用例无此情况）。
- 块配对是「文本 + 角色」启发式：`li` 内含子列表时浏览器元素文本是引擎块的
  超集，只能按「部分配对」比块顶与前几行；角色判断依赖 dump 的 `role`，
  列表项无标记时按文本兜底。
- 引擎 `nowrap`/`pre` 的 `contentWidth` 可能是 Infinity，`bboxW` 导出为 null，
  块宽按「未知」跳过；T1 改成有限宽 measure 后会自动参与比较。
- 浏览器渲染线程与引擎字体一致（同一 OTF），字宽可比；换字体需同步更新
  `render_browser.mjs` 的 `@font-face`。
- `/tmp/css_parity` 是默认输出目录，多人同时跑会互相覆盖 JSON/PNG/report。
  并行验证时给三个脚本设同一个 `CSS_PARITY_OUT`（如
  `CSS_PARITY_OUT=/tmp/css_parity_t5`），浏览器调试端口用 `CSS_PARITY_PORT`
  错开，避免抢占 9333。
