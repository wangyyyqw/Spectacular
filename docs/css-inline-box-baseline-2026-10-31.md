# 行内盒实测基线修复（2026-10-31）

基线 `7fad833`。定位第 103 组剩余差异；不改用例、比较工具、容差或依赖。

## 变更与定位

- 非嵌套非空盒没有传入实际末行基线，排版器借用外部行的字号/行高近似，
  且没有包含盒顶部 padding/border。第 103 组首段因此导出 42.38px，而浏览器
  为 45px；内盒与外部文字的绘制基线也确实错位，不是导出误差。
- `epub_chapter_source.dart` 为所有非空原子盒提供顶部 inset 加实际末行基线。
  无内容行或 `overflow` 非 `visible` 时改用底部 margin 边缘，符合 CSS 2.2
  §10.8.1；字号、行高与多行内容不再借用外部字体度量。
- `line_breaker.dart` 对实测基线使用真实 margin 盒的上下延伸，并与文字
  strut 合成行高。末行基线在边框盒外时允许负的下延伸，不把溢出内容高
  当成盒尺寸；被裁剪内容不再把行盒撑到完整内容高。
- 只改变提供实测基线的路径。未提供 `contentBaseline` 的调用方保留原有
  近似，其他竖直对齐模式不在本次重写。移除同一函数内未被读取的两组增长数组。
  既有大型章节布局/行盒函数不整体重构，新增测试辅助函数均不超过 40 行。

## 验证证据

- `bash tool/run_all.sh`：三包分析无问题，核心 **1298**、UI **170**、宿主
  **414** 项通过，总计 **1882** 项，9 项条件跳过。最终日志
  `/tmp/spectacular-css7-validation-final.log`；Flutter 验证和对照导出串行运行。
- 新增 7 项实际 EPUB 回归：顶部与底部 inset、不等字号/行高、多行末行基线、
  逐层嵌套，以及 hidden/auto/scroll 的底部 margin 基线与溢出行高。
  新增 2 项核心公共布局回归：文字 strut 合成行高、盒外基线的负下延伸。
  9 项在旧实现下失败，日志 `/tmp/spectacular-css7-host-red.log`、
  `/tmp/spectacular-css7-core-red.log`；修复后核心针对性 20 项、宿主新旧
  针对性 34 项通过，日志 `/tmp/spectacular-css7-core-focused.log`、
  `/tmp/spectacular-css7-host-focused.log`。
- 核心依赖边界、严格分析守卫、边界脚本自测与覆盖矩阵回归通过。覆盖矩阵
  重新生成后没有差异；用户原有设计文档 SHA-256 不变，未暂存或提交。
- 全量 **100** 组 Chrome 与真实 EPUB 引擎重新导出。改前复用 `7fad833`
  已验证产物；全部浏览器 JSON/PNG 不变，引擎 JSON 仅 **53/103** 变化，
  PNG 仅 **103** 变化。其余 **98** 组 JSON/PNG 逐字节不变；53 仅首行
  基线 54.2525 → 54.1525px，浏览器为 54.19px，截图与失配数不变。
- 103 几何/样式失配 **7 → 0**，全量 **70 → 63**，涉及用例 **11 → 10**，
  未配对 0。墨迹形状差 **1.97% → 1.02%**，原始像素差 **2.66% → 2.17%**。
  首三段基线分别恢复为 45.38/107.38/172.38px，与浏览器 45/107/172px
  相差约 0.38px；混合字号段行高由 48 → 48.276px，浏览器为 48.41px。
  已人工检查并排截图，盒内与盒外文字的基线恢复；不宣称逐像素一致。

产物仅在 `/tmp/spectacular-css7-before/`、`/tmp/spectacular-css7-after/`。
复现（仓库根，Flutter 命令串行）：

```sh
bash tool/run_all.sh
CSS_PARITY_OUT=/tmp/css-inline-baseline node tool/css_parity/render_browser.mjs
(cd apps/reader_mobile && CSS_PARITY=1 CSS_PARITY_OUT=/tmp/css-inline-baseline \
  flutter test --no-pub test/css_parity/parity_dump_test.dart)
CSS_PARITY_OUT=/tmp/css-inline-baseline /usr/bin/python3 tool/css_parity/compare.py
```

## 未处理风险与下一步

- 全量仍有 63 项既有失配；字体栅格、根 padding、页首裁剪口径未改。
  未提供实测基线的旧调用方、top/bottom/middle 等组合仍保留既有近似。
- 盒内图片/浮动/ruby、保留空白、复杂双向/竖排、嵌套 opacity 及深层性能未完整
  验收；spine 30 重放性能与长书内存旧风险保留。
- 横排原子盒内的着重号已由同日审计第八轮接通并补像素、实际 CSS 和浏览器对照；
  下一步继续核对行盒/字体盒计量口径。

依据：[CSS 2.2 §10.8 行盒高度](https://www.w3.org/TR/CSS22/visudet.html#line-height)
及同节的 inline-block 末行基线、无行/非 visible 的底部 margin 基线规则。
