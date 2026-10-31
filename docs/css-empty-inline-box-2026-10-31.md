# 空行内盒遗漏修复（2026-10-31）

基线 `d107290`。继续第 102 组的空 `span.box` 遗漏问题，不改对照容差、
绘制样式或既有非空盒的基线策略，不新增依赖。

## 变更与定位

- 聚合器 `closeMark` 原先丢弃零长度区间，`take` 又丢弃纯空文本节点；宿主
  `inlineDisplay` 没有区分 inline-block，`extractInlineFloat` 再次排除空文本、
  空区间和空内容。这些边界共同导致声明的 36px 盒完全消失。
- 聚合器仅为明确的 inline-block 保留零长度结构标记和属性链，不给正文增加
  占位字符。原子盒内尾部折叠空白不泄漏，盒后空格与显式换行保留；空盒不能
  被纯图片折叠吞掉。未声明 display 的普通空元素与隐藏元素仍不产出盒。
- 宿主复用 `InlineBoxSpec`：空内容布局为零宽、零高、无文本行，盒尺寸仍按
  width/height、min/max、padding、border、margin 合成。auto 与显式零宽不
  强制撑成 1px；没有内容行的基线取底部 margin 边缘，并在重映射时保留。
- 空盒提取后消费自身标记，避免重复提取；保留外层文字样式。共享文本偏移
  的相邻盒按输入顺序稳定排序。复用既有原子盒换行、绘制、分页路径。
- 单元格和 caption 不再以空文本作为唯一判据；纯空盒参与测宽、行高及最终
  布局，空盒邻接空格不被纯文本 trim 丢掉。删掉因此不再使用的 `cellTexts`。
- 只改上述边界。已有大型聚合/章节布局函数不整体拆分；新增局部函数不超过
  40 行。稳定排序只给既有测量辅助函数增加平局规则，避免扩大排版器重构范围。

## 验证证据

- 三包分析通过；核心 **1293**、UI **170**、宿主 **399** 项通过，总计
  **1862** 项，9 项条件跳过。统一脚本的核心/UI 日志在
  `/tmp/spectacular-css5-validation.log`，宿主串行复验日志在
  `/tmp/spectacular-css5-host-serial.log`。
- 新增 4 项聚合、9 项实际 EPUB 章节源回归。覆盖空盒结构、字数不变、外层
  样式、纯空段落、auto/零尺寸、margin 基线、相邻 40 盒的顺序和三行换行、
  内外空白、尾部换行、隐藏元素，以及纯空/混合/邻接空白单元格。
  其中 **12 项在旧实现下失败**，普通空/隐藏元素的保护断言在旧实现下通过。
  旧实现日志 `/tmp/spectacular-css5-red-final.log`；最终 9 项宿主针对性回归
  日志 `/tmp/spectacular-css5-focused-final.log`。
- 核心依赖边界、严格分析守卫、边界脚本自测和覆盖矩阵排序回归通过。
  用户原有设计文档的 SHA-256 保持不变，没有暂存或提交该文件。
- 同一字体、350×800、DPR 1，显式运行全部 99 组 Chrome 与真实 EPUB 引擎
  对照。改前复用 `d107290` 的已验证产物；99 份浏览器 JSON 不变，引擎仅第
  **102** 组 JSON/PNG 改变，其余 **98** 组逐字节不变。没有改用例或容差。
- 第 102 组 `hasInlineBox: false → true`、行宽 **168px → 204px**，与浏览器
  一致；本组几何/样式失配 **2 → 0**，全量 **65 → 63** 项，涉及用例
  **11 → 10** 个，未配对 0 项。墨迹形状差 **1.45% → 0.81%**，原始像素
  差 **3.62% → 3.16%**。已人工检查并排截图：灰盒、盒后文字和着重号均
  正确移动，前六段没有改变；不宣称逐像素一致。

产物仅位于 `/tmp/spectacular-css5-before/`、`/tmp/spectacular-css5-after/`。
复现（仓库根；Flutter 验证与对照导出串行运行）：

```sh
bash tool/run_all.sh
CSS_PARITY_OUT=/tmp/css-empty-inline node tool/css_parity/render_browser.mjs
(cd apps/reader_mobile && CSS_PARITY=1 CSS_PARITY_OUT=/tmp/css-empty-inline \
  flutter test --no-pub test/css_parity/parity_dump_test.dart)
CSS_PARITY_OUT=/tmp/css-empty-inline /usr/bin/python3 tool/css_parity/compare.py
```

统一脚本首次与另一 Flutter 对照导出并行时，宿主一项数据库测试报缺少
`libsqlite3.dylib`；停止并行后串行重跑宿主分析与完整测试。未修改依赖、
原生库配置或数据库代码，避免把验证进程的产物竞争误修成产品变更。

## 未处理风险与下一步

- 全量仍有 63 项既有失配，字体栅格、根盒 padding、页首裁剪口径未改。
  自动对照未导出独立着重号字段，仍依靠绘制回归与截图核对。
- 原子盒嵌套、盒内块级内容、保留空白模式、ruby 避让、复杂双向/竖排及
  对齐组合尚未完整验收。非空盒的既有近似基线与最多四轮换行重测不变。
- 保留 spine 30 索引重放性能回退；未做真机性能或长书内存测试。
- 下一步优先核对非空原子盒提取后的外层样式保留及嵌套盒边界，再扩展对照。

依据：[CSS 2.2 §10.3.9](https://www.w3.org/TR/CSS22/visudet.html#inlineblock-width)
的 inline-block 宽度与 shrink-to-fit，
[§10.8.1](https://www.w3.org/TR/CSS22/visudet.html#line-height) 的无内容行基线。
