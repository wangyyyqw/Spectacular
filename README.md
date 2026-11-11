# Spectacular Reader

Flutter 原生 EPUB 阅读器，正文渲染不使用 WebView。技术方案见 [方案/技术方案.md](方案/技术方案.md)，开发任务见 [方案/开发方案.md](方案/开发方案.md)。

## EPUB 引擎架构

正文渲染走「解析 → 样式 → 布局 → 分页 → 自绘」全自研管线，数据流与模块对应如下：

```
EPUB 字节
  │
  ├─ epub/      ZIP 读取（四档诊断恢复）→ OCF 校验 → container.xml（损坏时回退扫描 OPF）
  │             → OPF/spine → 目录回退链（NCX↔NAV↔spine 兜底，绝不空目录）→ 资源索引（七级查找）
  │
  ├─ parser/    双路径解析：严格 XML 校验闸门（保留 epub:type 语义），失败自动回退
  │             html5lib 容错并记诊断（sourceSpan 偏移是 CFI 坐标基础）
  │             → display 分派建块树 → 行内聚合（空白/硬换行/图片占位）→ CFI 解析期绑定
  │
  ├─ css/       层叠三源：UA 默认表（对照 Reeden 134 规则基线落地，注释即规范出处）+ 作者样式 + 内联
  │             → 选择器（四元组特异性）/层叠/继承 → ComputedStyle（一次算完不可变）
  │             → 阅读器覆盖层（reader origin）+ 内部契约层（-reader-* 仅 UA/阅读器可用）
  │
  ├─ layout/    断行（引擎断行 + 3em 宽度下限 + 避头尾禁则）→ 行切分（leadingDistribution: even）
  │             → 对齐（CJK gap 两端对齐 / 西文空格拉伸 / 标点悬挂 / 挤压 / 中西文自动间距）
  │             → 盒模型（box-sizing / margin 折叠与穿透折叠 / 负 margin 页根钳制）
  │             → 分页状态机（2px 容差 / break-inside / 图+题注整组不可切 / 20000 页截断）
  │             → 页索引持久化（RPI1 魔数 + schemaVersion + 校验和，冷启动边界重放）
  │
  ├─ paint/     固定阶段绘制：页背景 → 块背景 → 块边框 → 文本 → 装饰 → 选区
  │             + 段落缓存（布局指纹失效）+ 图片降采样缓存（href, 显示宽, DPR）
  │
  └─ position/  CFI 解析/构造/比较（唯一坐标：进度、书签、高亮全存 CFI 不存页码）
                + 三级重定位：区间直查 → 原文+上下文指纹消歧 → 章内比例兜底

reader_ui/      ReaderView / ReaderPage / ReaderSession + 虚拟页窗口（跨章连续页码）
                + 页缓存（±2 预取、LRU）+ 翻页手势 + 主题
apps/           章节源（document/styles/pagination 三层缓存 + 失效矩阵：切主题零重排）
                + 存储（drift / 进度落盘）+ 文件/TTS/诊断日志
```

### 关键机制

- **中文排版**：引擎断行（S4 实测定案）+ 避头尾禁则 + `text-justify` 四值 + `text-align-last` 末行对齐 + 标点悬挂（`hanging-punctuation`）/ 挤压（`text-spacing-trim`，逐对字体守卫）/ 中西文自动间距（`text-autospace`，默认关闭——「书里有什么就是什么」）。三类字距在同一字符上代数叠加。
- **行高与基线**：`leadingDistribution: even`（S1 结论）+ 无单位行高因子按子元素字号重算 + 上下标借行距（墨迹越出行盒才撑高，脚注编号不跳行距）。
- **盒模型**：margin 折叠全规则（正正/正负/负负/首末逸出/嵌套）+ 零高空容器穿透折叠 + body 首元素负 margin 钳制 + `flow-root` BFC 阻断规则。
- **定位与标注**：CFI 与文档树在解析期绑定；重排后按 CFI 恢复位置（行级锚点偏差 0 行）；标注失效时走三级重定位并置灰保留（不删除）。
- **缓存与性能**：排版缓存三层（document/styles/pagination），各层键只含「影响该层的最小变量集」（颜色不进排版键——切主题零重排）；段落布局缓存 + 页索引重放跳过分页状态机；性能预算见技术方案 §11.2 与验收记录指标表。
- **容错与防护**：43 个稳定诊断码（code × category × severity + detail/offset，防漂移单测）；解析双路径；ZIP 四档分档（坏条目跳过、局部头偏移修补恢复）；压力防护四道（DOM 深度 500 / 属性 65536 / 正则 1s 隔离预算 / 单章 20000 页截断）。
- **测试**：按 UI、CSS、布局、绘制、资源等职责运行，使用 `python3 tool/run_tests.py --list` 查看当前分类清单；另有 10 本样式快照回归（5 本地 + 5 生成）及 77 条排版规则编号矩阵（规则 ↔ 用例一一对应，见验收记录 `P7-规则回归矩阵.md`）。

