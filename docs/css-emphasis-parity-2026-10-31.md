# 横排着重号：EPUB 与浏览器对照（2026-10-31）

## 范围与变更

继续用户第 2 项「对照浏览器修复现有 CSS 渲染」。基线为 `4ee4202`，不改解析、
布局、分页、页索引或阅读器页首裁剪策略，不新增依赖。只收敛横排着重号的明显视觉差异。

- `packages/reader_core/lib/paint/text_emphasis.dart`：六种已有样式使用正文半字号的
  Unicode 字形及 `ruby` 字体特性，不再用圆和斜线近似；复用现有字体回退链。
- 按字素簇取选区盒，不拆分代理对、组合字符；跳过标点、分隔符、控制及未分配字符，
  保留百分号、井号、与号等规范例外及其兼容形式。
- `page_renderer.dart` 在每个着重号块内只排版一次标记字形，所有行复用，绘制后释放。
  删除无调用的旧横排绘制函数；竖排沿用原实现。本次新增函数均不超过 40 行，
  不搬迁原有超长绘制模块。
- 增加 `100-emphasis-glyphs`：24px 的六种形状、17px 的下方标记和颜色长属性。
  段落内边距明确留出标记空间，隔离阅读器页首裁剪，未改动旧样例或比较容差。
- 覆盖矩阵跨过 99 后按数字排序，避免 100 排在 11 前面、编号范围仍显示到 99。

## 浏览器证据

Flutter 3.47.5 / Dart 3.13.4，Chrome 156.0.8078.74；350×800、DPR 1，双方加载
同一份内置思源宋体。引擎侧把用例打包为 EPUB，通过实际章节源分页并绘制。

| 用例 | 改前墨迹形状差 | 改后墨迹形状差 | 改后几何/样式失配 |
| --- | ---: | ---: | ---: |
| 100-emphasis-glyphs | 1.93% | 0.29% | 0 |
| 19-text-emphasis | 5.43% | 4.71% | 6 |
| 57-emphasis-style-longhand | 5.69% | 4.39% | 6 |
| 13-shadow-opacity | 0.24% | 0.21% | 0 |

- 97 组几何 JSON 全部与改前逐字节一致；只有上表 4 组 PNG 发生变化，其余 93 组
  PNG 逐字节一致。没有用改变页数、断行或正文位置换取标记对齐。
- 全量几何/样式失配仍为 **63 项、10 个用例**，未配对仍为 0；墨迹形状差超过 2%
  的用例仍为 8 个。**本次没有清零既有失配，也不将视觉改善计作几何修复。**
- 已人工检查 `side_100-emphasis-glyphs.png`：左侧浏览器、右侧引擎，字形、标点
  跳过与颜色接近；19/57 仍有整块纵向偏移。普通文本页首的 `trimTextEdges` 会回收
  行高留白，本轮保留这一阅读器策略，不通过修改对照工具消除差异。

产物只放在 `/tmp/spectacular-css2-before/` 与 `/tmp/spectacular-css2-after/`，
包括逐用例 JSON、PNG、`side_*.png` 和全量 `report.md`，不纳入 Git。

## 验证

- `bash tool/run_all.sh`：三包静态分析通过；核心 1268、UI 170、宿主 390 项通过，
  合计 **1828 项**，9 项按显式开关或环境条件跳过。CSS 对照已另外显式执行。
- 着重号 10 项测试通过；新增的标点排除、空心芝麻轮廓、字素簇 3 项在原绘制代码下
  失败，修复后通过。规范例外保留也有断言。测试额外加载宿主内置回退字体，避免
  精简测试字体缺少着重号字形造成伪失败；页顶留出注音区，不放宽像素/数量断言。
- `PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/tool/css_parity_coverage_test.py`：
  跨两位数/三位数编号的排序回归通过。覆盖矩阵生成保持幂等。
- 核心依赖边界、严格分析选项及边界脚本自测通过。
- 完整测试日志：`/tmp/spectacular-css2-validation.log`；旧绘制失败证据：
  `/tmp/spectacular-emphasis-red-final.log`。

复现当前版本（仓库根目录）：

```sh
CSS_PARITY_OUT=/tmp/css-emphasis-check node tool/css_parity/render_browser.mjs
(cd apps/reader_mobile && CSS_PARITY=1 CSS_PARITY_OUT=/tmp/css-emphasis-check \
  flutter test --no-pub test/css_parity/parity_dump_test.dart)
CSS_PARITY_OUT=/tmp/css-emphasis-check /usr/bin/python3 tool/css_parity/compare.py
```

## 未处理风险与下一步

- 本次只处理块级横排绘制。行内独立着重号样式、竖排、ruby 冲突、额外形状、标记
  撑高行盒及字体特殊度量不宣称完整支持；定位由字体度量解算，仍存在字体回退差异。
- 检查时另发现既有 `text-emphasis` 简写颜色/重置及仅 `filled/open` 的默认形状
  不完整；本轮不顺带改解析与层叠。新样例使用形状/颜色长属性隔离这个变量。
- 试验中观察到 `body` 顶部 padding 与浏览器不一致，未改宿主根盒布局；正式样例
  采用段落 padding 测试着重号，不代表根盒问题已解决。
- 原有页首裁剪、行盒/字体盒口径与 CJK 间距差异仍保留；上一轮 spine 30 索引重放
  性能回退未处理，本轮未做真机性能或长书内存验收。
- 下一步优先补着重号简写的层叠/重置用例，再修解析，避免颜色与形状只在长属性下正确。

依据：[CSS Text Decoration 3 §3.1](https://www.w3.org/TR/css-text-decor-3/#text-emphasis-style-property)
的字形、半字号与跳过规则；[§3.4](https://www.w3.org/TR/css-text-decor-3/#text-emphasis-position-property)
的位置要求。已读取规范并以本机 Chromium 截图验证，不把与单一字体接近等同于完整规范实现。
