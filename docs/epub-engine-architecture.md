# EPUB 引擎架构

项目使用单一的 `reader_core` EPUB 实现和当前数据库结构。应用与测试直接导入核心模块，章节、目录和调度契约统一从 `source/` 导入；应用层不再保留章节转发文件，`reader_session.dart` 只提供会话与用户操作契约。样式、页面和位置分别以 `ComputedStyle`、`PageBlock` / `PageContent`、EPUB CFI 表达。

依赖方向为 `reader_mobile → reader_ui → reader_core`，应用也直接使用核心的 EPUB 打开器。应用负责文件选择、数据库、偏好、用户字体文件和平台插件；`reader_ui` 负责会话、预取、手势、选区和阅读界面；`reader_core` 负责资源、解析、样式、布局、绘制和位置。核心可以依赖 Flutter，但不能反向依赖应用、`reader_ui` 或平台插件。`api.dart` 只汇总跨层契约与数据模型，EPUB 实现通过 `epub/` 的具体入口导入。

```mermaid
flowchart LR
  open[统一来源接口] --> resources[EPUB 资源准备]
  resources --> structure[文档结构与原文锚点]
  structure --> style[级联与属性计算]
  style --> blocks[构块与文字测量]
  blocks --> pages[分页与页索引]
  pages --> paint[Canvas 绘制]
  structure --> position[CFI 与阅读进度]
  snapshot[冻结的 LayoutSnapshot] --> style
  snapshot --> blocks
  snapshot --> pages
```

一次打开和章节请求依次经过以下阶段：

1. `EpubReaderPage` 通过 `ReaderFormatOpener<EpubChapterSource>` 打开文件或字节。`EpubFormatOpener` 委托原有 `EpubChapterSource.open/openFile`，继续由 `epub_document.dart` 处理归档、OPF、目录与扩展元数据。文件入口保留按需读取能力。
2. `BookResources` 准备目标章及其直接资源；`ChapterStyles` 加载样式和导入依赖；`ChapterStructureStore` 交接聚合原文、选择器、锚点和图片分析。解压、HTML/CSS 解析等纯数据工作使用书籍共享的准备 isolate，归档读取句柄留在宿主。
3. 目标章字体与手工度量装饰准备完成后，冻结 `LayoutSnapshot`：内容版本、章节、尺寸、基础样式、阅读设置、字体依赖和装饰视图都进入本次作业。应用字体存储通过现有准备回调和字体可用性接口接入。
4. `ChapterLayoutPipeline` 先判断现有整页图片路径，再由样式解析器、生成内容服务和各类构块器产生 `PageBlock`。普通文本、表格、图片、行内原子盒各自测量；内在宽度预测复用文本测量，并使用独立的生成内容与列表状态副本。
5. `ChapterPageLayout` 协调浮动等章节分页规则并复用核心 `Paginator`，产出 `PageContent` 与页索引。门面核验作业仍有效后提交完成缓存；`ReaderSession` 消费页面和位置，绘制层经 Flutter Canvas 展示正文、背景和装饰。

定位由原文锚点、文本范围与图片叶 CFI 驱动，不以当前行数或页码替代原文位置。列表标记使用既有 `PageBlock.listMarker` 路径；生成内容的绘制坐标与原文坐标分别维护，字号和窗口变化后仍通过原文位置恢复阅读。

统一来源契约放在 `packages/reader_core/lib/source/`：

| 契约文件 | 作用 |
|---|---|
| `chapter_source.dart` | 实际使用的章节加载、可取消任务、准备优先级、定位、目录、重排和字体依赖契约；调用方直接导入此文件。 |
| `toc.dart` | 共享 `TocRow` 与 `flattenToc`，保持原目录展开结果。 |
| `format_opener.dart` | `ReaderFormat`、`ReaderContentLayout`、`ReaderPublicationSource`、`ReaderFormatOpener` 和 `ReaderOpenOptions`。 |