### 架构边界（设计即约束）

- `reader_core` 禁止平台插件与宿主包依赖，由 `tool/check_core_boundary.sh` 强制——引擎可在桌面/单测环境完整运行。
- 任何持久化数据不存页面坐标（只有 CFI 与字符偏移）；页码是重排后的派生量。
- 原书不改写：导入与解析全部内存规范化（对照阅微的导入期回写方案）。
- 架构骨架参考阅微（基于静态分析，仅参考架构与算法）；规格级补充来自 Reeden 2.0.0 静态分析（`参考/reeden/`，仅采用规格结论，不复用实现代码），引用纪律见 [docs/开发约定.md](docs/开发约定.md) §6.1。

## 后续扩展路线

任务定义与勾选状态见 [方案/开发方案.md](方案/开发方案.md)（232 项，进度 126/232）。当前 54.3%，下一步进入 **P3 主线**。

### 主线阶段

| 阶段 | 内容 | 状态 |
|---|---|---|
| P3 M2 资源、浮动与容错 | 内嵌字体（@font-face/多字重/解混淆/中文别名）、图片管线（降采样/满屏/预览）、浮动绕排（occupiedList/占位）、表格（两遍测量/colspan/跨页）、page-break 完整规则、破损书五级可读性 | 未开始（30 项） |
| P4 M3 业务闭环 | drift 表结构与书库、进度/目录/书签、选区与高亮笔记（消费三级重定位）、2-gram 全文搜索、设置面板、墨水屏、无障碍、性能埋点 | 未开始（34 项） |
| P5 M4 高级排版 | ruby 注音、text-emphasis、竖排（坐标系/逐字定位/标点旋转/翻页方向）、逻辑属性族（竖排前置）、中英混排分段 | 未开始（20 项） |
| P6 M5 打磨与发布 | 滚动模式、TTS（暂缓，待真机引擎可用）、CFI 导入导出、异常兜底、启动优化、签名与商店素材 | 未开始（20 项） |
| P2 M1 排版质量 | 剩 P2-37（关键 P1 属性抽样，候选清单见属性矩阵 §7）与 P2-38（里程碑评审） | 36/38 |

### P7 挂账清单（已完成增强的遗留项，均有责任任务）

| 遗留项 | 去向 |
|---|---|
| `line-break` 属性「照书」映射 | P3 CSS 扩展 |
| 行内 run 样式接线（b/em/code 等；挤压/间距扩展到含 run 行） | P3/P4 作者样式引擎 |
| 真斜体文件选面补验（合成倾斜已验证） | P3-02 |
| 浮动容器内 margin 折叠边界 | P3-12 |
| `div[align]` 属性居中（需属性选择器） | P3 |
| 列表标记绘制/嵌套类型/`ol[reversed]` | P3-23 |
| 表格默认边框与 `table[border]` 表现属性 | P3-17～21 |
| `p` 默认段距启用（UA 表已收） | P4-21 |
| 悬挂/挤压/自动间距的 reader 级开关（当前 CSS 驱动） | P4-21 |
| 逻辑属性族（margin/padding/inset-inline-*） | P5-08 竖排前置 |
| `text-orientation`/`text-combine-upright` 消费 | P5-10 |
| 首字下沉多行对齐（当前单行近似） | P3 浮动布局 |

## 开发阅读路径（推荐顺序）

