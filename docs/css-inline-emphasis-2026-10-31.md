# 行内独立着重号与跨行定位（2026-10-31）

## 变更范围

基线 `33b88b7`，继续上一轮的下一步。章节源已有 `StyledRun`，本次只接通普通
横排文本的绘制，不改解析、布局、分页、CFI、主题策略或比较容差，不新增依赖。

- `paint/text_emphasis.dart`：按字素簇起始位置选择行内样式，区间空隙使用块样式。
  `none` 可取消继承的标记；形状、字号、颜色、位置及基线位移均取区间值。
  `currentcolor` 复用正文主题策略，保留作者配色。组合字符不拆分，图片占位符不标记。
- 每行沿有序区间前进，不为每个字符扫描全部区间；每块按计算样式缓存标记字形，
  使用后统一释放。未声明任何着重号的块不进行额外逐行排版。
- `page_renderer.dart`：着重号与正文共用行画笔原点，消除旧代码重复累加 `line.top`
  的问题；行内盒占宽复用 `inlineBoxAdvanceAt`，标记随基线位移。切片裁剪留出
  行内标记空间，不因此增加行盒、页高或修改分页。非缓存行画笔使用后释放。
- 横排趟跳过竖排块，竖排仍走既有逐列实现，不叠加横排标记。
- 新增 `102-inline-emphasis` 及 12 项公共绘制入口回归；更新覆盖矩阵与用例数。
  着重号模块低于 500 行，新增函数均不超过 40 行、参数不超过 5 个。大型页面
  几何函数仅改裁剪范围接线，不顺带重构旧模块；测试主函数只注册独立测试。

## 验证

- `bash tool/run_all.sh`：三包静态分析通过，核心 **1289**、UI **170**、宿主
  **390** 项通过，合计 **1849** 项；9 项条件跳过。
  日志 `/tmp/spectacular-css4-validation.log`。
- 新增 12 项覆盖区间取消、上下位置、字号、当前色、跨行跨页、组合字符边界、
  盒占宽、图片占位符、基线位移、紧行高裁剪及缓存一致性。前 11 项在旧绘制下
  失败，改后通过；多行定位旧实现实测推进 **86px**，实际行高 **43px**。
  失败日志 `/tmp/spectacular-css4-red-final.log`。最终着重号解析/绘制针对性共
  **31** 项通过，日志 `/tmp/spectacular-css4-focused-final.log`。
- 核心依赖边界、严格分析选项、边界脚本自测、覆盖矩阵排序回归通过；生成矩阵
  幂等，用户原有设计文档修改保持不变。
- Flutter 3.47.5 / Chrome 156.0.8078.74，350×800、DPR 1、相同内置宋体。
  浏览器和实际 EPUB 章节源显式运行全部 **99** 组用例；99 份引擎几何 JSON
  与改前逐字节相同，只有第 **19、57、102** 组 PNG 改变，其余 96 组逐字节相同。

| 用例 | 改前墨迹形状差 | 改后墨迹形状差 |
| --- | ---: | ---: |
| 102-inline-emphasis | 3.49% | 1.45% |
| 19-text-emphasis | 4.71% | 4.30% |
| 57-emphasis-style-longhand | 4.39% | 4.40% |

第 102 组原始像素差 **4.32% → 3.62%**。已人工检查三组并排截图：第 102 组
前六段的范围、取消、上下位置、字号、颜色及换行标记正确；最后一段的空盒仍缺失。
19/57 仍有页首裁剪、行盒/字体盒及栅格差异，不宣称逐像素一致。
自动样式比较未导出着重号字段，几何结果不能替代像素断言和人工截图核对。

产物仅位于 `/tmp/spectacular-css4-before/`、`/tmp/spectacular-css4-after/`，不提交。
复现（仓库根）：

```sh
CSS_PARITY_OUT=/tmp/css-inline-emphasis node tool/css_parity/render_browser.mjs
(cd apps/reader_mobile && CSS_PARITY=1 CSS_PARITY_OUT=/tmp/css-inline-emphasis \
  flutter test --no-pub test/css_parity/parity_dump_test.dart)
CSS_PARITY_OUT=/tmp/css-inline-emphasis /usr/bin/python3 tool/css_parity/compare.py
```

## 未处理风险与下一步

- 第 102 组新增样例暴露 **2 项改前已有失配**，全量由上一轮 98 组的 63 项变为
  99 组的 **65 项**，涉及 11 个用例、未配对 0 项；本次改前与改后均为 65 项。
  墨迹形状差超过 2% 的用例由 9 个降至 8 个。新增失配不计作本次几何回归，
  也不通过删样例或放宽比较阈值掩盖。
- 其中空 `span.box` 的 36px 行内盒未进入章节布局：引擎 `hasInlineBox: false`、
  行宽 **168px**，浏览器 **204px**。宿主提取链存在空区间排除分支
  （`epub_chapter_source.dart` 的 `extractInlineFloat`），需进一步核对聚合与提取
  边界。本轮只验证已有 `InlineBoxSpec` 的标记位移，不宣称空盒的端到端问题已修。
- 表格单元格、原子行内盒内部的独立标记、ruby 冲突及标记撑高行盒未扩展；竖排
  绘制、复杂双向文字/两端对齐、特殊字体回退与混排上下标还需独立视觉验收。
- 保留上一轮 Chrome 默认点形与规范默认圆形的差异、根盒 padding、页首裁剪及
  spine 30 索引重放性能回退；本轮未做真机性能或长书内存测试。
- 下一步优先复现并修复空行内盒遗漏，锁定聚合/提取边界，再验证第 102 组盒占宽。

依据：[CSS Text Decoration 3 §3.1](https://www.w3.org/TR/css-text-decor-3/#text-emphasis-style-property)
的继承与字素簇范围、[§3.2](https://www.w3.org/TR/css-text-decor-3/#text-emphasis-color-property)
的继承后当前色解算、[§3.4](https://www.w3.org/TR/css-text-decor-3/#text-emphasis-position-property)
的按字符定位。规范要求的 ruby 避让和行盒撑高仍保留为未处理边界。
