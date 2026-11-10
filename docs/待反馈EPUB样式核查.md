# 待反馈 EPUB 样式核查

核查目录：`/Users/aaa/Documents/待反馈`。2026-11-10 仍在进行中；按用户最新要求，Flex 等布局以阅微 App 为准，其他 CSS 样式以多看为准，使用同一本原书、同一章节核对。成功分页与截图不代表视觉一致。

## 语料和覆盖口径

- 189 个 EPUB 输入（含 ZIP 内 EPUB），SHA256 去重后 181 本；405 个 CSS、89,784 个 HTML、233 种 CSS 属性。
- 首两本《咸的玩笑》严格 XML DOM 确认 37、51 条实际使用规则；另外六本的 3,270 个章节确认规则命中：《万相之王》26、《人类灭绝》54、《巴别塔》38、untitled 3、《逆流纯真年代》41、《法医秦明典藏版》58 条普通规则。
- 修复后的逐本隔离进程批次：181 本、1,663 个代表章节全部成功，16,116 页完成分页几何检查，实际绘制 3,163 张 PNG。每章默认前三页，其余页保存几何与计算样式。
- 全批源码指纹：`c3d28ade30b5e9be2186e64e669285dacd7d2f89adc2d53efdda1d43490de0e7`。后续代码修改需补充受影响书籍验证，不能沿用该批次宣称最新版本全量通过。
- 静态规则命中、代表页绘制、实际多看视觉核查是不同口径；尚未完成 181 本逐书全部 CSS 样式的视觉核对。

原书、清单、截图与日志保存在 `/tmp/spectacular-feedback/`，未修改 EPUB、不写入 Git。`inventory.json`、`render_queue.json`、`strict_next_page_table.md` 保留原书与规则位置；`final-render-manifest.json`、`final-render-revision.json`、`render-final/status.json` 保存全批清单、源码指纹和执行结果。原候选中的 11 个越界末章索引已按 OPF 修正，证据见 `spine-index-corrections-20261110.json`。

## 已复现并修复

| 原书及触发位置 | 原行为与修复 | 公共回归 |
| --- | --- | --- |
| 两本《咸的玩笑》的绝对图片、静态祖先及单图章节 | 图片参与 Flex、错误缩宽或被满屏快路覆盖；保留脱流覆盖层和作者自身计算盒 | `positioned_image_test.dart`、`full_bleed_test.dart`，含最终定位像素 |
| 第二本制作说明的根 table / 单直接 table-cell | 未消费 middle/bottom；按根高度和内缩放置完整内容 | `page_root_table_cell_test.dart`，含普通容器和不对称 padding |
| 《万相之王》`Section0003.xhtml:17/19` | 零字号行内图片间空白触发 caret 断言；跳过无墨迹片段查询并保留 advance | `inline_box_whitespace_test.dart` |
| untitled `Style0002.css:10` | 透明虚线邻边使红色楔角成为矩形；透明边保留厚度、允许实线斜接 | `border_corner_join_test.dart` |
| 《逆流纯真年代》`main.css:1535` | 24px/3em 下限撑宽 `width:1em` 浮动标题；明确非 auto 宽度保留请求宽 | `narrow_author_width_test.dart`、`line_breaker_test.dart` |
| 首本《咸的玩笑》`part0004.html:14` | Flex 收到自然宽后残留旧居中偏移，只剩 18.4px 黑片；迁移对齐坐标并保留 runs、行内盒、行高 | `flex_text_alignment_test.dart`，含 RTL、末行、完整绘制像素 |
| 《燕食记》《魔王大人深不可测》资源路径 | 中文与百分号混合路径抛 URI 异常；规范化后解码，非法编码保留原名 | `resource_index_test.dart` |
| 《假面山庄》等 8 本 ZIP 条目顺序 | mimetype 非首项阻止读取；降为 OCF 警告，内容错误及归档损坏仍拒绝 | `archive_reader_test.dart`；8 本原书抽查通过，多看《假面山庄》打开证据 |
| 《绫辻行人馆系列》`top002.xhtml:17` | 浮动分页重复测尾部 LF，访问空行表崩溃；消费不绘制的尾 LF 并保留原文偏移 | `float_inline_alignment_test.dart`；原书章节通过 |
| 《白之书》`tdzh001.xhtml:16`、`main.css:621` | `margin:-84% 0em` 导致裁剪区倒置，标题消失；扩展负首尾距对应可见区域，保留净流游标 | `page_clip_test.dart`；原书前后 PNG、真机标题恢复 |
| 《白之书》风铃与标题白框 | 逐块完整绘制使后续普通流背景遮住替换图片；普通流背景先画，图片和文字后画，负层级提前且合成组保持整体 | `element_compositing_test.dart`、`paint_order_test.dart`、宿主原书图片链路像素；原书风铃覆盖白框 |
| 负外边距普通块背景 | 文字回退而背景仍从流游标开始，形成倒置边框盒；背景边框同步扣除负首尾段距 | `element_compositing_test.dart` 的负边距背景像素 |