1. 先读本页：了解仓库边界、引擎架构与扩展路线。
2. 再读 [方案/技术方案.md](方案/技术方案.md)：确认设计目标、架构边界和各模块职责。
3. 然后看 [方案/开发方案.md](方案/开发方案.md)：把大设计拆成阶段任务和验收标准。
4. 执行阶段任务时，进入对应的 [方案/开发方案](方案/开发方案) 子文件，按复选框逐项推进。
5. 完成后补充验收记录与交接文档：见 [方案/交接文档.md](方案/交接文档.md)（项目现状速览 + 逐任务记录）与 [方案/验收记录](方案/验收记录/README.md)（99 个文件分类索引）。
6. 涉及 Reeden 素材时，先读 [docs/开发约定.md](docs/开发约定.md) §6.1「Reeden 资料引用纪律」与 [方案/技术方案.md](方案/技术方案.md) §2.2 证据索引，报告在 [参考/reeden/reports/](参考/reeden/reports/)；增强类任务在 [方案/开发方案/P7-Reeden增强补充.md](方案/开发方案/P7-Reeden增强补充.md)。

这条路径能把“为什么做/怎么做/怎么验收”三件事串起来，减少来回翻文档造成的上下文切换。

## 仓库结构

```
packages/reader_core/   EPUB 引擎（零平台插件依赖）：epub 解包 / parser 文档树 / css 层叠 /
                        layout 断行分页 / paint 绘制缓存 / position CFI 与重定位 / text 工具
packages/reader_ui/     阅读视图：ReaderView/ReaderPage/Session、虚拟页窗口、页缓存、手势、主题
apps/reader_mobile/     iOS / Android / macOS 壳：章节源（三层缓存）、存储（drift/进度）、TTS、诊断
方案/                   技术方案（v1.4）、开发方案（232 项按阶段拆分）、验收记录（含 README 索引）、
                        交接文档（项目现状速览 + 逐任务记录）、spike 实验结论
docs/                   开发约定（分支/测试/门禁/Reeden 引用纪律）
参考/                   参考工程与静态分析：阅微静态分析资料（架构骨架）、reeden/（排版引擎规格报告，
                        仅采用规格结论，不复用实现代码）
tool/                   按改动测试 / 显式全量 / 边界检查 / 进度同步
tests/                  跨包测试与校验脚本（strict flags / 边界拦截）
test_corpus/            本地测试样本库（不入库，需自行准备；另有 5 本生成样本在测试内直构）
test_fonts/             OFL 测试字体（思源宋体 Regular/Bold）
```

## 常用命令

```bash
# 日常：按 Git 改动运行相关测试，复用本地依赖缓存
python3 tool/run_tests.py

# 指定职责；影响多个职责时组合
python3 tool/run_tests.py ui
python3 tool/run_tests.py css layout

# 预览选择范围与执行命令、校验分类索引
python3 tool/run_tests.py --changed --dry-run
python3 tool/run_tests.py --check

# 显式全量：三包 analyze + test 及 Python 工具回归
bash tool/run_all.sh

# 运行移动端壳（macOS 桌面可直接预览）
cd apps/reader_mobile && flutter run -d macos

# 样式回归（基线更新需有意变更并逐条归因）
cd packages/reader_core && flutter test --no-pub test/snapshot/style_regression_test.dart
```

## 阅读与提交门禁

- `reader_core` 不得依赖平台插件与宿主包，由 `tool/check_core_boundary.sh` 强制（CI 已移除，本地门禁为准）。
- 任务进度以《开发方案》阶段文件中的复选框为准，勾选后运行 `perl tool/render_plan.pl` 同步总览。
- 提交前运行 `python3 tool/run_tests.py --check`，确认 `--changed --dry-run` 的范围后执行相关测试；改 UI 选 `ui`，改 CSS 选 `css`，跨职责组合分类。全量验证通过 `run_all.sh` 显式调用。
- 核心依赖边界与分析规则改变时分别执行对应守卫；[测试分类规则](docs/测试分类.md) 说明命令、自动选择边界与真机范围。
- 行为变更在同一提交同步旧断言、夹具和分类索引；涉及渲染/分页/解析必须有回归或快照，基线变更逐条归因。纯文档变更在提交信息里说明跳过测试的理由。
- 交接记录见 [方案/交接文档.md](方案/交接文档.md)。

## 适合的阅读方式

- 只想理解架构：本页「EPUB 引擎架构」→ [方案/技术方案.md](方案/技术方案.md)
- 只想推进实现：[方案/开发方案.md](方案/开发方案.md) → 对应阶段文件 → 执行测试
- 只想接手现状：[方案/交接文档.md](方案/交接文档.md)（速览 + 逐任务记录）→ [方案/验收记录/README.md](方案/验收记录/README.md)（证据索引）
