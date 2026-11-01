# 正文两端对齐与标点空间挤压（2026-11-01）

基线 `5161d6a`。本次只增强横排普通正文，不修改 EPUB 解析器、原文、书签或
CFI 编码，不新增依赖、设置界面、中西文自动间距或符号纵向微调。
功能回归通过，但 **8ms 性能预算尚未通过**，不视为全部验收完成。

## 实现与维护边界

- `prose_spacing_defaults.dart` 在章节排版入口为普通 `p`、承载正文的叶子
  `div` 补 `justify` 与 `trim-both`。`Cascade` / `ComputedStyle` 仅增加
  两个属性的声明来源记录；祖先声明的左、中、右对齐以及显式
  `inherit` / `unset` / `initial` 均受保护，阅读器显式覆盖仍最后应用。
  标题、列表、表格、题注、导航、代码、诗歌语义、保留换行、竖排、RTL、
  浮动及已有特殊组件不新增正文默认。未修改全局 CSS 初始值或 UA 规则。
- `punctuation_spacing.dart` 复用既有全角标点集合，处理开—开、闭—闭和
  闭—开组合，按实际 run 的字体、字号计算；不扩展 `！？…`、破折号或半角
  符号。新增挤压仅使用实测生效的字体 `halt` 特性，不使用字形缩放、裁剪
  或 `hwid`。无 `halt` 时只保留旧的闭标点相邻兼容规则，不猜测边缘留白。
  显式开启或关闭 `halt` 不被二次覆盖；图片、原子盒、注音及基线变化为边界。
- `spaced_paragraph.dart` 先按挤压占宽求平台认可的断点，再由
  `cjk_justify.dart` 分配余量。压紧的组合内部锁定，英文词内、组合字符和
  emoji 不拆；默认不拉伸末行和硬换行。保留缩进、禁则、断词、省略号和
  标点悬挂，悬挂只使用尚未挤掉的句读宽。
- `text_spacing.dart` 定义不可变的 `LineSpacing` / `GlyphSpacing`：行内
  UTF-16 偏移、占宽调整、锁定间隙、两端对齐间隙、边缘处理和折叠尾空白。
  测量、绘制、光标、命中和选区消费同一结果；测量插入断点后重映射，浮动
  重排、分页与多列复制保留数据。尾空白保留原文下标，光标锚到可见行末，
  避免平台对零尺寸字形求光标时断言。
- 布局、绘制与章节分页缓存包含间距规则版本，分页索引 schema 从 4 升到 5；
  旧分页失效，书签无需迁移，颜色主题不触发布局重算。字体探针缓存有 1024
  项上限且不含颜色。保留既有浮动小字号图注修复；多列注音、图片切片改用
  重排后的真实原文范围，避免以新行号访问旧布局越界。

新逻辑按间距计划、平台断行和 span 应用拆分。既有大型章节布局/分页函数只
做必要接线，不整体重构；测试注册入口和单一墨迹扫描辅助保留线性结构，
不作为生产热路径。

## 功能验证

环境：macOS，同机 Flutter 3.47.5 / Dart 3.13.4；Flutter 测试与 CSS 导出串行。

| 验证 | 结果 |
| --- | --- |
| 三包静态分析 | `reader_core`、`reader_ui`、`reader_mobile` 均无问题 |
| 核心包全量 | 1374 项通过，4 项条件跳过 |
| UI 包全量 | 184 项通过 |
| 宿主包全量 | 547 项通过，5 项条件跳过 |
| 合计 | **2105 项通过，9 项条件跳过**；独立性能预算见下节 |
| 文档树不变量 | 13 本样本、5089 章，0 项违反 |
| 真书额外回归 | 4 项通过；《诸神愚戏》抽样 24 章、228 页、最多 11 页/章 |
| 真书打开与翻页 | 1541 章书打开、首页绘制、翻页通过；本轮首屏 324ms |
| 工程守卫 | 核心依赖边界、严格分析标志守卫、`git diff --check` 通过 |

新增核心 23 项、章节入口 8 项回归，覆盖纯中文、中英混排、连续及行边标点、
缩进窄屏、末行/硬换行、无间隙、实际 run 混合字号粗体颜色、上下标、
`space-all`、显式 `halt`、无特性字体降级、注音/图片/盒、浮动、多列、跨页、
断词、省略号、悬挂、缩放、标点光标/命中/选区、原文拼接与同位置 CFI、
主题缓存。可拉伸行的实际绘制占宽与目标宽仍使用 **0.5 逻辑像素**容差。
使用完整思源宋体 Regular/Bold，并逐个比较标点挤压前后墨迹包围盒尺寸，
不只依赖 Ahem 测试字体。原有样式快照全部通过，未更新基线。

复现命令（各包目录分别执行分析和全量测试，避免并行争抢）：

```sh
flutter analyze --no-pub
flutter test --no-pub -r expanded
# apps/reader_mobile 目录，额外启用真实 EPUB
REAL_EPUB=1 flutter test --no-pub test/real_book_sweep_test.dart \
  test/m1_integration_test.dart -r expanded
# 仓库根目录
bash tool/check_core_boundary.sh
bash tests/analysis/verify_strict_flags.sh
```

