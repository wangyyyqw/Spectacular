# P7-03 UA 样式表对照与扩充落地

> 任务：P7-03 ｜ 日期：2026-10-24
> 基线：Reeden 2.0.0 的 134 规则 UA 表（`参考/reeden/reports/630-ua-stylesheet.md`，注释版全文 `参考/reeden/work/epub-css/sheet-A.css`）
> 产出：`packages/reader_core/lib/css/ua_stylesheet.dart`（规则文本 + 层叠规则集 + 块级覆盖层）
> 结论：规则文本 33 条按 WHATWG HTML 15.3 分节落地，逐条注明出处；当前管线消费块级覆盖层 17 个标签；6 处「与浏览器的刻意差异」全部有处置结论。

---

## 1. 落地形态（三条读取路径）

| 路径 | 内容 | 消费方 |
|---|---|---|
| `uaStylesheetCss` | 33 条规则文本（每条带规范出处注释） | 单一事实来源，未来层叠接线直接解析 |
| `uaRules()` | 解析为 `CascadeRule`（UA origin），已验证可被 `Cascade.compute` 消费 | 作者样式逐元素层叠接入时使用（P3/P4 后续） |
| `UaBlockDefaults.apply()` | 17 个块级标签的覆盖层（仅含当前排版/绘制栈已消费的物理属性） | `EpubChapterSource.loadChapter` 与快照 harness（同一路径） |

配套改动：
- `BlockBuilder._noDisplayTags` 补 `noscript/area/basefont/datalist/noframes/param`（display:none，15.3.1）；
- `ComputedStyle` 行高继承修正：**无单位 line-height 因子按子元素自身字号重算**（CSS 2.1 §10.8），px/百分比仍按绝对量继承——这是标题字号放大后行高正确跟随的前提，此前全库单一样式未暴露该语义缺口。

## 2. 逐分区对照（Reeden 134 规则 → 本项目处置）

| WHATWG 分区 | Reeden 规则要点 | 本项目处置 | 依据 |
|---|---|---|---|
| 15.3.1 隐藏元素 | noscript!important 隐藏、area/basefont/datalist/param 等 | **已落地**（样式表 + BlockBuilder 双路径） | 与 Chrome 一致 |
| 15.3.2 页面 | body margin 8px | **margin:0**（阅读器边距接管） | Reeden 630 §4-3 补充规则；技术方案 §7.5 |
| 15.3.3 流内容 | p/blockquote/figure margin-block 1em、blockquote/figure margin-inline 40px | blockquote/figure **已落地**；p 的默认段距**暂不启用**（段距按阅读器设置归一，待 P4-21 设置项接入后启用） | 技术方案 §7.5 第 3 条 |
| 15.3.4 短语内容 | b/strong/i/em/code/sub/sup/mark/u/del 等 13 组 | **样式表已收**；行内 run 逐段样式随「逐 run 层接线」启用（当前聚合器单一 run） | 排线分阶段 |
| 15.3.5 双向文字 | bdi/bdo unicode-bidi | 不做（§38.4 跟随引擎 bidi） | 技术方案边界 |
| 15.3.6 分节与标题 | h1–h6 字号 2.00/1.50/1.17/1.00/0.83/0.67em、margin 0.67/0.83/1.00/1.33/1.67/2.33em、加粗 | **已落地**（含 page-break-after:avoid 表达避页底） | WHATWG + Reeden 630 §2-5 |
| 15.3.7 列表 | li list-item、ul/ol padding-inline 40px、dd margin 40px、嵌套 disc→circle→square、ol[reversed] | 缩进/边距/dt 加粗**已落地**；嵌套类型与反序**待 P3-23**（标记未绘制）；`ul ul` 嵌套选择器在样式表预留 | CSS Lists 3 |
| 15.3.8 表格 | border-spacing 2px、td/th padding 1px、th 加粗居中、table[border] 表现属性 | th **已落地**；裸表格网格线与表格默认值**待 P3-17～21** | 中文网文裸表格高频（630 §1） |
| 15.3.10 表单 | radio/checkbox 静态图示 0.8em | 不做（一期无表单渲染） | 产品边界 |
| 15.3.11 hr | margin-block 0.5em、inset 边框 | margin **已落地**；边框绘制**待 P3-24** | WHATWG |
| 居中 | center/div[align] 的 -webkit-center 行为 | center **已落地**（text-align:center）；div[align] 需属性选择器，**随 P7-04 评估** | Chrome 对齐 |
| ruby（CSS Ruby 1） | rt 50% 字号、缩进归零 | **样式表已收**，接线**待 P5-01～04** | Reeden 630 §2-4 |

