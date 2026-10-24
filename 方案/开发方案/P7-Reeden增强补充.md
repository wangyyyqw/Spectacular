# P7 Reeden 增强补充（32 项 / 102h）

> 返回 [开发方案.md](../开发方案.md) ｜ 上一阶段：[P6 M5 打磨与发布](P6-M5-打磨与发布.md) ｜ 下一阶段：无（末阶段）
> 里程碑：MS-P7 Reeden 增强闭环，完成条件见 [主文档 §1.2](../开发方案.md#1-进度看板与里程碑)。
> 定位：本阶段**不新增产品能力边界**，只把 Reeden 2.0.0 逆向分析（[参考/reeden](../../参考/reeden/reports/)，证据索引见[技术方案 §2.2](../技术方案.md)）中已验证的规格，增强到**已完成的 P0～P2 成果**上。架构骨架仍以阅微 + 本项目实验结论为准（技术方案 §2「Reeden 的角色」三条纪律）。
> 执行时机：P7.1～P7.2（规格回填）建议在 P3 大规模开发前完成，避免新代码建立在旧规格上；其余模块可与 P3～P6 穿插，无强制先后。
> 规则：勾选任务后运行 `perl tool/render_plan.pl` 同步主文档总览与进度；字段口径见主文档 §0.3～§0.4。

> 进度：32 / 32 项 · 102h / 102h（100%）

---

### P7.1 规格回填与基线

- [x] **P7-01 Reeden 资料引用规范落地** ｜ 2h
  - 目标：把 参考/reeden 分析工程纳入仓库文档体系：阅读路径、引用格式（报告路径 + 章节）、引用纪律成文
  - 产出：`docs/开发约定.md`「Reeden 资料引用」节、README 阅读路径补一行
  - 依赖：无
  - 验收：引用规范成文，至少覆盖三条纪律（只借结论不复制代码、区分〔实测〕/〔建议〕、与既有实验结论冲突时以本项目实验为准）；README 与开发约定均可导航到 `参考/reeden/reports/`
  - 参考：[参考/reeden/reports/00-brief.md](../../参考/reeden/reports/00-brief.md)（分析手册与输出规范）；[技术方案 §2](../技术方案.md)「Reeden 的角色」（接入纪律）

- [x] **P7-02 技术方案 Reeden 回填核对与冲突清单** ｜ 3h
  - 目标：逐条核对技术方案 v1.4 新增的 §2.2 索引与 §82.7 借鉴清单，产出冲突处置清单（每处冲突给出「维持既有 / 采纳 Reeden / 搁置待实测」结论与理由）
  - 产出：`方案/验收记录/P7-技术方案回填核对.md`
  - 依赖：P7-01
  - 验收：清单覆盖 §82.7 三张表的全部条目；六处「仅作记录」冲突各有不采纳理由复核；核对记录与技术方案交叉引用一致
  - 参考：[技术方案 §82.7](../技术方案.md)（三级借鉴清单）；[参考/reeden/reports/REEDEN-APK-分析报告.md](../../参考/reeden/reports/REEDEN-APK-分析报告.md)（主报告）

- [x] **P7-03 UA 样式表对照与扩充落地** ｜ 4h
  - 目标：以 Reeden 134 规则 UA 表为基线扩充本项目 §73 默认表，逐条移植并注明规范出处：h1–h6 `break-after:avoid`（标题避页底）、列表嵌套类型 disc→circle→square、`ol[reversed]` 反序、`sub/sup` 行高借用、ruby `rt` 缩进归零与 50% 字号、`noscript{display:none!important}`、表单控件静态尺寸、`center/div[align]` 居中行为、裸表格默认边框预期
  - 产出：`packages/reader_core` UA 默认表扩充 + `方案/验收记录/P7-UA表对照.md`（逐条差异与取舍）
  - 依赖：P2-13
  - 验收：每条新增规则带规范出处注释；5 本样本快照回归无意外差异（有差异必须逐条归因）；对照表覆盖 630 号报告 §2 的六处刻意差异
  - 参考：[参考/reeden/reports/630-ua-stylesheet.md](../../参考/reeden/reports/630-ua-stylesheet.md)（134 规则与六处差异）；[技术方案 §73](../技术方案.md)（UA 默认表现状）

- [x] **P7-04 CSS 属性白名单对照复核** ｜ 3h
  - 目标：把 Reeden 358 项属性识别表与本项目 91 项分级逐项对照，识别「中文书高频但本项目缺失」的属性（重点评估：逻辑属性族、`:is/:where/:has`、列表式 `:not`、`box-decoration-break`、`text-autospace`、`orphans/widows`、`break-*`），给出纳入 P1 限定 / 维持不做的结论
  - 产出：属性对照矩阵与增补结论（并入 P2-18 的属性矩阵文档）
  - 依赖：P2-18
  - 验收：91 项之外至少评估 15 个候选属性，每项有「纳入/不纳入 + 理由 + 触发样本」；结论同步回技术方案 §23
  - 参考：[参考/reeden/reports/510-spec-typeset.md](../../参考/reeden/reports/510-spec-typeset.md) §1（CSS 子集两档与 358 项表）；[技术方案 §23](../技术方案.md)（分级现状）

- [x] **P7-05 诊断码体系落地（对齐 §82.4）** ｜ 4h
  - 目标：把技术方案 §82.4 的 EpubError 体系实现为 reader_core 公共 API，形态对齐 Reeden「30 个稳定码 + severity(info/warning/error) + offset，作为公共 API 输出、诊断随文档缓存」的做法；把现有解析/导入/排版错误全部映射进码表
  - 产出：`packages/reader_core/lib/epub/epub_exception.dart` 扩展、码表文档、单测
  - 依赖：P1-05
  - 验收：现有错误路径（§12 容错表 + §55.3 拒绝路径）全部有稳定 code；code 不随文案变化（本地化只改 message）；码表有单测防漂移
  - 参考：[参考/reeden/reports/500-spec-parse.md](../../参考/reeden/reports/500-spec-parse.md) §0-#8（30 诊断码 API）；[技术方案 §82.4](../技术方案.md)（错误码体系设计）

- [x] **P7-06 规则编号回归矩阵** ｜ 4h
  - 目标：参照 Reeden「规则编号驱动 + 逐条回归」的组织方式（内部文档章节 + 条目号体系），给本项目已有排版规则建立编号目录（断行/对齐/行高/分页/容错各一节），并让每条规则至少对应一个快照或单测用例
  - 产出：`方案/验收记录/P7-规则回归矩阵.md`、用例命名与规则编号对齐
  - 依赖：P2-25
  - 验收：矩阵覆盖 P1-22～P2-34 落地的全部规则条目，每条规则有编号、描述、用例文件与用例名；无对应用例的规则列为缺口
  - 参考：[参考/reeden/reports/150-epub-typography.md](../../参考/reeden/reports/150-epub-typography.md) §0-#2（规则编号体系）；[技术方案 §13.2](../技术方案.md)（快照回归）

### P7.2 P0 风险验证增强

- [x] **P7-07 S4 禁则结论与 D22 场景对照复核** ｜ 2h
  - 目标：用 Reeden D22 strict 禁则的行为描述（句读/闭口符不在行首、开口符不在行尾、作者写了 `line-break` 就照书）复核 S4 实测的 10 场景与 3em 宽度兜底的覆盖面，缺的场景补用例
  - 产出：对照记录 + 新增断言用例（`packages/reader_core/test/layout/`）
  - 依赖：P0-12
  - 验收：D22 场景清单逐条有本项目断言；发现的未覆盖项转为缺陷登记或新规则编号（进 P7-06 矩阵）；S4 结论本身维持不变
  - 参考：[参考/reeden/reports/150-epub-typography.md](../../参考/reeden/reports/150-epub-typography.md) §0-#3（D22）；[方案/spike/s4-result.md](../spike/s4-result.md)（S4 实测）

- [x] **P7-08 S5 字重结论补测 italic 维度** ｜ 2h
  - 目标：S5 只实测了 regular+bold；对照 Reeden 字体注册模型（缓存键 family→(weight, italic)→字形、合成粗斜体路径）补测 regular/italic/bold-italic 组合，确认 `fontStyle` 也能按 family 正确选中
  - 产出：S5 补测记录（`方案/spike/` 或验收记录）
  - 依赖：P0-08
  - 验收：italic 与 bold-italic 有实测结论；任一组合不成立时登记「拆 family 映射」后备方案并评估工作量
  - 参考：[参考/reeden/reports/550-perf-font-config.md](../../参考/reeden/reports/550-perf-font-config.md) §3（face 注册与缓存键）；[技术方案 §28.2](../技术方案.md)（S5 方案 A/B）

- [x] **P7-09 sub/sup 借行距规则落地** ｜ 2h
  - 目标：实现「上下标先借已有行距、超出才撑高行盒」（borrow-leading）替代当前按最大字号撑高，消除脚注编号 `<sup><a>[1]</a></sup>` 造成的行距跳变
  - 产出：行高计算分支 + 用例（含脚注编号样本快照）
  - 依赖：P2-04
  - 验收：含上标脚注的样本行高无跳变（相邻行行高差 <0.5px）；极端大字号上标仍能正确撑高；技术方案 §25.3 坑 1 标记为已解决
  - 参考：[参考/reeden/reports/630-ua-stylesheet.md](../../参考/reeden/reports/630-ua-stylesheet.md) §2-#3（N5 借行距规则原文）；[技术方案 §25.3](../技术方案.md)（脚注坑）

- [x] **P7-10 性能指标与预算总表对齐** ｜ 3h
  - 目标：对照 Reeden 12 类观测面与 40+ 项阈值总表，补齐本项目性能预算缺口（章节首次排版耗时、缓存命中率、跨章跳转耗时、内存水位、快照回归耗时），并给每项指标定阈值与采集方式
  - 产出：技术方案 §11.2 预算表扩充、`方案/验收记录/P7-性能指标表.md`
  - 依赖：P2-28
  - 验收：每项新指标有阈值、采集方式、超标动作三要素；P2-28 已有指标不回退；与 P4-31 埋点点位能对上
  - 参考：[参考/reeden/reports/570-perf-metrics-budgets.md](../../参考/reeden/reports/570-perf-metrics-budgets.md)（指标/预算总表）；[技术方案 §11.2](../技术方案.md)（预算现状）

### P7.3 P1 链路增强

- [x] **P7-11 解析器双路径（严格 XML → 容错回退）** ｜ 4h
  - 目标：合法 XHTML 走严格解析（保留命名空间与 `epub:type` 语义），解析失败自动回退 html 容错解析；所用路径记诊断，并作为缓存键的一部分（回读缓存时必须知道当时用的哪条路径）
  - 产出：`parser/document_parser.dart` 双路径分支 + 诊断 + 用例
  - 依赖：P1-14
  - 验收：命名空间完好的书保留 `epub:type`（脚注/pagebreak 语义可用）；标签不闭合的书可打开并带降级诊断；两条路径产出的缓存键可区分
  - 参考：[参考/reeden/reports/500-spec-parse.md](../../参考/reeden/reports/500-spec-parse.md) §1（双路径证据与动机）；[技术方案 §12](../技术方案.md)（容错表）

- [x] **P7-12 容器与 OPF 回退扫描** ｜ 3h
  - 目标：container.xml 缺失/损坏时按候选路径扫描兜底（`OEBPS/content.opf`、`content.opf` 等）；manifest 项缺 media-type 时按扩展名推断；两者均记诊断不静默
  - 产出：`epub/container.dart`、`epub/opf.dart` 回退分支 + 用例
  - 依赖：P1-01、P1-02
  - 验收：container.xml 损坏样本可打开并带 containerFallback 诊断；media-type 推断样本不误判（xml/css/ncx/nav 四类资源归类正确）
  - 参考：[参考/reeden/reports/500-spec-parse.md](../../参考/reeden/reports/500-spec-parse.md) §1.1（Fallback: found OEBPS/content.opf）；[技术方案 §12](../技术方案.md)（容错表）

- [x] **P7-13 目录健壮性补强** ｜ 3h
  - 目标：显式处理两类坏目录：目录项 href 不在 spine（tocTargetOutsideSpine，跳转时降级到最近章）、spine 全部非 linear（回退全 spine 包含非 linear 项）；避免静默丢目录项或空目录
  - 产出：`epub/toc.dart` 校验与降级 + 用例
  - 依赖：P1-07
  - 验收：构造的两类坏目录样本有明确降级路径与诊断；§35.2 回退链四步全部有用例覆盖
  - 参考：[参考/reeden/reports/560-perf-toc-progress.md](../../参考/reeden/reports/560-perf-toc-progress.md) §2（TOC 诊断枚举族）；[技术方案 §35.2](../技术方案.md)（回退链）

- [x] **P7-14 位置锚点三级解析与指纹消歧** ｜ 4h
  - 目标：补强 CFI 失效后的兜底链为三级：字符区间直查 → quote + 上下文指纹重映射（前后文哈希消歧，多命中取离原位置最近）→ 章内比例兜底；失败分类（未命中/歧义/上下文不符）对齐 §30.4
  - 产出：`packages/reader_core/lib/position/relocator.dart` + 用例（含重复文本样本）
  - 依赖：P1-13
  - 验收：CFI 失效样本按三级顺序命中；同一段文字出现两次的样本指纹消歧成功；三级全失败时标注置灰保留（不删除）
  - 参考：[参考/reeden/reports/560-perf-toc-progress.md](../../参考/reeden/reports/560-perf-toc-progress.md) §1.4（Locator v3 与三级解析顺序）；[技术方案 §30.4](../技术方案.md)（重排后重定位）

- [x] **P7-15 ZIP 诊断分档** ｜ 3h
  - 目标：ArchiveReader 失败分类细化为四档：条目截断 / 局部头损坏（可扫描恢复）/ 文件名编码错位（legacy 编码重试）/ EOCD 缺失（中心目录扫描），分别对应修复策略与拒绝路径
  - 产出：`epub/archive_reader.dart` 错误分档 + 用例（四类坏 ZIP 样本）
  - 依赖：P1-03
  - 验收：四类坏样本各归其档；可恢复档（局部头错位）能扫描恢复并记诊断；只有不可救档走 L4 拒绝
  - 参考：[参考/reeden/reports/500-spec-parse.md](../../参考/reeden/reports/500-spec-parse.md) §0-#1（zip 四诊断档）；[技术方案 §55](../技术方案.md)（破损分级）

- [x] **P7-16 长章与恶意内容防护** ｜ 4h
  - 目标：落地四道防线：DOM 嵌套深度上限、SVG DoS 防护（尺寸与嵌套上限）、用户可配置正则的 1 秒超时守卫、单章排版 20000 页截断（渐进提示不中断）
  - 产出：防护逻辑 + 极端样本用例（超深嵌套/超大 SVG/超长章）
  - 依赖：P1-25
  - 验收：四类恶意样本不崩溃、不无限卡死（每类有超时断言）；截断有用户可见提示与诊断码
  - 参考：[参考/reeden/reports/180-epub-perf-compat.md](../../参考/reeden/reports/180-epub-perf-compat.md)（压力防护清单）；[技术方案 §12](../技术方案.md)（单章超大分段）

### P7.4 P2 排版增强

- [x] **P7-17 阅读器私有契约层** ｜ 3h
  - 目标：定义 UA/阅读器层专用的私有伪类与属性命名空间（如 `:-reader-source(...)`），解析器限制其只能出现在 UA 与阅读器覆盖层 origin，作者 CSS 使用时记诊断拒绝——为「应用通过 CSS 向引擎表达意图」预留通道
  - 产出：css 解析器 origin 限制 + 契约文档（命名空间清单）
  - 依赖：P2-22
  - 验收：作者 CSS 使用私有伪类被诊断拒绝且不影响其余规则；UA 层正常使用；现有覆盖层（§7.5）迁移到该机制或说明不迁移的理由
  - 参考：[参考/reeden/reports/630-ua-stylesheet.md](../../参考/reeden/reports/630-ua-stylesheet.md) §3（私有契约层与诊断限制）；[技术方案 §7.5](../技术方案.md)（覆盖层顺序）

- [x] **P7-18 标点悬挂（hanging punctuation）** ｜ 4h
  - 目标：两端对齐行尾的句号/逗号悬挂到版心右缘外（不压缩字形、不留空隙），作为独立开关且书内显式 CSS 优先（作者未禁止时才启用）
  - 产出：`layout/cjk_justify.dart` 悬挂分支 + 快照用例
  - 依赖：P2-20
  - 验收：两端对齐样本行尾句读悬挂后右缘对齐误差 <1px；开关关闭输出与现状逐像素一致；末行与硬换行行不悬挂
  - 参考：[参考/reeden/reports/150-epub-typography.md](../../参考/reeden/reports/150-epub-typography.md) §0-#5（悬挂行为文案）；[技术方案 §8.4](../技术方案.md)（gap 对齐基础）

- [x] **P7-19 标点挤压（punctuation compression）** ｜ 4h
  - 目标：相邻标点挤掉中间的整格空白（标点贴汉字一侧的留白保留）；按字体实际字形判断，字体不支持时自动跳过整条规则
  - 产出：挤压分支 + 快照用例（密集标点样本「他说：『好。』」类）
  - 依赖：P7-18
  - 验收：密集标点样本挤压后行宽与行内无重叠；测试字体不支持时回退现状并有诊断；与悬挂组合时行为可预期
  - 参考：[参考/reeden/reports/150-epub-typography.md](../../参考/reeden/reports/150-epub-typography.md) §0-#5（挤压行为文案）；[技术方案 §8.4](../技术方案.md)（间隙规则）

- [x] **P7-20 中西文间距与空格整理** ｜ 4h
  - 目标：两个独立开关：① 中西文之间自动间距（text-autospace 思路，只调视觉间距不改字符）；② 书内空格整理（半角标点转全角），整理必须遵守白名单豁免——不改 `3.14` 数字、不改 `～=-/` 等符号、不触发换行变化
  - 产出：`text/script_fallback.dart` 间距分支 + 整理规则表 + 用例
  - 依赖：P7-19
  - 验收：豁免白名单有逐条单测（数字/符号/多个空格）；两开关均关闭时输出与原文逐字符一致；整理不改变分页结果（同设置页数不变）
  - 参考：[参考/reeden/reports/150-epub-typography.md](../../参考/reeden/reports/150-epub-typography.md) §0-#5（空格整理两条行为文案）；[技术方案 §38.2](../技术方案.md)（混排规则）

- [x] **P7-21 text-justify 四值与 text-align-last** ｜ 3h
  - 目标：解析 `text-justify` 的 inter-word / inter-character / distribute / justify-all 四值并映射到现有 gap 对齐（inter-character 与 distribute 走全 gap 分配、inter-word 只拉伸空格）；补 `text-align-last` 控制末行对齐
  - 产出：属性解析与对齐映射 + 用例
  - 依赖：P2-20
  - 验收：四值样本行为可区分（同一章切换四值产生四种行宽分布）；`text-align-last: justify` 时末行参与拉伸；未设置时行为与现状一致
  - 参考：[参考/reeden/reports/150-epub-typography.md](../../参考/reeden/reports/150-epub-typography.md) §0-#6（四值全解析证据）；[技术方案 §8.4](../技术方案.md)（末行不拉伸例外）

- [x] **P7-22 页索引持久化（RPI 式）** ｜ 4h
  - 目标：分页结果序列化为可落盘的页索引：页起点数组 + 每页偏移信息 + schema 版本号（对齐 Reeden pagination 层 5 字段的最小集），冷启动命中时直接出页跳过重排；schema 不匹配自动重建
  - 产出：`packages/reader_core/lib/layout/page_index.dart` 序列化 + 读写用例
  - 依赖：P2-26
  - 验收：同设置重开书跳过分页（分页耗时为 0 有埋点）；schema 版本不匹配时静默重建结果一致；索引损坏（截断/魔数错）不崩溃
  - 参考：[参考/reeden/reports/650-rpi2-format.md](../../参考/reeden/reports/650-rpi2-format.md) §0、§3（pagination 5 字段与错误码）；[技术方案 §11.1](../技术方案.md)（分页缓存）

- [x] **P7-23 三层缓存与设置失效矩阵** ｜ 4h
  - 目标：排版缓存拆为 {document, styles, pagination} 三层，各层缓存键只含影响该层的最小变量集；按「设置 → 失效层 → 是否重定位 → 是否可增量」建立失效矩阵（字号只失效 styles+pagination、主题零失效、字体与几何全失效）
  - 产出：缓存分层重构 + `方案/验收记录/P7-失效矩阵.md` + 矩阵测试
  - 依赖：P7-22
  - 验收：矩阵中每类设置变更只失效标注层（切主题零重排有测试断言）；缓存键含「设置 + 几何」指纹（§21.1 windowKey 拆到各层）；现有 P2-24 重排链路行为不回退
  - 参考：[参考/reeden/reports/550-perf-font-config.md](../../参考/reeden/reports/550-perf-font-config.md) §2（21 行失效矩阵）；[技术方案 §11.1、§21](../技术方案.md)（缓存与重排链路）

- [x] **P7-24 margin 塌陷复核（MarginStrut 对照）** ｜ 3h
  - 目标：对照 MarginStrut 模型复核 P2-08 的 margin 折叠实现，补三类边界：相邻负 margin、浮动容器内块、首/末子元素穿透折叠
  - 产出：复核记录 + 补充用例（发现偏差即修）
  - 依赖：P2-08
  - 验收：三类边界快照与 CSS 2.2 外边距折叠规范行为一致；偏差项有缺陷登记与修复
  - 参考：[参考/reeden/reports/140-epub-layout.md](../../参考/reeden/reports/140-epub-layout.md)（MarginStrut 与塌陷）；[CSS 2.2 外边距折叠](https://www.w3.org/TR/CSS22/box.html#collapsing-margins)（规范）

- [x] **P7-25 BFC 阻断注入** ｜ 2h
  - 目标：排版前对 html/body 注入基础约束（overflow/min-height 归零、body 加 flow-root 或等价 BFC 阻断），防止作者页面的裸 float 污染整章布局
  - 产出：注入规则（随 UA 层下发）+ 用例
  - 依赖：P2-15
  - 验收：含裸 float 的样本整章布局不受污染（浮动只在预期容器内绕排）；注入可通过诊断观察；不影响 §7.5 覆盖层顺序
  - 参考：[参考/reeden/reports/630-ua-stylesheet.md](../../参考/reeden/reports/630-ua-stylesheet.md) §4-#3（必须配套的注入样式）；[技术方案 §73](../技术方案.md)（UA 表）

- [x] **P7-26 整组不可切规则** ｜ 3h
  - 目标：分页器支持「整组不可切」的组语义：图 + 题注、连续图组作为原子单元不在中间切页；整组放不下当前页时整体下移，组高于整页时按序切（缩放策略留给 P3-10）
  - 产出：分组页判定 + 用例（图+题注样本）
  - 依赖：P2-26
  - 验收：图与题注永不分离（跨 20 页扫描无分离样本）；组放不下时整体下移不产生空页；与 page-break-before/after 组合行为正确
  - 参考：[参考/reeden/reports/510-spec-typeset.md](../../参考/reeden/reports/510-spec-typeset.md) §3.4-#4（D 系整组不切规则）；[技术方案 §60](../技术方案.md)（块测量规格）

- [x] **P7-27 增量重排与 section 续排** ｜ 4h
  - 目标：设置变更触发重排时按章续排不丢弃已完成部分；失效与续排日志带 old/new 上下文（设置项、失效层、已完成章数），四类失效诱因（屏幕尺寸/配置版本/配置变更/缓存不存在）可区分
  - 产出：分页任务续排 + 结构化日志
  - 依赖：P7-23
  - 验收：改字号时已完成章的分页进度保留（重排从断点继续有埋点）；日志能回答「这次失效是谁引起的、丢了哪几层」；取消后已完成页保留（§27.3 行为不变）
  - 参考：[参考/reeden/reports/180-epub-perf-compat.md](../../参考/reeden/reports/180-epub-perf-compat.md)（completedSections 续排）；[参考/reeden/reports/550-perf-font-config.md](../../参考/reeden/reports/550-perf-font-config.md) §1.2（失效诱因四串）

- [x] **P7-28 首字下沉近似** ｜ 3h
  - 目标：出版书常用的 `::first-letter` 首字下沉在伪元素不支持的前提下提供内置近似：识别段首字符按 N 行高放大，识别失败记诊断照常渲染
  - 产出：首字下沉近似实现 + 样本快照
  - 依赖：P7-03
  - 验收：含首字下沉样本视觉可接受（首字基线与后续行对齐）；纯字母段首不误触发；快照回归其余样本无差异
  - 参考：[参考/reeden/reports/510-spec-typeset.md](../../参考/reeden/reports/510-spec-typeset.md) §1.4-#4（伪元素缺失时的近似建议）；[技术方案 §23](../技术方案.md)（CSS 属性分级）

- [x] **P7-29 缓存键检查清单落文档** ｜ 2h
  - 目标：把「缓存键必须包含影响该层的最小变量集」写成新增设置时的过检清单（新增任何排版输入都要回答：影响哪层、键里有没有它、失效怎么传），并回顾技术方案 §11.1 现有全部缓存键
  - 产出：`方案/验收记录/P7-缓存键检查清单.md`
  - 依赖：P7-23
  - 验收：现有缓存键（CSS 规则表/计算样式/分页/页渲染/图片/字体等）逐条过检；漏键项登记修复任务；清单并入开发约定供后续任务引用
  - 参考：[参考/reeden/reports/660-cache-keys.md](../../参考/reeden/reports/660-cache-keys.md)（键设计检查清单）；[技术方案 §11.1](../技术方案.md)（缓存表）

### P7.5 集成与评审

- [x] **P7-30 P7 能力并入 M1 集成链路** ｜ 4h
  - 目标：把 P7 新增能力（标点三件套、页索引冷启动、双路径解析、失效矩阵）并入现有 M1 集成测试链路并更新快照基线
  - 产出：`apps/reader_mobile/test/m1_integration_test.dart` 扩充 + 快照更新
  - 依赖：P7-21、P7-22、P7-26
  - 验收：全链路用例通过；快照差异逐条归因（新能力引入的差异有说明）；冷启动页索引命中路径有用例
  - 参考：[集成测试](https://docs.flutter.dev/testing/integration-tests)（用例组织）；[技术方案 §13.2](../技术方案.md)（快照回归）

- [x] **P7-31 样式回归样本扩充** ｜ 3h
  - 目标：按 P7-04 属性对照结论与 P7-03 UA 表扩充回归样本：密集标点书、深层列表嵌套书、裸表格书、含 `<sup>` 脚注书、首字下沉书
  - 产出：样本清单（`test_corpus/` 与生成脚本说明）+ 快照与断言
  - 依赖：P7-06
  - 验收：新增样本全部有快照与至少一条断言；回归脚本可重复运行；样本版权说明更新
  - 参考：[参考/reeden/reports/510-spec-typeset.md](../../参考/reeden/reports/510-spec-typeset.md)（进阶集清单）；[技术方案 §45.3](../技术方案.md)（样本库）

- [x] **P7-32 P7 里程碑评审与文档回填** ｜ 2h
  - 目标：核对 P7 全部任务完成情况，回填技术方案 §2.2 索引状态与 §82.7 落地标记，登记未落地项去向（并入 P3～P6 任务或挂账）
  - 产出：评审记录、技术方案与主文档进度更新
  - 依赖：P7-30、P7-31
  - 验收：全部任务勾选有据（测试/记录可复查）；§82.7 三张表的「直接采纳」条目全部有落地位置或明确挂账；遗留项有编号与责任阶段
  - 参考：[主文档 §0.4](../开发方案.md)（勾选规则）；[技术方案 §82.7](../技术方案.md)（借鉴清单）