`ReaderPublicationSource` 沿用 `ReaderChapterSource`，增加 `format`、`layout` 和同步 `close()`。`ReaderOpenOptions` 只共享原有的正文宽高（默认 320 × 480）、基础样式、`trimTextEdges`（默认开启）与内容版本。EPUB 打开器的 `verifyCrc` 是格式专属选项：未指定时字节入口校验、文件入口不校验；应用对已导入书籍显式传 `false`，保持原打开语义。

EPUB 的 `layout` 来自 `document.extensionConfig.isFixedLike`，`_prepareLayoutInput` 实际据此选择原有固定页图片分析。它描述现有书籍配置与处理分支；固定版和漫画支持仍受单图、可见正文、资源可用性等条件限制，`vertical-comic` 保留已有告警与降级路径。

TXT、PDF 当前只有格式枚举，没有解析器或注册表。后续格式可实现相同的打开与来源契约，并声明 `reflowable` 或 `fixedPages`；固定页来源仍须提供页面内容、资源释放和位置映射。当前契约没有实现 PDF 解码、文本提取、注释或原生页面坐标语义，应用阅读页也仍保留 EPUB 专属入口。

资源与并发边界围绕一次打开的书籍建立。`BookResources` 是归档与原始资源的唯一关闭所有者；字体、样式、构块器只能借用它，完成布局不持有归档或加载器。`EpubChapterSource.close()` 取消准备和排版、失效版本并关闭各服务；宿主通过 `preparationsStopped` 等待 isolate 和端口实际释放。`BookFonts.close()` 清理 Dart 侧状态，Flutter 已注册的字形仍由引擎管理。

准备调度与几何排版分别管理。同键请求共享计算，每个等待者独立取消；前台阅读优先于预取和后台。HTML/CSS 准备可取消 worker，几何排版在主 isolate 串行执行，并在遍历、测量与分页边界让出执行权。取消、内容版本变化、尺寸或字体依赖过期都会阻止结果提交；这些检查同样覆盖准备缓存回填，不能只在任务开始时判断一次。

同步访问只消费准备结果：读取原文、目录位置或满屏判定前等待 `loadAnchorChapter(spine)` 或 `loadChapter(spine)`；百分比跳转使用 `prepareCfiForReadingPercent(percent)`。`BookResources.parsedChapter/footnotes`、`ChapterStyles.stylesheets` 和 `ChapterStructureStore.prepared` 在冷缓存时返回明确错误，不触发同步解压、解析或坐标补写。视口改变后重新准备目标章。结构缓存共享资源服务已解析的文档，目录核验也从该结构读取，保留同一份原始树。

`setCurrentReadingChapter` 固定实际可见章结构，最近的前台准备请求使用独立保护键，辅助定位不会替换当前章的保护；结构缓存仍以三项为上限。视口变化后原文索引尚未准备时，`readingPercentForCfi` 按公共契约返回 `null`，不触发同步解析。会话不缓存准备中的空值，重排提交后重新计算百分比。

页面窗口和原文索引分别缓存，预加载页不能保证索引仍在缓存中。`ReaderSession` 在跨章翻页、滚动与跳转提交前检查目标页的 CFI；来源提供正文进度但位置不可用时，通过既有可取消原文准备任务补齐索引。已有位置能力或不提供正文进度的来源不重复准备。

UA 默认值统一由 `uaRules()` 参与 `Cascade.compute()`；CSS 导入加载、行内样式解析和 Flex 构块均只有一个异步入口。行内提升块同样等待后缀级联并检查作业预算。组件快照通过同一套 UA 层叠计算样式，其页边距和段距由夹具显式固定。

应用存储采用 `AppDatabase` 的初始 schema 1，一次建立当前完整表结构和索引。书库、阅读进度、统计时段、标注、装饰、书评和偏好共用此库；没有历史 schema 升级、书库 / 进度 JSON 导入、身份补迁、锚点语义补迁或开书摘要补写。书籍目录统一为 `books/<id>`，导入时计算内容摘要并随条目保存。