《白之书》`usedHeight=-152.02` 与作者 CSS 精确相符，核查工具只要求净流高有限，实际内容盒尺寸仍需非负。图片导出按正式阅读器同序尝试原路径、资源索引、前 64 个章节目录，避免相对或编码路径造成工具假缺图。

## 验证

- 最新层叠修复后核心全量 1661 通过 / 8 跳过；移动端全量 1026 通过 / 6 跳过 / 1 既有统计失败。
- `stats_page_test.dart:666` 期望“25 分钟”实际“45 分钟”，历史交接已有同一失败；本次未修改统计代码。
- 移动端 Flex/浮动/定位聚焦 41 项，核心归档/资源/断行/绘制聚焦 85 项，裁剪 7 项通过。
- 核心和移动端按包静态分析、核心依赖边界、差异检查通过；未修改 `reader_ui`，其上一轮全量 753 项通过。
- MEIZU 20 / Android 16 的隔离 Release 包 `com.spectacular.reader_mobile.css_test` 离线构建成功；8 本 16 页实际绘制，`device-followup/report.json` 中 `errors=[]`。未替换手机正式阅读器。
- 同机多看已取首本作者语、“正文一”、假面山庄封面、白之书“假面舞会”截图；历史多看图另覆盖巴别塔、untitled、逆流纯真年代及法医秦明。
- 新增同机多看 untitled 第一章截图、阅微首本“正文一”和设置截图。阅微为字号 20、思源宋体；项目隔离包为字号 16，数值尺寸比较须先统一设置，标题与笑脸的分离关系已有可见差异。
- 最新层叠代码另复测《白之书》spine 10，见 `render-stacking-final/181/`；最新代码尚未重跑 181 本批次或重建隔离真机包。核心日志 `core-stacking-full.log`，移动日志 `mobile-stacking-full.log`。

## 未处理差异和风险

- 首本“正文一”：标题裁剪已恢复，阅微将标题放在页面中上部、小笑脸置于下方；项目笑脸较大并遮住标题。按新要求以阅微布局为准，继续定位尺寸与定位处理。作者语签名位置也待阅微同页核对。
- 《白之书》标题和风铃层叠已恢复；正文区起点与多看仍不同，出血策略待核对。
- 巴别塔和法医封面的圆角、模糊底图、白框底纹不在作者 CSS 或原 JPG 中，仍需确认多看内置图片策略。
- Flex 最终宽度小于已有行 advance 时仍需真正重排并计算行高，当前坐标迁移只适用于原行能完整放入的情况。
- 根 table 对齐只覆盖一个直接 cell；嵌套定位、fixed、其他 table 结构、系统字体及原书缺字体回退尚未全部核对。
- `PageContent.hitTest` 简化 API 仍以净流高限制底界；正式 UI 使用 `TextHitTester`，本次未扩大这一接口范围。
- 普通流绘制分阶段保留现有容器结构，尚未实现跨普通容器的完整 CSS 层叠上下文提升与排序；定位、滤镜和透明度有回归覆盖，但不能称为完整 CSS 层叠实现。

下一步先按阅微核对首本 Flex 与图片布局，再按清单补齐多看/阅微同页证据，继续修复差异。

OCF 条目顺序仍违反 [EPUB 3.3 §4.2.2](https://www.w3.org/TR/epub-33/#sec-zip-container-mime)；本次允许读取是依据多看原书打开证据作出的兼容处理，不改变 EPUB 作者规范。
普通流背景、替换内容及负层级的绘制顺序同时参考 [CSS 2.2 Appendix E](https://www.w3.org/TR/CSS22/zindex.html)，原书验收仍按上述 App 基准。
