# reader_mobile

Spectacular Reader 的 Flutter 应用宿主，包含 Android、iOS、macOS 和 Windows 工程。项目仍在开发，当前专项验收主要覆盖 Android 真机；平台目录存在不代表已完成同等验收。

## 当前功能与职责

- `lib/main.dart` 初始化日志、当前数据库、书库和进度存储，进入书架、统计、书评、我的四页应用壳。
- `lib/library/` 负责 EPUB 文件导入、去重、内容摘要、修订替换、分组、标签和书籍生命周期。文件统一保存在 `books/<id>`，原 EPUB 不改写。
- `lib/reader/epub_reader_page.dart` 通过核心 `EpubFormatOpener` 打开书籍，将进度、标注、装饰、偏好、用户字体和背景交给 `ReaderPage`；EPUB 解析、章节准备和排版实现位于 `reader_core`。
- `lib/storage/` 使用同一个 drift 数据库保存书库、进度、标注、装饰、书评、阅读时段和设置。`AppDatabase.schemaVersion` 为 2，支持 v1 增量升级，增加编辑草稿和保留版本表，不清理用户阅读数据。
- `lib/search/scan_search_service.dart` 逐章扫描原文，返回上下文和 CFI；当前阅读搜索未使用 2-gram 索引。
- `lib/reader/reading_session_tracker.dart` 记录前台阅读时段，`lib/home/stats_page.dart` 汇总统计；`lib/diagnostics/` 提供运行事件与日志导出。

内容修订是当前业务功能：替换书籍时按原文证据重新关联进度和标注，保留书评与阅读记录；写入前校验内容摘要，拒绝过期会话覆盖。数据库打不开时应用可退回内存模式，该模式不提供持久化能力。

当前支持 EPUB。TXT、PDF 只有核心格式契约；TTS 依赖已声明、UI 有可选回调，但应用尚未接入朗读流程。全局实现状态见 [根 README](../../README.md)。

## 阅读与业务细节（2026-11-12）

| 功能 | 当前行为与实现位置 |
|---|---|
| 阅读菜单与边距 | 菜单和抽屉进入、退出有动画，墨水屏和系统减少动态效果使用即时切换；六项边距支持拖动、点击数值输入小数、预览、取消及保存。宿主由 `epub_reader_page.dart` 接入 `reader_ui`。 |
| 自定义字体 | `ReaderFontStore` 管理导入、注册、试读、重命名和移除；名称变更不改变字体身份。移除当前字体恢复书籍字体并关闭全书字体覆盖，清单与偏好持久化。 |
| 四角信息 | `ReaderSettings.cornerInfo` 独立保存四角的隐藏、章节名、书名、章内页码、全书进度、时间及电量；隐藏整行回收正文高度，显式边距继续保留。Android `MainActivity.getBatteryLevel` 提供真实电量。 |
| 封面与图标 | `home/book_cover_image.dart` 统一书架、详情、统计和书评的封面，按宽度与屏幕倍率解码、等比完整显示；缺失和失败回退书名占位。沿用 Material 图标，菜单提供语义标签和触控目标。 |
| 统计 | `home/reading_insights.dart` 为概览、趋势与热力图提供同一统计口径；新增连续／最长连续天数、日均、平均／最长单次、四时段分布、估算字速，以及按书的时长、次数、翻页和字数排行。 |
| 书评与读完 | 书评页面与 `home/finish_book_sheet.dart` 统一评分和 5000 字正文；保存成功后关闭，失败保留草稿，保存期间防止重复提交，未保存退出需确认；详情支持复制全文。 |

统计中的阅读次数是连续前台片段次数；退出、后台和再次进入会产生不同片段。跨自然日的翻页和字数按时长分配，标为估算且总数守恒；日均以实际阅读天数计算，字速不是净阅读速度测量。书评与读完标记分别保存，后者失败时会明确提示书评已保存，保留编辑器供重试。

实现、分类回归及真机覆盖见 [功能细节优化与 APK 验收](../../docs/功能细节优化与APK验收-2026-11-12.md)。

## EPUB 编辑

阅读菜单或选区菜单中的“编辑 EPUB”进入工作副本。Android 点击段落可改正文、HTML 和 class；桌面窗口展开文件树、源码标签页和本应用引擎预览。源码支持查找替换，资源工具支持目录、元数据、章节顺序与分合章。预览可切换书籍样式和当前阅读设置。

