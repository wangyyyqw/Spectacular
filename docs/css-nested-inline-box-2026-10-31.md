# 非空与嵌套行内盒修复（2026-10-31）

基线 `60e1d14`。继续核对非空原子盒的外层样式及嵌套边界，不新增依赖，
不改比较工具、容差或既有非嵌套盒的近似基线策略。

## 变更与定位

- `epub_chapter_source.dart` 摘除非空盒时原先丢弃覆盖它的祖先标记，导致
  盒前后颜色、字重消失；聚合标记按子到父关闭，内盒还会先被摘成正文兄弟。
- 以范围、链深度和来源属性 Map 身份判断真实后代；消费盒本身及其后代，
  重映射并保留实际祖先。解析器每元素建立独立的不可变属性 Map，样式链
  复用该身份，避免同形空兄弟与空内盒共用偏移时相互吞并。
- 先提取最外层原子盒，内盒递归进入外盒 `PageBlock` 载荷。子样式从最终
  父样式继承，子盒百分比以父内容宽计算，不重复解算相对字号；auto 宽度
  包含内盒及 inset。原子子盒位于内容首尾时保留与文字之间的可见空格。
- 无内容行仍用底部 margin 边缘作基线；含嵌套盒的父盒采用最后内容行基线
  加上边框与内边距。普通非嵌套盒保持原策略。
- `page_renderer.dart` 递归绘制内盒，即使载荷只有盒、没有文字也绘制；文字
  复用现有 `_paintLineText` 的占宽位移，避免后字覆盖内盒，并遵守外盒裁剪。
- 复用正文/表格共用提取与既有排版路径。已有大型章节布局函数不整体重构；
  新增局部辅助函数不超过 40 行。

## 验证证据

- `bash tool/run_all.sh`：三包分析无问题；核心 **1296**、UI **170**、宿主
  **407** 项通过，合计 **1873** 项，9 项条件跳过。日志
  `/tmp/spectacular-css6-validation.log`；Flutter 验证与对照导出串行运行。
- 新增 8 项实际 EPUB 公共行为回归及 3 项绘制回归。前 7 项宿主测试和
  3 项绘制测试在旧实现下失败，修复后通过；新增首尾空格回归在修复后通过。
  旧实现日志 `/tmp/spectacular-css6-red.log`、
  `/tmp/spectacular-css6-paint-red.log`；新旧宿主针对性回归合计 27 项通过，
  日志 `/tmp/spectacular-css6-focused-host.log`。绘制验证 40×18 红盒恰有
  720 个红像素、缓存与非缓存一致、多层空载荷可见及 overflow 裁剪生效。
- 核心依赖边界、严格分析守卫、边界脚本自测和覆盖矩阵回归通过；覆盖矩阵
  连续生成两次 SHA-256 相同。用户原有设计文档 SHA-256 保持不变，未暂存。
- 新增第 103 组，六段覆盖外层颜色、嵌套盒、相对字号、百分比宽、空内盒
  及 auto 外盒。同一字体、350×800、DPR 1，全量运行 **100** 组 Chrome
  与真实 EPUB 引擎对照。改前复用基线的 99 组产物并显式补跑 103；改后
  100 组完整重跑。全部浏览器 JSON/PNG 不变，引擎仅 103 的 JSON/PNG 变化，
  其余 **99** 组逐字节不变。
- 103 几何/样式失配 **20 → 7**；同一 100 组全量 **83 → 70** 项，涉及
  11 个用例，未配对 0。新样例墨迹形状差 **7.81% → 1.97%**，原始像素差
  **11.68% → 2.66%**。已人工检查前后并排截图：盒前后颜色保留，内盒进入
  外盒，百分比宽与空内盒占宽恢复；仍有基线位置差异，不宣称完全兼容。

产物仅在 `/tmp/spectacular-css6-before/`、`/tmp/spectacular-css6-after/`。
复现（仓库根；Flutter 命令串行）：

```sh
bash tool/run_all.sh
CSS_PARITY_OUT=/tmp/css-nested-inline node tool/css_parity/render_browser.mjs
(cd apps/reader_mobile && CSS_PARITY=1 CSS_PARITY_OUT=/tmp/css-nested-inline \
  flutter test --no-pub test/css_parity/parity_dump_test.dart)
CSS_PARITY_OUT=/tmp/css-nested-inline /usr/bin/python3 tool/css_parity/compare.py
```

## 未处理风险与下一步

- 103 仍有 7 项失配，包含约 2.6px 的行基线差；全量另有 63 项既有失配。
  根 padding、页首裁剪与字体度量口径未改，不在比较侧放宽容差。
- 本次验收限横排原子文本盒与空盒。盒内图片/浮动/ruby、块级内容、保留空白
  模式、复杂双向/竖排、着重号内部绘制、嵌套 opacity 等组合未完整验收。
  非空非嵌套盒近似基线与最多四轮换行重测不变。
- 深层嵌套性能、真机长书内存及 spine 30 索引重放性能回退未处理。
- 下一步优先定位 103 的剩余基线差异，分别核对 CSS 行盒、字体基线与导出口径，
  再决定最小修复位置。

依据：[CSS 2.2 视觉格式化模型](https://www.w3.org/TR/CSS22/visuren.html)
的原子行内盒与独立格式化上下文，
[§10.8.1](https://www.w3.org/TR/CSS22/visudet.html#line-height) 的 inline-block 基线。
