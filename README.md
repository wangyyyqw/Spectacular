<div align="center">
  <img src="apps/reader_mobile/assets/branding/app_icon.png" alt="阅微Extend图标" width="128" />
  <h1>阅微Extend</h1>
  <p>本地书库 · 中文排版 · EPUB 编辑</p>

![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter&logoColor=white)
![EPUB 与 TXT](https://img.shields.io/badge/%E6%A0%BC%E5%BC%8F-EPUB%20%7C%20TXT-795548)
![开发中](https://img.shields.io/badge/%E7%8A%B6%E6%80%81-%E5%BC%80%E5%8F%91%E4%B8%AD-orange)
[![原创代码 GPLv3](https://img.shields.io/badge/%E5%8E%9F%E5%88%9B%E4%BB%A3%E7%A0%81-GPLv3-blue)](LICENSE)

</div>

阅微Extend（Spectacular Reader）是一款基于 Flutter 的电子书阅读器。导入 EPUB 或 TXT 后，可以调整阅读排版、管理书签与笔记、查看阅读统计；桌面端还提供 EPUB 编辑工作台，用于修改正文、样式和书籍结构。

项目当前主要验证 Android 和 macOS，平台能力与发布前待确认事项见下文。

## 功能

| 场景 | 当前能力 |
| --- | --- |
| **导入与书库** | 本机 EPUB/TXT 导入；百度、夸克、阿里、123、天翼、PikPak、蓝奏个人网盘选书导入；TXT 编码选择、章节识别与正则重新分章；书架搜索、分组、排序、置顶、多选和导出。 |
| **中文阅读** | 书内 XHTML 与 CSS 解析，中文两端对齐、标点处理、表格、浮动、竖排、注音及图片排版；阅读菜单可切换原文、简体或繁体显示，使用原生 OpenCC 按词组转换，不改写原书。 |
| **阅读外观** | 仅内置思源宋体中文精简版（常规、粗体），支持书内字体或导入字体；调整字号、行高、段距、六向边距、主题、背景及四角信息。 |
| **翻页与导航** | 八种阅读方式，目录、进度跳转、全文搜索、脚注弹窗、图片预览与画廊；支持音量键翻页和墨水屏设置。 |
| **书签与笔记** | 下拉添加书签，选区划线、记录想法、设置文字装饰；按书查看笔记与划线。 |
| **听书** | 系统 TTS 与离线模型可切换，离线模型预热与短首段加快起播；阅读菜单中的悬浮条支持音色、语速、定时暂停、暂停继续及取消，旁白和对白可分别配置；支持句段高亮、画面跟随和 Android 锁屏后台续读。 |
| **书单与书评** | 创建书单、归集书籍，标记读完后记录评分与书评。 |
| **阅读统计** | 顶部阅读总览、图书阅读时长、阅读日历、阅读排行与最近阅读记录。 |
| **离线查看与补传** | 阅微、野社、书源搜索、网盘目录和词典等页面在服务不可用时展示已缓存的内容。阅读时长、进度、笔记和书评可继续在本机保存；阅微恢复连接后会自动补传并刷新。首次未加载的内容仍需联网。 |
| **桌面编辑** | EPUB 资源浏览、源码与预览双向定位、CSS 属性与值补全、内置样式库、查找替换、元数据与目录编辑、章节调整、草稿恢复、保存和导出。 |
| **本地 EPUB 工具** | EPUB 2／3 转换、简繁转换、结构检查、图片处理、字体子集化、注释处理与拼音标注。 |

阅读方式包括：**覆盖、堆叠覆盖、仿真、3D、接续、连续滚动、水平滑动、无动画**。

在「我的 → 设置 → 主题取色 → 配色方案」可选清蓝、墨纸、青竹、素笺。配色与经典／Material 3 控件风格独立；全局壁纸取色优先，关闭后恢复所选方案，不改变书籍正文主题。添加想法和文字装饰共用阅读设置的分栏面板：安卓从底部打开，Windows 从侧边打开，放弃未保存的修改前会询问。

正文由项目中的 EPUB 引擎完成解析、测量、分页和 Canvas 绘制。书内样式、阅读设置与窗口尺寸共同决定版式；调整字号、边距或窗口后，通过原文锚点重新定位阅读位置。

## 平台状态

| 平台 | 当前范围 |
| --- | --- |
| **Android** | 当前主要验证平台，阅读、书库、笔记和统计主线已有真机验证。 |
| **macOS** | 提供桌面阅读与 EPUB 编辑，已有编辑、保存、导出及部分本地工具验证。 |
| **Windows** | 已提供桌面工程、编辑入口和手动触发的验收工作流，完整平台验收待完成。 |
| **iOS** | 已提供工程配置，真机与发布验收待完善。 |

项目仍有以下边界：

- EPUB 样式支持持续完善，尚不具备完整浏览器级 CSS 兼容性。
- TXT 导入后转换为 EPUB，沿用统一的阅读与书库流程。
- PDF 阅读尚未接入应用流程。
- 听书从当前阅读位置开始，耳机按钮打开控制面板；Android 锁屏或切换应用后继续播放，通知栏和锁屏可暂停、继续、结束，其他平台仍在后台暂停、返回后手动继续。退出阅读页或划掉应用任务结束。同一句跨页连续播放，离线按真实音频位置翻页并裁剪接缝多余静音，系统按实际字词回调跟随。手动翻页或跳章解除画面跟随，听书仍沿原顺序继续，可从面板回到朗读位置；后台不驱动画面，返回前台再跟随最新原文位置。位置只保留在本次阅读中，不在进程被终止后自动恢复。离线音色单独下载，系统字词高亮与暂停精度取决于设备引擎；离线只高亮当前句段。
- 本地书库 EPUB 支持在阅读时长按正文，点「编辑」修改所在段落。单层标签只显示文字；含行内标签、自闭合元素或选中多个同级段落时显示原始 HTML。标签未闭合或嵌套不匹配时，抽屉提示原因并保留输入；保存成功后自动重开新版继续阅读。在线阅读不提供此入口，完整 EPUB 工作台仍仅面向桌面端。
- 构建产物用于开发验证，商店签名与正式发布流程尚未完成。

## 合并主线的约定

`ReaMicro` 合并 `main` 前，先从共同祖先梳理待合入提交，审计所有会影响界面、交互和相关测试的差异，包括 Git 能自动合并的改动。以阅微现有主题、公共组件和交互为准：无差异的改进可以采纳；有益但风格不同的改进按本分支样式适配；会导致体验回退的改动只迁移有用逻辑。合并后定向验证受影响的界面和已有优化，说明主要取舍，不为通过主线测试而改回主线样式。

## 开始使用

当前以源码构建作为安装入口。准备好环境后，克隆仓库并运行应用，从书架导入本地 EPUB 或 TXT。

### 准备环境

- **Flutter / Dart**：当前 [Windows 工作流](.github/workflows/epub-editor-windows.yml) 固定 Flutter `3.47.5`；各包要求 Dart `^3.13.4`。
- **Android**：Android SDK、与当前 Gradle 兼容的 JDK，以及设备或模拟器。
- **macOS**：Xcode 及命令行工具。
- **辅助工具**：Python 3；Android 构建脚本使用 Bash，合成 EPUB 样本生成还需要 `zip` 命令。

### 获取代码与依赖

```bash
git clone https://github.com/wangyyyqw/Spectacular.git
cd Spectacular

(cd packages/reader_core && flutter pub get --offline)
(cd packages/reader_ui && flutter pub get --offline)
(cd packages/epub_toolkit && flutter pub get --offline)
(cd apps/reader_mobile && flutter pub get --offline)
```

上述命令优先使用本地缓存。首次准备且缓存不足时，去掉对应命令的 `--offline` 获取依赖，再继续后续步骤。

### 运行应用

```bash
cd apps/reader_mobile
flutter devices
flutter run --no-pub
```

存在多个设备时，按提示选择，或通过 `-d` 指定设备。macOS 桌面可直接运行：

```bash
flutter run --no-pub -d macos
```

## 构建应用

### Android APK

准备依赖后，从仓库根目录执行：

```bash
bash tool/build_apk.sh
```

脚本使用 Flutter `--no-pub` 与 Gradle `--offline` 构建 arm64 Release APK，保存到：

```text
apps/reader_mobile/dist/spectacular-reader-release.apk
```

完成后会输出文件大小与 SHA-256；下载文件夹存在时，还会复制一份 APK。Dart 调试符号单独保存在 `apps/reader_mobile/dist/symbols/<构建时间>/`，同目录记录对应 APK 的 SHA-256，排查该版本崩溃时需保留这份符号。原生库在 APK 中压缩，安装时由系统解压，因此下载体积与安装占用不同。

仅在构建明确提示缓存缺失时，允许补齐依赖：

```bash
bash tool/build_apk.sh --allow-downloads
```

本分支 Android 包名为 `com.spectacular.reamicro`；未配置发布密钥时，Release 构建沿用开发签名。覆盖安装已有应用时，应保持相同包名与签名，以保留应用数据。

### macOS 应用

在应用目录执行：

```bash
cd apps/reader_mobile
flutter build macos --release --no-pub
```

产物位于 `build/macos/Build/Products/Release/reader_mobile.app`。

如需打包 WebP 转换工具，先在本机准备 Homebrew 和 `cwebp`，再执行：

```bash
bash ../../packages/epub_toolkit/tool/bundle_cwebp_macos.sh \
  "$PWD/build/macos/Build/Products/Release/reader_mobile.app"
```

该脚本复制本地工具、依赖动态库与许可证，并重新签名应用。现有工具验收基于 Apple Silicon；Intel Mac 需要对应架构的组件及单独验证。

## 项目结构

| 目录 | 职责 |
| --- | --- |
| [apps/reader_mobile](apps/reader_mobile) | 应用宿主、平台适配、书库、搜索、统计、持久化与桌面编辑入口。 |
| [packages/reader_core](packages/reader_core) | EPUB 解析、TXT 转换、CSS、排版、分页、绘制、原文定位与编辑写回。 |
| [packages/reader_ui](packages/reader_ui) | 阅读会话、翻页与滚动、选区、书签、面板和主题。 |
| [packages/epub_toolkit](packages/epub_toolkit) | 桌面编辑器使用的 EPUB 转换、结构检查、图片、字体与注释处理工具。 |
| [tool](tool) | 构建脚本、测试分类、工程检查和诊断工具。 |
| [tests](tests) | 跨包工具回归、工程约束检查与合成 EPUB 样本生成。 |

主要代码入口：[EPUB 打开](packages/reader_core/lib/epub/epub_format_opener.dart) · [阅读 UI](packages/reader_ui/lib/reader_ui.dart) · [应用接入](apps/reader_mobile/lib/reader/epub_reader_page.dart) · [桌面编辑](apps/reader_mobile/lib/editing)

## 开发与测试

各包通过本地路径依赖连接。修改后按受影响范围运行具体测试；以下命令均从仓库根目录执行：

```bash
# 翻页方式与控制器
(cd packages/reader_ui && flutter test --no-pub \
  test/paging/page_turn_mode_test.dart \
  test/paging/page_turn_controller_test.dart)

# CSS 扩展属性解析
(cd packages/reader_core && flutter test --no-pub \
  test/css/private_properties_test.dart)

# 阅读设置的存储与交互
(cd apps/reader_mobile && flutter test --no-pub \
  test/reader/settings_flow_test.dart)

# 本地 EPUB 工具分派
(cd packages/epub_toolkit && flutter test --no-pub \
  test/local_dispatch_test.dart)
```

静态分析在对应包执行 `flutter analyze --no-pub`。真机与桌面窗口测试位于应用的 `integration_test/`，须单独选择设备运行。

仓库另有 [分类测试入口](tool/run_tests.py) 与 [分类配置](tool/test_groups.json)。可按职责选择测试；`--all` 覆盖四个包的本地测试及 Python 工具回归，`--check` 校验未分类条目与失效规则。

合成样本可通过 `python3 tests/corpus/build_epubs.py` 重建至 `test_corpus/`。私人书籍、数据库、截图、日志和构建产物仅用于本地验证，不随源码提交。

## 许可证

本项目有权发布的原创代码采用 GNU GPL v3.0（GPL-3.0-only）。分发基于本项目代码的衍生作品时，须将该衍生作品整体按 GPL v3.0 发布，并提供对应源代码。第三方代码、字体、数据和模型继续遵守各自的原始许可证，详见[第三方资源与来源说明](THIRD_PARTY_NOTICES.md)。

## 常见问题

**为什么修改字号或窗口后页码会变化？**

页码由当前版式决定。字号、字体、边距和视口改变后会重新分页，阅读器通过原文锚点恢复位置，因此重排前后的页码可以不同。

**离线安装依赖或打包失败怎么办？**

先核对工具链配置，再查看是否确实缺少缓存。缺少 Dart 依赖时，去掉对应 `flutter pub get` 的 `--offline`；Android 构建缺少缓存时使用 `--allow-downloads`。其他编译错误按日志定位。

**如何反馈一本书的显示问题？**

提供平台、应用版本、章节位置、阅读设置、复现步骤及截图。若需要附件，请提供有权分享的最小 EPUB 样本，并说明预期效果。