最终全量日志为 `/tmp/prose-final-reader_{core,ui,mobile}-{analyze,test}.log`，
真书日志 `/tmp/prose-final-real.log`。这些日志与截图不提交到仓库。

## CSS 与真实字形对照

新增 `tool/css_parity/cases/113-prose-spacing.json`；浏览器和引擎均使用仓库
完整思源宋体，不用缺失 `halt` 的子集字体证明边缘挤压。已人工查看并排图，
标点无字形压扁或裁切，仍不宣称与 Chrome 逐像素一致。

- 原始 110 组对照：514 项失配，涉及 66 组，另有 1 项未配对。阅读器现在
  默认 `justify` / `trim-both`，Chrome 默认仍为 `start`，不能直接将全部
  增量解释为 CSS 回归，也不能把这份报告称为通过。
- 为隔离作者样式保护，在改前、改后临时副本的 109 组旧用例 CSS 最前面
  加入 `body { text-align: start; text-spacing-trim: trim-adjacent; }`，让两边
  都有相同作者声明，再复用同一浏览器产物。109 份引擎几何 JSON **逐字节
  相同**，107 张引擎截图逐字节相同；两边均为 **55 项既有失配 / 5 组**，
  另有 1 项未配对。仅 `05-vertical-align` 与 `17-text-align-last` 截图变化，
  对应分段绘制基线及不再给英文词内/折叠尾空白分配字距，已人工检查。
  未修改提交用例、比较工具或容差。
- 新增 113 组仍有 15 项工具失配、墨迹形状差约 6.67%。包含混合字号行高、
  断行差异及比较器把上下标子 span 配到父段落的问题；不掩盖差异，不把
  本次明确子集描述为完整 CSS Text 4 兼容。

产物目录 `/tmp/prose-css-after`、`/tmp/prose-css-authored-before` 和
`/tmp/prose-css-authored-after`，`side_*.png` 左浏览器、右引擎。
109 组隔离报告使用 `compare.py` 的用例位置参数排除新增 113，避免将改前
缺少新用例的数据误计为回归。常规复现：

```sh
CSS_PARITY_OUT=/tmp/prose-css node tool/css_parity/render_browser.mjs
(cd apps/reader_mobile && CSS_PARITY=1 CSS_PARITY_OUT=/tmp/prose-css \
  flutter test --no-pub test/css_parity/parity_dump_test.dart)
CSS_PARITY_OUT=/tmp/prose-css /usr/bin/python3 tool/css_parity/compare.py
```

## 性能预算：未通过

保留原有 8ms / 4ms / 1000ms 门槛；没有通过改容差或更新预算文档掩盖失败。
用户提供的改前结果为 8.408 / 0.007 / 39.599ms。最终同机、同测试、相邻
交替两轮结果如下，单位 ms；第三列指标实际为 100 段布局加分页，并非 GPU
绘制时间。

| 轮次 | 20 段布局加分页 | 缓存命中 | 100 段章节构建 |
| --- | ---: | ---: | ---: |
| 改前 1 | 8.641 | 0.007 | 41.176 |
| 改后 1 | 9.059 | 0.010 | 43.688 |
| 改前 2 | 8.629 | 0.006 | 40.490 |
| 改后 2 | 9.489 | 0.010 | 43.301 |

四次预算均因 20 段构建超过 8ms 退出 1。原实现已超预算，本次仍新增约
0.418–0.860ms，不能把全部失败归因于旧问题。已采用普通 BMP 字簇快路径、
有限字体探针缓存、无调整快路径和局部断行窗口；仍需性能专项优化，
不据此推算移动端耗时。日志 `/tmp/prose-final-budget-{before,after}-{1,2}.log`。

```sh
# packages/reader_core 目录，单独运行，不能与全量测试并行
BUDGET_RUN=1 flutter test --no-pub test/bench/budget_test.dart -r expanded
```

## 未处理风险与下一步

- 不支持 `halt` 的未知字体保留部分边缘留白。生产嵌入字体使用内容寻址的
  引擎字体名并等待注册；若外部同名字体在进程内动态替换，探针缓存尚无
  额外的字体注册代数失效机制。
- 缺乏语义标记的诗歌或特殊段落不能保证自动识别；CSS 对照剩余差异和既有
  多列 CFI 总体限制未在本次消除。不把多列间距复制测试等同于所有多列
  CFI 已验收。
- 未进行真机视觉、移动端性能或移动安装包构建验收。建议下一步优先做
  8ms 热路径性能专项，并在目标移动设备检查真实 EPUB、浮动和混合字号。

规则依据为 [CSS Text 4 标点间距明确子集](https://www.w3.org/TR/css-text-4/#text-spacing-trim-property)。
此前查阅的[方正文章](https://mp.weixin.qq.com/s/Z-CDNLNuisQuSQwGsgpssA)及
[方正官网服务入口](https://www.foundertype.com/index.php/FontofMade/index)未核验到
可直接集成的公开引擎 SDK、接口文档、源码、完整规则表或可复现量化性能。
本实现不依赖方正客户端，不宣称复刻方正引擎。