## 3. 六处「与浏览器的刻意差异」处置（验收要求）

| # | Reeden 差异 | 处置 |
|---|---|---|
| 1 | `noscript{display:none!important}`（XHTML 也隐藏） | **采纳**：样式表 + BlockBuilder 双落地，有测试 |
| 2 | audio 无 controls 隐藏、多看音频例外 | **不做**：一期无音视频（§1.2），登记 P5 之后 |
| 3 | `sub/sup` 借行距（borrow-leading，fixups N5） | **分两步**：UA 覆盖层已落 `font-size:0.83em + vertical-align`；借行距行为**待 P7-09** 专项实现 |
| 4 | ruby `rt` 缩进归零 + 50% 字号（独立块容器） | **样式表已收**；本项目是行内覆盖模型，接线随 P5 |
| 5 | h1–h6 `break-after:avoid; break-inside:avoid`（标题避页底） | **采纳**：以 `page-break-after:avoid` 落地（P0 属性表内表达） |
| 6 | 列表嵌套类型 disc→circle→square | **待 P3-23**（列表标记绘制未实现），选择器规则已预留 |

## 4. 快照回归与归因（验收要求）

- 5 本样本整书快照基线更新（`STYLE_REGRESSION_UPDATE=1`），差异**逐本归因**（全部为预期变更，无未解释差异）：

| 样本 | 样本内命中标签 | 归因 |
|---|---|---|
| basic.epub | h1×4、ol | 章标题「第一章」按 h1 2em 加粗 + 上下边距 |
| styles.epub | h1×2、h2×3、blockquote×1 | 标题分级 + 引用左右 40px 缩进（像素差最大，符合预期） |
| table.epub | h1×2、figure×1、th×3 | 标题 + figure 边距 + th 加粗居中 |
| toc-ncx.epub | h1×3 | 章标题 |
| cjk-vertical.epub | h1×2 | 章标题 |

- 页数全部不变（3/2/2/3/1），差异均为页内版式变化；`page_snapshot_test.dart`（纯 p 段落样本）**零差异**，证明覆盖层只影响命中的标签。

## 5. 验证记录

```bash
cd packages/reader_core
flutter analyze                        # No issues found
flutter test                           # 493+ 通过（含新增 ua_stylesheet_test 10 例、block_builder noscript 例）
STYLE_REGRESSION_UPDATE=1 flutter test test/snapshot/style_regression_test.dart   # 基线更新
flutter test test/snapshot/style_regression_test.dart                            # 通过
bash tool/run_all.sh                   # 全部通过：3 个包
bash tool/check_core_boundary.sh       # 通过
bash tests/analysis/verify_strict_flags.sh  # 通过
bash tests/tool/verify_core_boundary.sh     # 通过
```

## 6. 遗留与去向

| 项 | 去向 |
|---|---|
| p 默认段距启用 | P4-21 设置面板（段距设置） |
| 行内 run 样式（b/code/em…） | 逐 run 层接线（样式引擎接入作者 CSS 时） |
| 列表标记/嵌套类型/ol[reversed] | P3-23 |
| 表格默认边框/间距、table[border] | P3-17～P3-21 |
| hr 边框、mark 背景 | P3-24 |
| sub/sup 借行距 | P7-09 |
| div[align] 属性居中 | P7-04 评估属性选择器 |
| ruby rt 规则接线 | P5-01～P5-04 |