内容修订属于当前应用功能：用户重新导入修改后的 EPUB 或明确替换原书时，以原文证据重新关联位置，保留原始锚点、笔记、书评和阅读时段。修订产生的身份关联保存在 `BookIdAliases`；写入前核对当前内容摘要，防止过期阅读会话回写。缺失或损坏的记录不会在读取时转换；修订遇到无效锚点会失败并保留当前文件和数据库。

缓存继续有界：完成布局、块和页索引由同一条目持有，进程内近期缓存最多 3 项、估算总量不超过 32 MiB；原文和结构缓存按 3 章保留，CSS 表缓存 32 项，段落测量缓存 4096 项，文本宽度缓存 2048 项，图片尺寸和未命中缓存各 512 项。完成缓存可以在来源关闭后保留纯结果，但不持有文件句柄。其容量估算不包含独立图片解码缓存和原生字形内存。

完成布局键包含内容版本、基础样式、实际宽高、页高和上内缩、阅读设置、字体依赖及本章度量装饰；基础样式键也保留作者几何字号 `cssFontSize`、内在宽度模式和背景数据。视口或内在宽度变化进入实际测量宽度及相应键；纯绘制覆盖沿用现有重绘路径。缓存失效与版本检查共同约束复用，不能仅凭章节序号取页面。

以下是 43 个实现文件的最终归属，路径均相对 `packages/reader_core/lib/`。`epub/chapter/` 共 40 个文件，包括原章节目录的 39 个实现及 `prose_spacing_defaults.dart`；这张表不包含原本就在核心的 ZIP、OPF、CSS、分页器等模块。

