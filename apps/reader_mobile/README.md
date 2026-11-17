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

## 阅微同步

- `lib/rea_micro/` 保存阅微账号令牌、书籍关联、阅读时长台账和阅读位置同步状态。令牌只进入应用私有设置，不写日志或诊断导出。
- 支持邮箱验证码登录，也支持发现同一局域网内已登录的阅微设备并通过 RSA 一次性公钥换取令牌。Android 扫描期间持有 `MulticastLock`；iOS/macOS 首次使用需允许访问本地网络。
- Windows 发现设备前会筛除无法加入 mDNS 组播的虚拟或断开网卡，并从每块可用网卡分别发送查询；单个网卡返回 `10042/WSAENOPROTOOPT` 不再中断整个发现流程。
- 登录后可在「阅微同步」页开启「以阅微为唯一数据源」。开启时按书名和作者自动关联本地书籍，统计页改为展示阅微概览、周/月/年趋势、最近 30 天和全部书籍阅读记录；本地未导入的云端书籍只展示记录。
- 阅读页落盘位置后记录 CFI、章节名与全书百分比，经节流上报 `rest/reader/update-read-progress`；启动、恢复前台、关闭阅读页、手动同步以及唯一数据源模式每两分钟拉取 `rest/reader/get-read-progress`。本地待上报位置与云端位置按最后修改时间比较，较新者胜出，避免旧设备覆盖新进度。
- 唯一数据源模式会继续上报本地新增阅读时段，并同步刷新云端统计；退出登录或登录失效时自动关闭该模式。
- `_reamicro-sync._tcp` 使用阅微的 `MANIFEST <字节长度>` 命令帧读取清单，兼容设备返回的 JSON 与 CBOR 负载。阅微 UUID 与本地书籍标识来源不同，依次按本地标识、云端关联和唯一书名加作者匹配书籍；本地尚有未上报位置时保留本地，已应用的远端位置可按书籍关联继续上报云端。
- 时长与位置分别同步；“立即同步阅读数据”会依次执行两者。局域网同步会读取 `GET_FILES` 文件帧，逐文件校验大小和 MD5，重建 EPUB 后自动导入本地缺失的同账号书籍，并继续合并阅读位置；批注仍不通过局域网传输。

当前支持 EPUB。TXT、PDF 只有核心格式契约；TTS 依赖已声明、UI 有可选回调，但应用尚未接入朗读流程。全局实现状态见 [根 README](../../README.md)。

## 阅读与业务细节（2026-11-12）

| 功能 | 当前行为与实现位置 |
|---|---|
| 阅读菜单与边距 | 菜单和抽屉进入、退出有动画，墨水屏和系统减少动态效果使用即时切换；六项边距支持拖动、点击数值输入小数、预览、取消及保存。宿主由 `epub_reader_page.dart` 接入 `reader_ui`。 |
| 自定义字体 | `ReaderFontStore` 管理导入、注册、试读、重命名和移除；名称变更不改变字体身份。移除当前字体恢复书籍字体并关闭全书字体覆盖，清单与偏好持久化。 |
| 四角信息 | `ReaderSettings.cornerInfo` 独立保存四角的隐藏、章节名、书名、章内页码、全书进度、时间及电量；隐藏整行回收正文高度，显式边距继续保留。Android `ReaderBatteryHandler` 通过 `MainActivity.getBatteryStatus` 和电池事件通道提供真实电量与充电状态；充电或已充满仍接电时显示闪电。 |
| 封面与图标 | `home/book_cover_image.dart` 统一书架、详情、统计和书评的封面，按宽度与屏幕倍率解码，等比缩放并居中裁切铺满卡片；缺失和失败回退书名占位。沿用 Material 图标，菜单提供语义标签和触控目标。 |
| 统计 | 依次展示图书时长、阅读日历、每日平均、阅读排行和最近阅读。顶部摘要、七日节奏、概览、趋势图及其明细、阅读热力图、阅读习惯和阅读分布展示已移除。`home/stats_page.dart` 的统计加载与汇总字段、`home/reading_insights.dart` 的数据接口继续保留，仍可提供今日／累计／逐日时长、书架数量与进度、已开始／已读完数量、字数、翻页次数、逐日阅读片段、连续天数、单次均值和时段偏好。 |
| 图书时长 | `home/book_duration_chart.dart` 按日、周、月、季度和年展示投入；日期入口可跳转到有记录的时段，切换周期保留日期。合计时长固定显示在圆环中央，点选后在时长下方显示单书占比。书名在圆环下方左对齐列表显示，最多四本书名加“其他”，不足四本按实际数量展示。每项展示时长和占比，点选书名或扇区查看完整书名，“全部”与“其他”进入当前周期明细。 |
| 阅读日历 | `home/reading_calendar.dart` 复用有效阅读会话，按月展示实际阅读日期；同书连续阅读日期在周内尽量合并为色条，跨周重新起行。单日四本以内全部显示，超过四本保留时长前三本并以“+N 本”提示其余数量；所有格子统一为六本书所需的固定高度，非本月日期不绘制格子。左右箭头可浏览前后月份，包含无记录和未来月份，年月仅作标题展示；未来日期不打开阅读明细。点击过去或当天日期查看全部书名与当日时长；窄屏或大字号可横向浏览。详情中的“当前已读完”表示现有进度状态，不推断具体读完日期。 |
| 统计页布局 | 宽屏内容居中限宽，图书时长、排行和最近阅读统一文字与列表间距；长书名最多显示两行，窄屏或大字号时将时长移至书名下方。每日平均的数值保留在花瓣内，数值与单位分行并按花瓣轮廓缩放，大字号时改用可换行的星期列表；选中星期后可通过“小时分布”按钮进入该星期最近阅读日。 |
| 书评与读完 | 书评页面与 `home/finish_book_sheet.dart` 统一评分和 5000 字正文；保存成功后关闭，失败保留草稿，保存期间防止重复提交，未保存退出需确认；详情支持复制全文。 |

