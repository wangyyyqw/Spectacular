# Spectacular Reader

Spectacular Reader 是一款以本地书库为中心的 Flutter 电子书阅读应用，提供 EPUB 与 TXT 导入、中文排版、多种翻页方式、书签笔记和阅读统计，并在桌面端集成 EPUB 编辑工作台。

正文通过 EPUB 解析、CSS 计算、内容测量、分页和 Canvas 绘制呈现。阅读设置、书内样式和实际视口共同参与排版，字号或窗口变化后通过原文锚点恢复阅读位置。

项目目前处于开发阶段，主要验证范围为 Android 和 macOS。

## 主要功能

- **本地书库**：导入 EPUB；TXT 按章节规则分章并转换入库。支持书架搜索、分组、排序、置顶、多选、书籍详情和导出。
- **阅读排版**：内置宋体与黑体，支持书内字体和自定义字体；提供中文两端对齐、标点处理、表格、浮动、竖排和注音等排版能力。
- **阅读外观**：调整字号、行高、段距和六向边距，设置主题、背景及四角信息；支持字体试读和墨水屏设置。
- **应用字体**：界面默认使用内置思源宋体，可在“我的”中导入 TTF/OTF 并切换应用字体。
- **阅读导航**：目录、进度跳转、全文搜索、注释弹窗、图片预览和画廊切换；结合原文位置保存与恢复阅读进度。
- **书签与笔记**：下拉添加或移除书签，选区划线、记录想法、设置文字装饰；按书查看笔记和划线，读完后记录评分与书评。
- **阅读统计**：按日、周、月、季度和年查看图书阅读时长，提供阅读日历、按星期的每日平均、书籍排行和最近阅读记录。
- **桌面 EPUB 编辑**：资源浏览、源码与预览双向定位、查找替换、元数据与目录编辑、章节调整、样式修改、草稿恢复、保存和导出。

阅读模式包括 **覆盖、堆叠覆盖、贝塞尔仿真、3D 仿真、接续、连续滚动、水平滑动和无动画**。

## 平台状态

| 平台 | 当前范围 |
|---|---|
| Android | 阅读、书库、笔记和统计主线已有真机验证。 |
| macOS | 提供桌面阅读与 EPUB 编辑，已有编辑、保存、导出及部分本地工具链路验证。 |
| Windows | 已提供桌面工程和编辑入口，完整平台验收仍待完成。 |
| iOS | 已提供工程配置，真机与发布验收仍待完善。 |

EPUB 样式支持与平台适配持续完善，具体书籍的显示效果取决于其内容和已实现的样式规则。

## 项目结构

| 目录 | 职责 |
|---|---|
| [apps/reader_mobile](apps/reader_mobile) | Flutter 应用宿主、平台适配、本地书库、搜索、统计与编辑入口。 |
| [packages/reader_core](packages/reader_core) | EPUB 解析、TXT 转换、CSS、排版、分页、绘制、原文定位与编辑写回。 |
| [packages/reader_ui](packages/reader_ui) | 阅读会话、翻页与滚动、选区、书签、面板和主题。 |
| [packages/epub_toolkit](packages/epub_toolkit) | 桌面编辑器使用的 EPUB 转换、结构检查、图片、字体和注释处理工具。 |
| [tool](tool) / [tests](tests) | 构建入口、测试分类、工程检查及跨包工具回归。 |

应用通过本地路径依赖内部包。引擎负责内容和排版，阅读 UI 负责会话与交互，宿主负责持久化和平台能力。

## 开始使用

准备 Flutter SDK，并满足各包的 Dart `^3.13.4` 约束。Android 开发需要 Android SDK，macOS 开发需要 Xcode 及命令行工具；项目脚本使用 Python 3。

```bash
git clone https://github.com/wangyyyqw/Spectacular.git
cd Spectacular

# 在仓库根目录准备各包依赖，优先使用本地缓存
(cd packages/reader_core && flutter pub get --offline)
(cd packages/reader_ui && flutter pub get --offline)
(cd packages/epub_toolkit && flutter pub get --offline)
(cd apps/reader_mobile && flutter pub get --offline)
```

首次准备且缓存缺失时，去掉对应命令中的 `--offline` 获取所需依赖。依赖已准备后，从仓库根目录查看设备并启动应用：

```bash
flutter devices
(cd apps/reader_mobile && flutter run --no-pub -d macos)
```

Android 运行时，将 `macos` 替换为 `flutter devices` 列出的 Android 设备 ID。应用启动后，从书架导入本地 EPUB 或 TXT。

### Android APK

从仓库根目录使用现有构建脚本，默认复用 Pub 与 Gradle 缓存：

```bash
bash tool/build_apk.sh

# 仅在缓存缺失时允许获取依赖
bash tool/build_apk.sh --allow-downloads
```

该脚本构建 Android arm64 Release，产物位于 `apps/reader_mobile/dist/spectacular-reader-release.apk`。构建产物和运行日志保留在本地。

## 开发与验证

在仓库根目录按改动范围选择测试分类：

```bash
# 界面交互
python3 tool/run_tests.py ui

# 样式、布局和绘制
python3 tool/run_tests.py css layout paint --analyze

# 存储、定位与集成
python3 tool/run_tests.py storage position integration --analyze

# 查看分类与执行计划
python3 tool/run_tests.py --list
python3 tool/run_tests.py --changed --dry-run
```

分类测试使用 `flutter test --no-pub`，静态分析使用 `flutter analyze --no-pub`。设备集成测试按对应平台单独运行；本地书籍样本、截图、APK 和日志不提交到仓库。

## 资源许可

内置字体、词典与工具组件保留各自的许可文件，可查看 [字体许可](apps/reader_mobile/assets/fonts/LICENSE.txt) 和 [词典许可](packages/reader_core/third_party/hyph_en_US/LICENSE.txt)。仓库目前尚未声明项目级统一许可证。