- 同名 class 写入共享 CSS。先展示全书影响范围；高优先级声明冲突时可保留作者优先级或显式统一该属性。归属清单只用于恢复，实际渲染仍来自标准 XHTML/CSS。
- 保存更新书库副本，保留书籍身份、进度、批注和书签。正文变化按内容证据迁移位置；无法确认的位置保留为待重新定位。
- 自动草稿保留未完成的源码；语法错误允许留在草稿，不能提交。过期草稿可以导出保留，但不能覆盖较新版本。
- 保留首次编辑前原版和最近一次保存前版本；恢复书籍内容不会恢复旧数据库或丢弃之后新增的笔记。原始外部 EPUB 不自动覆盖，另用“导出 EPUB”选择输出位置。
- 编辑撤销历史最多 100 项、旧资源 32 MiB，超出后释放最早历史；图片和字体按条目读取，输入期间不重新打包整本 EPUB。

相关实现位于 `lib/editing/`、`reader_core/lib/editing/`。Windows 验收入口是 `.github/workflows/epub-editor-windows.yml`，只有实际运行通过才计为平台验收，工程目录本身不代表兼容性保证。

大书编辑基准复用上述本地生成的 144 MiB、48 图、单 HTML 200 页样本，在核心包执行：

```bash
flutter test --no-pub test/editing/epub_edit_stress_test.dart \
  --dart-define=RUN_EDITOR_STRESS=true
```

报告写入 `apps/reader_mobile/dist/epub-editor-stress.json`；本地测试进程的事件循环间隔和 RSS 不代表 Android Release 帧率。

## 本地运行

使用已配置的 Flutter、Android SDK 或 Xcode。当前验证工具链为 Flutter 3.47.5、Dart 3.13.4，依赖版本与平台覆盖以 `pubspec.yaml`、锁文件及实际验收为准。

```bash
# 在本目录执行；仅在包配置缺失或依赖发生变化时准备依赖
flutter pub get --offline

# 已有依赖时复用缓存
flutter devices
flutter run --no-pub -d macos
flutter run --no-pub
```

本地缓存不足时再下载所需依赖。自定义字体、纹理与内置正文宋体/黑体均由 `pubspec.yaml` 声明；不要用网络字体替代现有资源。

## Android APK

已有依赖时的标准 Release 入口：

```bash
flutter build apk --release --no-pub --target-platform=android-arm64
```

`--no-pub` 跳过 Dart 依赖解析，Gradle 离线构建还需 `--offline`。验收 APK 使用 Flutter 配置生成、正式插件注册与本地 Gradle `:app:assembleRelease` 完成离线打包，命令和插件注册前置见 [统一实现与 APK 验收](../../docs/统一实现与APK验收-2026-11-11.md)，最新产物与安装结果见 [功能细节优化与 APK 验收](../../docs/功能细节优化与APK验收-2026-11-12.md)。

产物保存在被忽略的 `dist/`。当前包名为 `com.spectacular.reader_mobile`，应用版本为 `1.0.0+1`；开发验收包未完成商店签名和发布材料准备。覆盖安装必须使用相同签名，原开发数据的保存与本次初始数据库验收准备见专项记录。

## 验证

从仓库根目录按改动选择职责：

```bash
python3 tool/run_tests.py ui
python3 tool/run_tests.py storage position integration --analyze
python3 tool/run_tests.py css layout resources
python3 tool/run_tests.py --check
```

测试文件归类依据行为，应用包中的 CSS 测试仍属于 `css`。`integration_test/` 中的真机入口不由日常分类或 `--all` 自动运行。新增或改变业务行为时同步相关断言、夹具与索引，规则见 [测试分类](../../docs/测试分类.md)。

大型 EPUB 压力基准使用本地生成的固定样本，不下载书籍或图片：

```bash
# 仓库根目录：生成约 144 MiB、48 张大图、单 XHTML 长章
python3 tool/build_performance_epub.py

# 本目录：显式启用压力基准，日常测试默认跳过
flutter test --no-pub test/reader_perf_stress_test.dart \
  --dart-define=RUN_STRESS_BENCHMARK=true
```

默认样本在测试的 360×600、18px 参数下为 200 页，包含嵌套边框、混合字号、浮动和表格。基准检查正文、分页、CFI、重排定位及图片解码绘制，记录开书、长章跳转、热缓存、百页定位和重排耗时；使用 `STRESS_EPUB`、`STRESS_REPORT` 指定输入与 JSON 报告路径。默认产物都在忽略的 `dist/` 下。事件循环间隔与 RSS 来自本地 Flutter 测试进程，不能替代 Android Release 的帧率和内存实测；耗时不设易受机器负载影响的硬阈值。

当前架构与资源生命周期见 [EPUB 引擎架构](../../docs/epub-engine-architecture.md)，验收范围见 [验收索引](../../方案/验收记录/README.md)。
