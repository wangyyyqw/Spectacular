# EPUB 引擎架构与开发者指南

当前实现以 `reader_core` 为唯一 EPUB 引擎，应用与测试直接导入核心模块。章节与定位契约统一位于 `reader_core/source/`；书库、进度和统计共用当前 schema 1。文件职责、缓存容量和既有验收记录见 [EPUB 引擎架构](../docs/epub-engine-architecture.md)，验证入口与预期维护见 [测试分类](../docs/测试分类.md)。

## 数据流

```text
应用文件选择与导入
  → 计算书籍身份、内容摘要并保存当前数据库
  → EpubFormatOpener.openFile / openBytes
  → BookResources：归档、目标章、直接资源
  → ChapterStructureStore：原始文档、选择器、原文锚点、图片叶 CFI
  → ChapterStyles / ChapterStyleResolver：UA、作者规则和阅读设置
  → ChapterBlockWalker：文字、图片、表格、Flex、容器构块
  → ChapterPageLayout / Paginator：分页与页索引
  → ReaderSession：当前位置、预取、交互和持久化
  → PageRenderer：Canvas 正文、背景、装饰和选区
```

解压和 HTML/CSS 解析通过书籍共享的可取消 worker 完成；字体测量和分页在主 isolate 按预算让出执行权。准备完成后冻结 `LayoutSnapshot`，结果提交前核对内容、视口、字体和取消状态。

## 文件地图

路径相对 `packages/reader_core/lib/`；应用与 UI 文件标明所属包。

| 子系统 | 入口 | 职责 |
|---|---|---|
| 格式来源 | `source/format_opener.dart`、`source/chapter_source.dart` | 格式打开、章节、目录、定位、准备和资源关闭契约 |
| EPUB 门面 | `epub/epub_format_opener.dart`、`epub/epub_chapter_source.dart` | 组织一次开书、章节请求、缓存提交及关闭 |
| 资源准备 | `epub/chapter/book_resources.dart`、`chapter_preparation_job.dart` | 按目标章准备文档和直接注释，共享调度与取消 |
| 原文结构 | `epub/chapter/chapter_structure.dart`、`chapter_positions.dart` | 聚合原文、目录定位与全书字节进度 |
| CSS | `css/parser.dart`、`stylesheet_loader.dart`、`cascade.dart`、`computed_style.dart` | 解析、异步导入展开、层叠、继承和计算值 |
| UA | `css/ua_stylesheet.dart` | `uaRules()` 提供唯一规则集，参与完整层叠 |
| 章节样式 | `epub/chapter/chapter_styles.dart`、`chapter_style_resolver.dart` | 作者表缓存、字体改写、行内样式与阅读覆盖 |
| 构块 | `epub/chapter/chapter_block_walker.dart`、各类 `*_block_builder.dart` | 按文档序构造当前页面块与原文坐标 |
| 排版 | `layout/line_breaker.dart`、`layout/paginator.dart` | 文字行盒、断行、页边界与页面载荷 |
| 章节分页 | `epub/chapter/chapter_pagination.dart` | 协调浮动、容器、页索引和特殊图片页 |
| 绘制 | `paint/page_renderer.dart` | 消费页面载荷，绘制正文、背景、边框与装饰 |
| 字体 | `epub/chapter/book_fonts.dart`、`css/book_font_loader.dart` | 按章加载书内字体，冻结作业使用的字体视图 |
| 阅读 UI | `reader_ui/reader_session.dart`、`reader_page.dart` | 会话、预取、手势、选区、重排和页家具 |
| 应用存储 | `reader_mobile/storage/db.dart`、`library/library_store.dart` | 当前完整数据库、导入、书库和统计持久化 |

## 准备与位置契约

- 冷章节先等待 `source.loadAnchorChapter(spine)`，需要页面时等待 `source.loadChapter(spine)`。同步 `anchorChapter`、满屏分析与位置换算只消费准备结果，不隐式解析。
- 百分比跳转使用 `prepareCfiForReadingPercent(percent)`；目录跳转先准备其目标章，再读取目录 CFI 或 fragment。视口变化后重新准备该章。
- `BookResources.parsedChapter/footnotes` 与 `ChapterStyles.stylesheets` 是准备结果的读取入口。未准备时明确失败，调用方通过相应异步准备 API 获取数据。
- 结构与资源缓存共享同一原始文档；完成布局只保存纯结果，不持有归档句柄。当前章节固定在有界缓存内，后台预取不能挤出它。
- 同键请求共享计算，每个等待者独立取消。关闭来源后等待 `preparationsStopped`，再结束测试或阅读页资源收尾。
- 原文 CFI 使用 UTF-16 文本偏移或真实图片叶元素身份。生成文本、列表标记和当前页号分别处理，不替代原文坐标。

## 数据模型与书籍修订

`AppDatabase` 的 schema 1 一次建立当前表和索引，没有历史版本迁移或外部 JSON 补导入。导入时计算 `contentRevision`；书籍身份、内容摘要和排版版本各自承担不同职责。书籍目录统一为 `books/<id>`。

内容锚点只编解码当前格式，读取进度直接使用保存的比例和位置元数据。书籍内容修订继续支持原文匹配、拆章合章、待确认位置和过期会话写入保护。修订前身份的关联由 `BookIdAliases` 保存；用户笔记、书评和阅读时段保留。损坏的锚点导致修订失败并保留当前数据，不从页号或文件补造记录。

## 按改动验证

在仓库根目录执行：

```bash
python3 tool/run_tests.py --check
python3 tool/run_tests.py --changed --dry-run
python3 tool/run_tests.py ui
python3 tool/run_tests.py css
python3 tool/run_tests.py resources position storage
python3 tool/run_tests.py layout paint integration --analyze
```

跨职责的公共接口变化组合调用方分类。核心依赖方向变化运行 `bash tests/tool/verify_core_boundary.sh`；分析规则变化运行 `bash tests/analysis/verify_strict_flags.sh`。本地测试默认 `--no-pub`，缺少依赖配置先使用离线缓存。`--all` 和 `tool/run_all.sh` 是显式全量入口。

行为变化在同一提交中更新实现、旧断言、夹具与索引。快照逐条归因：本次统一 UA 后，表格题注消费居中规则，只更新 `table.epub` 第 0 页版式哈希及整书哈希；页数、原文、其他样本与光栅参考计数保持。单纯内部整理保留原断言。

## 扩展与边界

- CSS 属性经过解析、层叠、计算值和实际构块 / 绘制消费，并验证真实章节结果。
- 新选择器在 `SelectorElement` 视图上匹配，回归需包含祖先、兄弟和原始属性身份。
- 新块载荷由核心定义，构块器生成，分页器和绘制层共同消费；定位和取消测试随公共行为更新。
- 引擎依赖 Flutter 的测量、字体注册和 Canvas。Flex、竖排、满屏图片及 EPUB 扩展按已实现能力验证；TXT/PDF 当前只有来源契约，没有解析器。
- 单次原生文字测量内部不能任意抢占，原生字体和图片内存也不属于纯布局缓存容量。修改浮动、表格或原文坐标时需要组合相关分类与真书冒烟。