| 实现文件 | 职责 |
|---|---|
| `epub/epub_chapter_source.dart` | EPUB 章节门面；协调资源、准备、布局、定位、缓存提交与关闭，保留原静态打开入口。 |
| `epub/epub_format_opener.dart` | 将统一格式打开契约适配到原 EPUB 字节和文件入口。 |
| `util/bounded_cache.dart` | 按最近访问顺序淘汰的定长缓存，不包含书籍或会话业务。 |
| `epub/chapter/block_style_helpers.dart` | 字号声明来源、页背景、边框颜色及 UA 列表缩进规则的共享转换。 |
| `epub/chapter/book_fonts.dart` | 书内字体注册、族名与字形覆盖映射、用户字体可用性及不可变字体视图。 |
| `epub/chapter/book_progress.dart` | 从清单和归档元数据构建进度权重，封装章内文本和图片坐标。 |
| `epub/chapter/book_resources.dart` | 持有归档；准备原文、注释、图片和字体资源，管理资源缓存与释放。 |
| `epub/chapter/cancellable_isolate_worker.dart` | 同书共享一个纯数据 worker 槽位，负责排队、取消、退出及端口释放。 |
| `epub/chapter/chapter_anchor_builder.dart` | 隐藏注释定义、按作者显示规则聚合原文并收集锚点块。 |
| `epub/chapter/chapter_block_walker.dart` | 按文档顺序分发构块任务，维护递归容器和列表上下文。 |
| `epub/chapter/chapter_flow.dart` | 保存一次构块的块流、浮动游标、递归位置和列表计数上下文。 |
| `epub/chapter/chapter_image_coordinates.dart` | 收集实际可见图片叶的顺序和 CFI，保留 SVG 内层图片身份。 |
| `epub/chapter/chapter_layout_cache.dart` | 冻结完成布局、估算引用图容量，统一复用页面、块和页索引。 |
| `epub/chapter/chapter_layout_job.dart` | 定义 `LayoutSnapshot`、执行预算与章节排版调度器，管理独立等待者。 |
| `epub/chapter/chapter_layout_pipeline.dart` | 组合样式、构块和分页阶段，只返回纯结果，由门面统一提交。 |
| `epub/chapter/chapter_page_flags.dart` | 解释 OPF 整页图片、窗口适配和跨页图标记。 |
| `epub/chapter/chapter_pagination.dart` | 普通、浮动及特殊块的章节分页协调，生成并复用页索引。 |
| `epub/chapter/chapter_positions.dart` | 提供原文定位、目录目标、全书比例与 CFI 转换，不依赖页面测量。 |
| `epub/chapter/chapter_preparation_job.dart` | 准备任务去重、优先级、独立取消、子任务传播和结果映射。 |
| `epub/chapter/chapter_raw_styles.dart` | 原文准备阶段的作者级联、可见性和字体引用收集。 |
| `epub/chapter/chapter_selectors.dart` | 连接原始元素、兄弟关系、聚合节点和作业内生成节点的选择器视图。 |
| `epub/chapter/chapter_structure.dart` | 准备和缓存聚合文档、选择器、锚点及普通／固定页图片分析。 |
| `epub/chapter/chapter_style_key.dart` | 为影响后续计算的基础样式生成完整稳定键。 |
| `epub/chapter/chapter_style_resolver.dart` | 作业内级联、根逻辑轴、字号处理、行内样式和容器样式投影。 |
| `epub/chapter/chapter_styles.dart` | 加载 CSS 与导入依赖，处理媒体条件、字体声明和派生级联缓存。 |
| `epub/chapter/chapter_text_measurer.dart` | 使用冻结字体与预算进行文本、表格宽度和内在宽度测量，复用完成结果。 |
| `epub/chapter/chapter_text_overlays.dart` | 按目标章节派生手工度量装饰、字体族及稳定指纹。 |
| `epub/chapter/container_blocks.dart` | 维护容器片段、边框占位、外边距折叠及跨页装饰语义。 |
| `epub/chapter/css_preparation.dart` | 向 worker 提供 CSS 文本和归档条目解析的纯数据入口。 |
| `epub/chapter/flex_blocks.dart` | 现有 Flex 行构块、空间分配及页面根纵向 Flex 对齐。 |
| `epub/chapter/full_page_layout.dart` | 普通满屏单图与多看固定页分支，处理适配、出血和不支持情形的告警。 |
| `epub/chapter/gallery_block_builder.dart` | 识别多看分帧画廊，保留帧内布局并生成外层原子块。 |
| `epub/chapter/generated_chapter_content.dart` | 按文档顺序维护计数器、引号和伪元素生成内容，提供测量状态副本。 |
| `epub/chapter/generated_content.dart` | 求值 `content` 中的字符串、属性、计数器、引号和图片占位。 |
| `epub/chapter/image_block_builder.dart` | 将块级图片的尺寸、浮动、定位、盒模型和 CFI 组装为页面块。 |
| `epub/chapter/image_blocks.dart` | 按 CSS、表现属性和图片比例解算显示尺寸与边界约束。 |
| `epub/chapter/inline_content_builder.dart` | 构建行内图片、原子盒和注释载荷，提取行内浮动并重映射偏移。 |
| `epub/chapter/intrinsic_blocks.dart` | 预测普通横排容器的内容占宽，复用测量而不重走正式构块和计数。 |
| `epub/chapter/page_root_table_cell.dart` | 按根盒高度对齐页面根表格唯一单元格中的块流。 |
| `epub/chapter/prose_spacing_defaults.dart` | 只补普通正文的缺省排版值，保留作者显式声明和继承来源。 |
| `epub/chapter/table_block_builder.dart` | 解析表格、行列跨度和列宽，预算内测量单元格并提交完整表格块。 |
| `epub/chapter/text_block_builder.dart` | 将聚合文本、列表标记、生成内容、首字下沉及行内载荷转为可分页文本块。 |
| `epub/chapter/text_coordinates.dart` | UTF-16 代理项判断和文字样式片段切片，保留偏移语义。 |

CSS 仍以 `ComputedStyle` 为统一入口，属性族只拆出解析和计算职责。新增声明必须经过级联与真实消费者；只有字段解析成功不足以构成功能支持。此次涉及的入口如下，路径仍相对核心 `lib/`：

