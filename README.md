# Spectacular Reader

开发中的 Flutter 原生 EPUB 阅读应用，尚未发布。正文通过「解析 → CSS 计算 → 构块测量 → 分页 → Canvas 绘制」显示，不使用 WebView。

项目按一个全新应用维护：EPUB 实现统一放在 `reader_core`，书库、阅读进度和统计使用同一个完整数据库结构。当前不保留历史版本升级、JSON 导入或应用层引擎转发入口；用户重新导入修订后的书籍仍是正常业务功能。

## 当前实现进度

以下按 2026-11-11 的代码整理。任务看板为 **202 / 242 项（83.5%）**，P0、P1、P2、P3、P4、P7、P8 的任务已勾选；P4 里程碑与 P5、P6 尚未核销。任务勾选反映阶段记录，具体功能与验收范围以代码和专项证据为准，见 [开发方案](方案/开发方案.md) 与 [验收索引](方案/验收记录/README.md)。

| 能力 | 当前实现 | 验证与边界 |
|---|---|---|
| 应用主界面 | 书架、统计、书评、我的四页；书籍详情、分组、筛选、排序和批量操作 | 已有组件回归和 Android 真机记录 |
| EPUB 导入与资源 | 文件导入、内容摘要与去重、修订替换、OPF/目录、字体解混淆、图片与资源缓存 | 保留 EPUB 内容容错；TXT、PDF 只有格式契约，没有解析器 |
| CSS 与中文排版 | UA/作者/行内级联、阅读覆盖、选择器、盒模型、浮动、表格、列表、生成内容、中文对齐和标点处理 | 具体取值、消费者与降级范围见 [CSS 属性审计](docs/css-property-audit.md)，不宣称完整浏览器 CSS 支持 |
| 阅读交互 | 目录、进度跳转、书签、选区、高亮、笔记、图片预览、手工与自动装饰、主题、背景、自定义字体 | 同内容同版式可快速恢复；重排和内容修订使用原文锚点重新定位；图文混合首页的图片锚点仍有续读限制，见专项验收 |
| 阅读模式与高级排版 | 覆盖、堆叠覆盖、贝塞尔仿真、3D 仿真、水平滑动、无动画和连续滚动；已有 ruby、强调符和竖排实现 | P5/P6 的完整验收矩阵仍待完成，不能据现有入口认定发布就绪 |
| 搜索 | `ScanSearchService` 逐章扫描原文，结果携带 CFI 和上下文 | 当前主流程未使用 2-gram 全文索引 |
| 持久化与统计 | drift 保存书库、进度、标注、装饰、设置、书评和阅读时段；统计消费真实阅读会话 | `AppDatabase` 初始 schema 1，一次创建完整表与索引；数据库不可用时退回内存模式 |
| TTS 与发布 | 菜单保留可选 TTS 回调，依赖已声明；Android 开发验收 APK 可构建安装 | 尚未接入应用朗读流程；商店签名、发布材料和多平台验收未完成 |

统一实现的专项结果、APK 与真机范围见 [统一实现与 APK 验收](docs/统一实现与APK验收-2026-11-11.md)。本地样式、布局和业务回归与真机验证分别记录，Android 验收不代表 iOS/macOS 已完成同等验证。

## 模块职责与运行契约

依赖方向为 `reader_mobile → reader_ui → reader_core`，应用也直接调用核心的 EPUB 打开器。

| 模块 | 实际职责 | 入口说明 |
|---|---|---|
| [reader_core](packages/reader_core/README.md) | EPUB 资源、文档解析、CSS、章节准备、构块测量、分页、自绘、CFI 与原文位置 | `source/` 提供章节和格式契约，`epub/epub_format_opener.dart` 提供 EPUB 实现 |
| [reader_ui](packages/reader_ui/README.md) | 阅读会话、预取与页窗口、手势、翻页与滚动、选区、面板和主题 | `ReaderSession`、`ReaderPage`、`ReaderView`；存储和平台能力由宿主传入 |
| [reader_mobile](apps/reader_mobile/README.md) | 四页应用壳、文件选择、书库与数据库、搜索、统计、用户字体与背景、诊断和平台插件 | `lib/main.dart` 启动，`EpubReaderPage` 连接核心、UI 与业务存储 |

引擎资源由 `BookResources` 唯一持有关闭权。HTML/CSS 准备使用可取消 worker；文字测量与几何分页在主 isolate 执行。每次排版通过 `LayoutSnapshot` 冻结内容、视口、样式、字体和装饰输入，取消或过期作业不得提交结果。

原文、样式和注释的同步访问只消费已准备结果；调用方先等待 `loadAnchorChapter`、`loadChapter` 或百分比定位准备。UA 默认样式统一参与 `Cascade.compute()`。视口单位在样式计算时按本次快照转为像素，百分比继续由布局阶段按包含块解析。

