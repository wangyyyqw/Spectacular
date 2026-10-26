# CSS 属性对照工具（引擎 vs 浏览器）

目标：逐条 CSS 属性对比「引擎渲染」与「Chromium 渲染」，把差异收敛到接近浏览器。

## 组成

| 文件 | 作用 |
| --- | --- |
| `cases/*.json` | 用例：`{name, css, html}`，每个文件聚焦一组属性 |
| `render_browser.mjs` | Chrome CDP（350×800、dpr=1）渲染：截图 + 每个元素的 `getBoundingClientRect`、文本行 `client rects`、关键计算样式 |
| `../../apps/reader_mobile/test/css_parity/parity_dump_test.dart` | 引擎侧渲染：同尺寸截图 + 每块/每行几何与计算样式（`CSS_PARITY=1` 才跑） |
| `compare.py` | 按文本配对，输出 `report.md`（逐项差异）与 `side_<case>.png`（左浏览器 / 右引擎） |

## 用法

```bash
node tool/css_parity/render_browser.mjs
cd apps/reader_mobile && CSS_PARITY=1 flutter test test/css_parity/parity_dump_test.dart && cd ../..
/usr/bin/python3 tool/css_parity/compare.py            # 全部用例
/usr/bin/python3 tool/css_parity/compare.py 03-indent-align 09-box-model
```

产物在 `/tmp/css_parity/`：`report.md`、`browser_*.png/json`、`engine_*.png/json`、`side_*.png`。

## 口径

- 浏览器几何：`getBoundingClientRect` = 边框盒；行几何 = 文本节点 `client rects`（字体盒，不是整行行盒）。
- 引擎几何：块顶 = 版面 y + 段前扩展；行 y 相对块顶；行宽 = 排版行宽。
- 容差：块 y/h 1px，行宽 4px，行 y 按 `(line-height - font-size)/2 + 0.5` 放宽（字体盒 vs 行盒差异）。
- 浏览器侧必须带 `--allow-file-access-from-files`，否则 `@font-face` 读不到本地 OTF，会回退系统字体导致字宽不可比。

## 已发现并修掉

1. **盒类简写被 UA 长属性压制**（P9-27）：作者 `p { margin: 8px 0 }` 输给 UA
   `p { margin: 1em 0 }` 拆出的 `margin-top`，首段凭空多 9px 且段距全错。
   修法：级联阶段把 margin/padding/border/border-width/style/color 展开成长属性
   （与浏览器一致），按同一属性名比优先级。

## 待收敛（按影响排序）

1. 两端对齐（justify）：引擎行宽 340 / 浏览器 350，末个间隙未参与均分。
2. `white-space: pre`：换行未转硬断行（引擎 1 行，浏览器 3 行）；`pre-wrap` 同源。
3. 行内元素竖直几何：`sup/sub/vertical-align: text-top/middle` 只影响基线偏移，
   行高不扩（浏览器 32.5 / 引擎 31）。
4. 标点挤压策略与 Chrome 默认 `text-spacing-trim: normal` 不同：同样行宽下引擎
   多排一个字（牵涉 CJK 标点挤压是否默认开启）。
5. `box-sizing: border-box` 的宽度约束未把 padding/border 计入可用宽（引擎行宽
   281.5 超过内容宽 274）。
6. 表格用例只有 1 块导出（表格按块合并），后续需要导出单元格几何才能逐项比。
