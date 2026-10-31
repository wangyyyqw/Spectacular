# 着重号简写、默认形状与层叠重置（2026-10-31）

## 变更

基线 `2a22e3a`，继续上一轮 CSS 对照的下一步。不新增依赖，不改布局、分页、
页首裁剪或对照容差，保留用户已有设计文档修改。

- `cascade.dart`：`text-emphasis` 展开为样式与颜色长属性，共用原声明的来源、
  特异性、重要性和顺序；缺项重置为 `none/currentcolor`，不重置位置。
- `computed_style.dart`：复用颜色解析和括号内空白分词，支持现有形状与颜色的任意
  顺序、仅颜色简写；过滤重复/冲突/未知关键字，整条无效简写不覆盖早先合法声明。
  直接构造仍可解析简写，但不回读层叠阶段已被长属性 `inherit` 覆盖的简写。
- 仅 `filled/open` 按规范计算：横排为圆形，竖排为芝麻；竖排 `sideways` 属横排
  字向，使用圆形。继承已经计算的形状，不按子元素的书写模式重复解算。
- `currentcolor` 保留为现有 `textEmphasisColor == null` 哨兵，继承后跟随子元素
  正文色。横排绘制删除多余的全局主题色回退，复用正文已决策的主题颜色覆盖。
- 新增 `101-emphasis-shorthand`，更新用例数与生成式覆盖矩阵。生产新增解析函数
  均少于 40 行；现有大型工厂/简写分派仅局部接线，不做无关拆分重构。

## 验证证据

- `bash tool/run_all.sh`：三包静态分析通过，核心 **1277**、UI **170**、宿主
  **390** 项测试通过，合计 **1837** 项；9 项条件跳过。完整日志：
  `/tmp/spectacular-css3-final-validation.log`。
- 新增 8 项层叠/解析测试与 1 项主题颜色像素回归；着重号针对性共 **19** 项通过。
  最初 6 项解析回归在旧实现下失败，日志 `/tmp/spectacular-css3-red.log`；主题颜色
  回归在修复前失败、修复后通过，日志 `/tmp/spectacular-css3-color-red.log` 与
  `/tmp/spectacular-css3-focused.log`。像素断言同时覆盖默认文字跟随主题色和作者绿色。
- 核心依赖边界、严格分析选项、边界脚本自测及覆盖矩阵排序回归均通过。
- Flutter 3.47.5 / Chrome 156.0.8078.74，350×800、DPR 1、相同内置宋体：浏览器与
  实际 EPUB 章节源显式执行全部 **98** 组。98 份引擎几何 JSON 与基线逐字节相同，
  仅第 101 组截图改变，其余 97 份截图逐字节相同。全量仍为 **63 项失配、
  10 个用例、0 项未配对**；墨迹形状差超过 2% 的仍为 8 组。
- 第 101 组人工并排检查：红色空心圆、后写蓝色长属性、无效声明保留蓝色芝麻、
  绿色重置与继承、`none` 去掉标记均正确。原始像素差 **0.83% → 0.68%**，
  墨迹形状差 **0.30% → 1.40%**；默认圆形与 Chrome 点形的差异保留，不宣称
  所有视觉指标改善。自动几何/样式比较尚未导出着重号字段，不能以其零失配替代
  针对性断言和截图检查。

产物位于 `/tmp/spectacular-css3-before/`、`/tmp/spectacular-css3-after/`，不提交。
复现（仓库根）：

```sh
CSS_PARITY_OUT=/tmp/css-emphasis-shorthand node tool/css_parity/render_browser.mjs
(cd apps/reader_mobile && CSS_PARITY=1 CSS_PARITY_OUT=/tmp/css-emphasis-shorthand \
  flutter test --no-pub test/css_parity/parity_dump_test.dart)
CSS_PARITY_OUT=/tmp/css-emphasis-shorthand /usr/bin/python3 tool/css_parity/compare.py
```

## 规范与浏览器取舍

[CSS Text Decoration 3 §3.1](https://www.w3.org/TR/css-text-decor-3/#text-emphasis-style-property)
规定仅填充关键字时横排圆形、竖排芝麻；本机 Chrome 的计算值检测结果却得到：

| 第 101 组声明 | Chrome 计算样式 | 本次引擎 |
| --- | --- | --- |
| `filled` | `dot` | `circle` |
| `open rgb(0, 102, 204)` | `open dot` | `open circle` |
| 父级 `open currentcolor`、子级绿色 | `open dot` / `rgb(0, 128, 0)` | `openCircle` / 子级绿色 |

检测结果数据位于 `/tmp/spectacular-css3-probe/browser_101-emphasis-shorthand.json`。
选择规范默认值而非复制此版本 Chrome 的默认形状；需要点形的书籍仍可显式写 `dot`。
[§3.2](https://www.w3.org/TR/css-text-decor-3/#text-emphasis-color-property)
规定 `currentcolor` 在继承后解算；
[§3.3](https://www.w3.org/TR/css-text-decor-3/#text-emphasis-property)
规定简写重置样式/颜色但保留位置。以上规则以官方规范原文与本机检测结果双重核对。

## 未处理风险与下一步

- 仍只支持既有六种形状；`double-circle/triangle`、自定义字符串与现代颜色语法
  未扩展。颜色复用原解析器，不宣称完整 CSS Color 兼容。
- 行内独立着重号、ruby 冲突、标记撑高行盒及竖排绘制仍未完善；本次竖排只验证
  默认样式计算，不宣称通过竖排视觉验收。
- 既有页首裁剪、根盒 padding、几何/样式失配及 spine 30 重放性能回退仍保留。
- 下一步优先核对并接通行内独立着重号样式，先补实际章节源与浏览器样例。
