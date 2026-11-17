# reader_ui

基于 Flutter 和 `reader_core` 的阅读交互包，提供会话、预取、翻页、连续滚动、选区、标注面板和主题。文件选择、EPUB 打开、数据库及平台插件由应用宿主负责。

## 当前能力

| 入口 | 职责 |
|---|---|
| `ReaderSession` | 章节加载、打开与恢复、进度节流写入、邻页预取、重排和取消；通过宿主传入的 `ReaderProgressStore` 保存位置 |
| `ReaderPage` | 组合正文绘制、图片资源、页眉页脚、选区、高亮与笔记、注释弹窗、书签、装饰、搜索和设置面板 |
| `ReaderView` | 手势识别、点击区域与翻页意图；支持九宫格动作配置 |
| `VirtualPager` / `PageCache` | 跨章页窗口与有界页面复用 |
| `paging/` | 覆盖、堆叠覆盖、贝塞尔仿真、3D 仿真、水平滑动、无动画和连续滚动，含页面快照与图片预加载 |
| `theme/`、`panels/`、`annotations/`、`decorations/` | 阅读主题、字号与边距设置、标注和装饰交互及预览 |

统一导出位于 `lib/reader_ui.dart`。章节与目录契约直接来自 `reader_core/source/`；`reader_session.dart` 提供会话与进度契约，不再转发章节实现。

宿主先打开来源并准备设置与字体，再创建会话和阅读页；实际接入见 [EpubReaderPage](../../apps/reader_mobile/lib/reader/epub_reader_page.dart)。`ReaderSession` 的 `source`、`store`、`bookId` 必须由宿主提供，内容摘要通过 `contentRevision` 传入。退出阅读时等待会话与准备任务退出，关闭来源由其所有者负责。

## 位置与准备约定

进度以原文 CFI、内容摘要及内容证据定位，同时保留章页提示、滚动偏移和版式指纹。同内容同版式可快速恢复；重排或内容修订后重新解析内容锚点。缺少内容证据的标注不会仅凭 CFI 或引文命中自动接受，失败记录保留并展示状态。

原文、样式和注释的同步接口只消费已准备结果。会话与面板在读取前等待章节准备，预取与前台阅读使用同一调度契约，取消或过期任务不得回填结果。注释载荷随准备后的布局冻结，避免资源缓存淘汰后重排丢失注释。

视口改变且原文索引仍在准备时，百分比接口返回暂时不可定位；会话不缓存该空值，章节就绪后重新计算。实际可见章的结构与辅助定位请求分别受缓存保护。跨章翻页、滚动和跳转提交前，会话检查目标页的 CFI；有正文进度能力且索引缺失时等待原文准备，已就绪时不重复请求。

当前菜单仅提供可选 `onTts` 回调；本包没有平台朗读实现。竖排、ruby、强调符由核心布局与绘制提供，UI 消费其结果；高级场景的完整阶段验收仍待完成。

## 阅读设置与菜单细节

- 应用及阅读面板图标统一使用 `icons/app_icon.dart` 的 `AppIcon` / `AppGlyph`：沿用四底栏的 24 格坐标、1.7 线宽、圆角笔触和实心细节，尺寸、颜色及透明度跟随 `IconTheme`。底栏与评分使用 `filled` 表示选中；底栏镂空色由所在表面通过 `cutoutColor` 传入。
- 新增按钮、下拉框和弹出菜单须显式使用同一套字形；展开列表使用 `AppExpansionTile`，勾选菜单使用 `appCheckedMenuItem`。应用通过 `ActionIconThemeData` 统一自动返回和关闭图标，保留框架的路由行为。
- `ReaderMenuOverlay` 顶部、底部和抽屉使用滑动及淡入淡出，进入 280ms、退出 200ms，退出内容禁止点击；墨水屏或 `MediaQuery.disableAnimations` 为真时即时切换。抽屉提供标题、关闭按钮与抓手。
- `MarginEditor` 保留六项边距的拖动、正文预览、取消和保存，数值可点击输入小数，按各项上限校验；预览与实际正文共用页家具高度。
- `ReaderCornerInfo` 管理四角信息，`ReaderCornerRow` 显示当前章节、书名、章页、进度、分钟时钟或电池图标。整行隐藏时回收该行高度，显式边距继续保留；信息配置参与翻页快照失效。电池通过宿主的 `getBatteryStatus` 查询电量与充电状态，并监听 `com.spectacular.reader_mobile/battery` 事件通道即时更新；充电及已充满仍接电时显示闪电，未提供状态时显示未知，读取失败保留有效值。
- `ReaderFontPickerSheet` 提供字体选择、按需试读、重命名和确认移除，失败保留弹层并展示原因。宿主通过 `onLoadFont`、`onRenameFont`、`onRemoveFont` 负责注册与持久化，恢复书籍字体时关闭全书字体覆盖。

当前实现与 Android 验收范围见 [功能细节优化与 APK 验收](../../docs/功能细节优化与APK验收-2026-11-12.md)。

## 本地验证

已有本地依赖时，从仓库根目录按职责运行：

```bash
python3 tool/run_tests.py ui --analyze
python3 tool/run_tests.py resources position
python3 tool/run_tests.py layout paint
python3 tool/run_tests.py --check
```

首次配置在本包执行 `flutter pub get --offline`，日常测试与分析使用 `--no-pub`。分类依据实际行为，缓存、定位与渲染测试分别归相应职责。公共行为变化同步调用方、断言与夹具；快照变化逐条解释原因，规则见 [测试分类](../../docs/测试分类.md)。

应用整体进度见 [根 README](../../README.md)，核心边界和资源生命周期见 [EPUB 引擎架构](../../docs/epub-engine-architecture.md)。