| 模块 | 入口与实际消费 |
|---|---|
| `css/value_tokens.dart` | 分割值列表、函数和引号内容，解码 CSS 字符串；背景、列表及简写共同使用。 |
| `css/length.dart` | `CssValueContext` 从 `LayoutSnapshot` 获得视口和根书写轴，全部视口单位在样式计算时统一冻结为像素；`CssLength` 只表达像素、百分比和 auto，保留 `calc`，`ex` 使用 `0.5em` 回退。 |
| `css/font_size.dart` | `CssFontSizes` 计算绝对档位和相对关键字，并参与现有阅读字号分类；作者几何字号独立保存在 `cssFontSize`。 |
| `css/list_style.dart` | 解析字符串标记、类型和严格简写；文本构块器复用标记测量和绘制路径。 |
| `css/background_declarations.dart` | 校验背景声明并展开长短属性，分轴定位进入同一组级联属性。 |
| `css/background_values.dart` | 背景层、每轴重复模式、定位和渐变模型，包括基础 `CssConicGradient`。 |
| `css/intrinsic_width.dart`、`layout/intrinsic_widths.dart` | 分别表示宽度模式和内容测量值；`BoxModel` 应用 `fit-content` 公式及原有 min/max 约束。 |
| `css/parser.dart`、`css/cascade.dart`、`css/computed_style.dart` | 保留完整入口，处理声明有效性、级联顺序、继承、复制与计算值，连接各属性族。 |
| `layout/line_breaker.dart` | 提供文字布局、行盒与样式片段的唯一入口，测量内在宽度并接入取消预算。 |
| `paint/background_tiles.dart`、`paint/background_image.dart`、`paint/page_renderer.dart` | 图片和渐变共用瓦片几何，消费 `space/round`、分轴定位与锥形渐变，并保留背景层和裁剪路径。 |

新增能力保持明确边界：背景定位没有增加 `right 10px` 等边缘偏移语法；锥形渐变只支持默认中心、起点和均匀色标，不支持 `from/at`、显式色标位置或重复锥形渐变；内在宽度仅覆盖普通横排文本块与容器，没有扩展到尺寸函数、其他尺寸属性或替换元素的完整算法。`vi/vb` 使用根书写轴；保留 HTML 根轴信息不等于实现完整 HTML 样式继承。`orphans/widows` 继续不在本轮范围。属性对照与证据见 [CSS 属性审计](css-property-audit.md)。

主观架构评分为 **7.5/10**。职责归属、真实跨层契约、资源关闭权、冻结输入及提交边界已经较清楚，后续 CSS 适配可以沿“属性族计算 → 模型 → 构块／绘制消费者”扩充。主要复杂度仍集中在 `ComputedStyle`、`text_block_builder.dart`、`chapter_pagination.dart`、`table_block_builder.dart` 等大模块；浮动、表格、行内载荷和原文坐标之间仍有较强联动，分包没有消除算法复杂度。

本次迁移对这些已有大函数保留算法正文，以隔离依赖整理与行为变更；超过长度或复杂度阈值的旧函数没有在同一提交中再次拆分。代价是局部理解成本仍高，改动浮动、表格和行内坐标时必须继续通过真实章节回归约束。

核心仍依赖 Flutter 的 `TextPainter`、字形注册、Canvas 和 shader，不能作为纯 Dart 的无界面排版库使用。几何测量仍在主 isolate 上运行，时间预算是协作式检查，单次原生测量并不能在内部任意抢占；字体回退与平台度量也会影响结果。关闭书籍不能保证立即释放 Flutter 的原生字体内存。现有 Flex、竖排和固定页是具体能力集合，不代表完整浏览器 CSS 或通用 PDF 支持；本轮没有用同设备的独立性能对照证明速度或内存已经提升。