进度保存 CFI、内容摘要和原文证据，同时记录章页提示、滚动偏移及版式指纹。页号是版式相关的恢复提示；窗口、字号或书籍内容变化后由内容锚点恢复。修订功能保留原始与当前证据，并核验当前内容摘要，阻止过期会话回写。

原 EPUB 文件不改写，容错和规范化发生在读取、解析与布局阶段。诊断以 `EpubCodeTable` 为真源，当前登记 48 条（包含预留码），由码表回归检查实际发出方。核心可依赖 Flutter 的文字测量与绘制能力，禁止依赖宿主、`reader_ui` 或平台插件。

详细数据流、缓存键、资源生命周期和扩展边界见 [EPUB 引擎架构](docs/epub-engine-architecture.md)。

## 本地开发

当前验证环境为 Flutter 3.47.5、Dart 3.13.4；SDK 约束以各包的 `pubspec.yaml` 为准。已有本地依赖时使用 `--no-pub`。首次配置或包配置缺失时，在对应目录执行 `flutter pub get --offline`；本地缓存不足时再下载所需内容。

```bash
# 在仓库根目录准备三个包的本地依赖
(cd packages/reader_core && flutter pub get --offline)
(cd packages/reader_ui && flutter pub get --offline)
(cd apps/reader_mobile && flutter pub get --offline)

# 查看设备，然后运行应用
flutter devices
cd apps/reader_mobile
flutter run --no-pub -d macos
```

Android 运行与离线 Release 打包说明见 [移动端 README](apps/reader_mobile/README.md)。构建产物放在被 Git 忽略的 `apps/reader_mobile/dist/`，不提交 APK、设备备份或日志。

## 按改动范围验证

测试分类真源是 `tool/test_groups.json`。当前入口包含 `ui`、`css`、`layout`、`paint`、`resources`、`position`、`storage`、`perf`、`integration`、`tooling` 十类；每个测试文件归一个主分类，组合选择会去重。

```bash
# 默认按暂存、未暂存及未跟踪改动选择
python3 tool/run_tests.py

# 指定职责；CSS 改变几何或绘制时组合相关分类
python3 tool/run_tests.py ui
python3 tool/run_tests.py css layout paint
python3 tool/run_tests.py storage position integration --analyze

# 校验分类与预览范围，不启动 Flutter
python3 tool/run_tests.py --check
python3 tool/run_tests.py --changed --dry-run
python3 tool/run_tests.py --list

# 核心依赖边界守卫
bash tests/tool/verify_core_boundary.sh

# 明确需要全量时，分析三包并运行本地测试
bash tool/run_all.sh
```

测试使用 `flutter test --no-pub`，分析使用 `flutter analyze --no-pub`。本地 Python 工具中的 CSS 图像回归需要 Pillow；本项目 macOS 已有 `/usr/bin/python3` 可运行 `tooling`。全量入口不包含 `integration_test/` 真机任务和设备操作，详细映射与范围见 [测试分类规则](docs/测试分类.md)。

行为变更在同一提交同步相关断言、夹具与调用方回归；修 bug 时增加能在原实现失败的最小用例。新增、删除、重命名测试同步分类索引。快照仅在有意改变行为且逐条解释差异后更新，不能通过删断言、放宽容差或批量重录掩盖失败。纯文档变更可跳过行为测试，提交记录说明理由。

## 仓库与文档导航

```text
packages/reader_core/  EPUB 引擎、跨层契约及核心测试
packages/reader_ui/    阅读视图、会话、交互及组件测试
apps/reader_mobile/   Android / iOS / macOS 宿主、业务存储与应用测试
docs/                 当前架构、属性审计、工程规则和专项验收
方案/                 技术设计、阶段任务、交接与历史验收记录
tool/                 按改动测试、全量入口、工程守卫与本地工具
tests/                跨包守卫与 Python 工具回归
test_corpus/          本地 EPUB 样本库，不入库
test_fonts/           OFL 测试字体
参考/                 本地参考与静态分析资料，不入库
```

- 理解当前实现：[EPUB 引擎架构](docs/epub-engine-architecture.md) → [CSS 属性审计](docs/css-property-audit.md)。
- 查看目标与任务：[技术方案](方案/技术方案.md) → [开发方案](方案/开发方案.md) → 对应阶段文件；任务勾选后使用 `perl tool/render_plan.pl` 同步看板。
- 接手验证状态：[交接文档](方案/交接文档.md) → [验收索引](方案/验收记录/README.md) → 对应专项证据。历史报告保留当次结果，当前能力以代码和最新记录为准。
- 修改代码前：[开发约定](docs/开发约定.md) 与 [测试分类规则](docs/测试分类.md)。参考项目只采用规格与算法结论，引用纪律见开发约定 §6.1。
