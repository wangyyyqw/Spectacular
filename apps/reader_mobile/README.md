# reader_mobile

Spectacular Reader 的 Flutter 应用宿主，包含 Android、iOS 和 macOS 工程。项目仍在开发，当前专项验收主要覆盖 Android 真机；平台目录存在不代表已完成同等验收。

## 当前功能与职责

- `lib/main.dart` 初始化日志、当前数据库、书库和进度存储，进入书架、统计、书评、我的四页应用壳。
- `lib/library/` 负责 EPUB 文件导入、去重、内容摘要、修订替换、分组、标签和书籍生命周期。文件统一保存在 `books/<id>`，原 EPUB 不改写。
- `lib/reader/epub_reader_page.dart` 通过核心 `EpubFormatOpener` 打开书籍，将进度、标注、装饰、偏好、用户字体和背景交给 `ReaderPage`；EPUB 解析、章节准备和排版实现位于 `reader_core`。
- `lib/storage/` 使用同一个 drift 数据库保存书库、进度、标注、装饰、书评、阅读时段和设置。`AppDatabase.schemaVersion` 为 1，一次创建完整表与索引，不保留历史数据库升级或 JSON 导入流程。
- `lib/search/scan_search_service.dart` 逐章扫描原文，返回上下文和 CFI；当前阅读搜索未使用 2-gram 索引。
- `lib/reader/reading_session_tracker.dart` 记录前台阅读时段，`lib/home/stats_page.dart` 汇总统计；`lib/diagnostics/` 提供运行事件与日志导出。

内容修订是当前业务功能：替换书籍时按原文证据重新关联进度和标注，保留书评与阅读记录；写入前校验内容摘要，拒绝过期会话覆盖。数据库打不开时应用可退回内存模式，该模式不提供持久化能力。

当前支持 EPUB。TXT、PDF 只有核心格式契约；TTS 依赖已声明、UI 有可选回调，但应用尚未接入朗读流程。全局实现状态见 [根 README](../../README.md)。

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

`--no-pub` 跳过 Dart 依赖解析，Gradle 离线构建还需 `--offline`。本次 APK 使用 Flutter 配置生成、正式插件注册与本地 Gradle `:app:assembleRelease` 完成离线打包，具体命令和插件注册前置见 [统一实现与 APK 验收](../../docs/统一实现与APK验收-2026-11-11.md)。

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

当前架构与资源生命周期见 [EPUB 引擎架构](../../docs/epub-engine-architecture.md)，验收范围见 [验收索引](../../方案/验收记录/README.md)。