验证沿用固定 EPUB 夹具比较样式、块结构、分页和 CFI，已核对的固定结果保持不变，没有整体重录基线。迁移验收中的 14 项既有失败，已在干净的 `dd3e1eb8404cba5644cb4250b9bfd02071d8ba91` 副本、相同本地依赖环境下复现；涉及字号、浮动与缩进、首屏页眉、预取集合、基础样式实例及日期相关统计断言。这些失败在迁移提交中未修复，以下保留该次验收的历史结果。

2026-11-11 集中验收使用 Flutter 3.47.5、Dart 3.13.4 和已有本地依赖。CSS 提交为 `e944764`，迁移在此基础上完成；没有新增依赖。三包 `flutter analyze --no-pub` 均无问题，完整测试结果如下：

| 包 | 通过 | 已复现的旧失败 | 跳过 |
|---|---:|---:|---:|
| `reader_core` | 1729 | 0 | 8 |
| `reader_ui` | 768 | 4 | 0 |
| `reader_mobile` | 1198 | 10 | 6 |
| 合计 | 3695 | 14 | 14 |

核心跳过项为真书全量性能测试 1 项、级联基准 1 项、真实字体基准 4 项、性能预算 1 项，以及当前 Flutter 不区分 `TextLeadingDistribution` 的旧用例 1 项。应用跳过项为未开启 `REAL_EPUB` 的 3 项、`RUN_REAL_BOOK_BENCHMARK` 的 1 项，以及缺少 `CSS_PARITY`／`FEEDBACK_MANIFEST` 配置的 2 项。新增七组能力的章节、几何与像素用例没有依赖这些开关。

纯迁移另做两项对照：43 个实现剔除导入／导出后与搬迁前备份逐字相同；3 组章节内容在 2 组视口和字号下共 23 页，样式、块结构、分页、原文、CFI、进度和逐页像素散列全部相同。临时输出的 SHA-256 为 `b55f8e8a516ddb89c9ae072a20d9da226c95edb96b41c0da3de5dbcb32708e79`。统一文件／字节打开、固定页分支、内容版本缓存与 CRC 默认值的 6 项测试也通过。

以下保留原基线和迁移验收的失败明细；行号为当时的位置，相对各包的 `test/`：

| 包／用例 | 原基线与迁移验收相同的结果 |
|---|---|
| 应用 `reader/narrow_author_width_test.dart:25` | 期望 24，实际 19.2。 |
| 应用 `reader/inline_display_block_test.dart:222` | 期望 14.45，实际 19.19140625。 |
| 应用 `reader/float_flat_test.dart:139` | 期望 16，实际 32。 |
| 应用 `reader/css_gaps_test.dart:129`、`:277` | 分别期望 38／34，实际 36／32。 |
| 应用 `reader/book_opening_flow_test.dart:136`、`reader/book_opening_view_test.dart:165`、`reader/margin_pagination_test.dart:137` | 首屏未找到 `ReaderPageHeader`，第三项在辅助函数第 285 行报 `No element`。 |
| 应用 `cache_layer_test.dart:56` | 尺寸变化后仍为同一基础 `ComputedStyle` 实例。 |
| 应用 `home/stats_page_test.dart:666` | 期望 25 分钟，实际 45 分钟；当前日期下两笔记录都落在十月。 |
| UI `prepared_decoration_flow_test.dart:288/314/378/438` | 四项预取集合都比预期多章节 743。 |

2026-11-11 后续修复按实际消费路径区分实现缺陷与失效断言，覆盖上述全部 14 项：