统计中的阅读次数是连续前台片段次数；退出、后台和再次进入会产生不同片段。跨自然日的翻页和字数按时长分配，标为估算且总数守恒；日均以实际阅读天数计算，字速不是净阅读速度测量。书评与读完标记分别保存，后者失败时会明确提示书评已保存，保留编辑器供重试。

实现、分类回归及真机覆盖见 [功能细节优化与 APK 验收](../../docs/功能细节优化与APK验收-2026-11-12.md)。

## EPUB 编辑

EPUB 编辑仅在桌面端提供，Android 和 iOS 阅读菜单与选区菜单均不显示编辑入口。当前已完成 macOS 编辑链路验收，Windows 暂缓验收。桌面阅读菜单或选区菜单进入工作副本，窗口展开文件树、源码标签页、本应用引擎预览和可折叠样式检查器。源码与预览支持精确双向定位，检查器显示元素、祖先、同名类生效值和作者声明来源。源码支持查找替换，资源工具支持目录、元数据、章节顺序与分合章。预览可切换书籍样式和当前阅读设置。

- 同名 class 写入共享 CSS。先展示全书影响范围；高优先级声明冲突时可保留作者优先级或显式统一该属性。归属清单只用于恢复，实际渲染仍来自标准 XHTML/CSS。
- 保存更新书库副本，保留书籍身份、进度、批注和书签。正文变化按内容证据迁移位置；无法确认的位置保留为待重新定位。
- 自动草稿保留未完成的源码；语法错误允许留在草稿，不能提交。过期草稿可以导出保留，但不能覆盖较新版本。
- 保留首次编辑前原版和最近一次保存前版本；恢复书籍内容不会恢复旧数据库或丢弃之后新增的笔记。原始外部 EPUB 不自动覆盖，另用“导出 EPUB”选择输出位置。
- 编辑撤销历史最多 100 项、旧资源 32 MiB，超出后释放最早历史；图片和字体按条目读取，输入期间不重新打包整本 EPUB。
- 预览按正文、CSS 导入、图片和字体等资源依赖失效，未受影响的章节复用准备结果；章节结构最多缓存 3 章，完成布局仍遵循 64 MiB 缓存上限。

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
# 从仓库根目录运行；默认全部复用缓存
tool/build_apk.sh

# 仅在提示缓存缺失后允许下载所需依赖
tool/build_apk.sh --allow-downloads
```

脚本依次使用 `flutter build apk --release --no-pub --config-only --target-platform=android-arm64` 生成配置、当前本地 SDK 的正式入口刷新 Release 插件注册，以及 `./gradlew --offline :app:assembleRelease` 打包；默认已有 Dart 包配置时不运行 Pub。缓存缺失后使用 `--allow-downloads` 会先补齐 Dart 包，再允许 Gradle 下载所需依赖。历史命令和插件注册前置见 [统一实现与 APK 验收](../../docs/统一实现与APK验收-2026-11-11.md)，最新产物与安装结果见 [功能细节优化与 APK 验收](../../docs/功能细节优化与APK验收-2026-11-12.md)。

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