| 范围 | 修复依据与当前约束 |
|---|---|
| 行内提升块字号（实现缺陷） | `TextBlockBuilder._bodyStyle` 跳过已在行内级联中完成的字号覆盖，消除 14.45 再被放大为 19.19140625 的二次缩放。原断言保留，增加嵌套比例、根关键字、17→22→17 切换、实际测量 runs 与 CFI 回归。 |
| 纯图浮动父边距（实现缺陷） | `ImageBlockBuilder` 用 `FloatParentMargins` 分别保留父盒边距的正负极值，图片自身 margin 保持独立；相邻在流块与浮动定位共用一次折叠结果。保留原 16px 断言，并覆盖父 40px／图片 7px、正负边距、已有前段、无后继、零间距、直接浮动和图片叶 CFI。 |
| 窄标题与缩进（3 项失效预期） | `ReaderOverrides.applyCascadeBase` 在作者 em 几何解算时保留书籍字号，测试改用明确 16px 作者基准及独立公式，同时验证阅读字号变化。标题 `em/rem` 外边距沿用既有缩放策略，内容宽与内边距保持作者基准；短居中装饰标题和普通正文分别断言。 |
| 开书与边距（3 项失效预期） | 沿用 `f64e36da` 的每章首页隐藏页眉约定，严格验证正文与页脚已准备、首页无页眉、续页页码正确，以及揭开封面前后复用同一正文页。 |
| 装饰与预取（4 项失效预期） | 沿用 `f80f959` 的前向四页预算和前后两页快照窗口。首屏仅加载目标章，空闲后允许短章补入 743；目标章不重复排版，字体范围、CFI、已存进度和纯绘制更新的页面身份均受断言约束。 |
| 基础样式缓存（1 项失效预期） | 不把级联基准的对象身份当作布局失效证据，改为真实章节验证作者基准、正文 18→22px、颜色消费、320→280px 测量宽及重复尺寸的完成缓存命中。 |
| 统计日期（1 项夹具冲突） | 月与年样本移到三个月前和前年，保留 25／30 分钟预期，并检查各时段书目及切回日视图。样本归属枚举覆盖完整公历 400 年周期，避免五周前记录与上月样本重叠。 |

交叉检查还修正了外边距整理对无折叠操作的 `NaN` 哨兵重复创建块的问题，既有预算与幂等身份测试保持原断言。背景即时重绘测试的退出计时器问题也在 `dd3e1eb` 复现；测试现在等待取消准备任务与 worker 释放，再结清假时钟事件，绘制像素及零重排断言保留。

短章预取仍存在一轮邻章重复请求的既有开销：补入 743 后五章窗口淘汰 741，下一轮重新请求邻章，装饰准备命中后停止续排。本次未改变预取策略，不能据此宣称性能提升。原有条件跳过项仍按前述环境要求保留；旧章节 fixture 与 golden 未重录。

修复后的最终全量结果如下，三包 `flutter analyze --no-pub`、核心边界检查与严格规则检查均通过：

| 包 | 通过 | 失败 | 跳过 |
|---|---:|---:|---:|
| `reader_core` | 1729 | 0 | 8 |
| `reader_ui` | 772 | 0 | 0 |
| `reader_mobile` | 1217 | 0 | 6 |
| 合计 | 3718 | 0 | 14 |

相较迁移验收，14 个失败全部消除，并新增 9 个独立回归用例；其中基础样式缓存拆成两项公共行为，嵌套提升字号新增一项，浮动边距新增七项。现有七组 CSS 能力的 84 项章节回归、固定章节 fixture、图片 CFI、选择与进度用例均已纳入全量。

从仓库根目录执行的验收命令：

```sh
(cd packages/reader_core && flutter analyze --no-pub && flutter test --no-pub --reporter expanded)
(cd packages/reader_ui && flutter analyze --no-pub && flutter test --no-pub --reporter expanded)
(cd apps/reader_mobile && flutter analyze --no-pub && flutter test --no-pub --reporter expanded)
bash tool/check_core_boundary.sh
bash tests/tool/verify_core_boundary.sh
git diff --check
```

两项核心边界检查均通过。严格规则脚本也通过；其内部两次 `flutter analyze` 使用以下本地包装方式附加 `--no-pub`，没有修改脚本或依赖：

```sh
bash -c 'flutter() { /Users/aaa/development/flutter/bin/flutter "$@" --no-pub; }; export -f flutter; bash tests/analysis/verify_strict_flags.sh'
```
