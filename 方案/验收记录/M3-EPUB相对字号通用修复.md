# EPUB 相对字号通用修复验收

日期：2026-11-11。修复 EPUB 通用排版链路中元素相对字号被阅读器字号覆盖的问题。
本次验收相对字号行为，逐书核查仍暂停，008 未标记整书完成。

## 1. 规则与实现

- 普通正文继续使用阅读器字号。元素通过 class、id 或行内样式声明 `em`、`rem`、
  百分比字号时，保留作者规定的比例；`font` 简写采用级联胜出的字号声明。
- 块元素的 `em`、百分比取当前元素相对作者父字号的比值，再乘阅读器字号；
  行内 `em`、百分比继承最终父字号，嵌套比例逐层相乘。
- 块和行内 `rem` 均以阅读器字号为根基准，不因作者父容器缩小而被错误放大。
- 缩放后的普通文本继续应用阅读器行高、对齐和字体覆盖设置。未设置阅读器字号时沿用原书。
- 原有全局 `body`／`p` 正文基准、绝对字号和容器盒模型策略保留；阅读器字号不注入作者级联根。
  元素相对外边距复用已有 `scaleRelativeTypography` 行为。

| 实现位置 | 作用 |
|---|---|
| [text_block_builder.dart](../../apps/reader_mobile/lib/reader/epub/text_block_builder.dart) | 块与 inside 列表标记共用字号覆盖路径；相对字号分支兼容阅读器其他排版设置 |
| [block_style_helpers.dart](../../apps/reader_mobile/lib/reader/epub/block_style_helpers.dart) | 读取显式字号或 `font` 简写，继承字号不当作新声明 |
| [chapter_style_resolver.dart](../../apps/reader_mobile/lib/reader/epub/chapter_style_resolver.dart) | 行内 `rem` 使用阅读器根字号，`em` 从最终父字号解算 |
| [computed_style.dart](../../packages/reader_core/lib/css/computed_style.dart) | `font` 简写支持大写相对长度单位，保留字体名称大小写 |

实现不依赖书名、书籍 ID 或特定章节；没有新增依赖或修改原书。

## 2. 回归与原书验证

新增 [authored_font_scale_test.dart](../../apps/reader_mobile/test/reader/authored_font_scale_test.dart)
含 10 项合成 EPUB 回归，覆盖简介三类元素、普通正文、阅读器设置变化、未设置字号、
class／id／行内 `em`／`rem`／百分比、简写与级联覆盖、行内嵌套、作者盒模型和 inside 列表。
修改前最初 9 项中 7 项失败，能复现署名和简介被提升到满字号，以及 `rem` 分母错误。

最终移动专项 **38 项通过**，核心专项 **23 项通过**，另有 008 原书探针 **2 项通过**：

```bash
cd apps/reader_mobile
flutter test --no-pub --reporter expanded \
  test/reader/authored_font_scale_test.dart \
  test/reader/reader_overrides_typography_test.dart \
  test/reader/epub/text_block_builder_test.dart \
  test/reader/zhushen_diaoming_test.dart

cd ../../packages/reader_core
flutter test --no-pub --reporter expanded \
  test/css/shorthand_test.dart \
  test/css/typography_override_test.dart \
  test/css/reader_overrides_test.dart
```

008《晋末长剑》原书 SHA-256：
`7760581db1f1a7c6efb3d82693895dedf795e94236f18639be8710b1d520045d`。
阅读器设置保持字号 **21**、行高 **1.3**、段距 **0**：

| 内容 | 原书声明 | 块与实际 run 字号 | 内嵌字体 |
|---|---|---:|---|
| spine 2 简介标题 | `p.jsmc1 { font-size: .8em; }` | 16.8 | HYWS |
| spine 2 六段简介正文 | `p.st1 { font-size: .8em; }` | 16.8 | kh |
| spine 2 署名 | 行内 `font-size: .6em` | 12.6 | kh |
| spine 4 普通正文首段 | 无特殊字号 | 21 | 原书字体 |

跨书回归使用既有《诸神愚戏》真实样本：`p.t-desc` 与 `span.t-tag` 各声明 `.8em`，
描述段为阅读器字号 × .8，标签为阅读器字号 × .8 × .8；对应旧断言按原书声明同步修正。

## 3. 真机、构建与像素复核

MEIZU 20 / Android 16，项目包 `com.spectacular.reader_mobile`，1.0.0+1，arm64 Release。
Android Use 操作与查看页面，ADB 保存 1080×2400 截图和核验安装。
覆盖安装后书架仍为 18 本，简介一屏显示六段正文和署名，原书内嵌字体保留；
设置面板复核字号 21、行高 1.3、段距 0。最终停在简介页，当前应用进程错误级别日志为空。

普通正文首段修复前后均分两行。按深色字形外接框比较，两行宽高分别保持
833×61 px、75×54 px；逐行对齐后深色掩码差异分别为 9 个像素、0 个像素。
正文上移 39～40 px 是上方装饰文字恢复 `.5em` 后所致，不是普通正文字号变化。
此测量仅比较该段，不宣称整页逐像素相同。

同日章节间距补核：标题 `h2.head1` 保留 `150%` 行高，章号与红色标题的字形净空为
27 个物理像素。英文装饰段 `.zw-x` 字号为 10.5，作者 `margin-bottom: 4em`
解算为 42 个逻辑像素，但实际 `spaceAfter` 为 0；阅读器段距 0 覆盖了装饰段的外边距，
使该行到正文的字形净空只有 18 个物理像素。标题内部行距正常，标题区到正文的间距仍需修复。
证据为 `/tmp/spectacular-title-spacing-current-20261111.png`、
`/tmp/spectacular-title-spacing-pipeline-20261111.json` 与
`/tmp/spectacular-title-spacing-pixels-20261111.json`；本次仅核查间距，未修改排版实现。

Flutter 3.47.5 / Dart 3.13.4；依赖解析和 Gradle 构建使用本地缓存：

```bash
cd apps/reader_mobile
flutter build apk --release --config-only --target-platform=android-arm64
cd android
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  ./gradlew --offline --console=plain :app:assembleRelease \
  -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart
```

正式构建配置需要刷新插件注册表，故此步骤未使用 `--no-pub`；依赖已先离线解析。
本地 Gradle 构建成功，APK 包标识与签名通过验证，`adb install -r` 成功。
更新时间 2026-11-11 11:09:11，首次安装时间保持 2026-10-31 17:59:47，
主用户数据目录仍为 `/data/user/0/com.spectacular.reader_mobile`。
验收 APK 与手机安装后的 `base.apk` 逐字节相同，SHA-256：

```text
143945bfcf04b85b2cc6ba486c1c10efaf081e8229bc002089c23ceb4ec89279
```

## 4. 全量检查与边界

三包均执行离线依赖解析、`flutter analyze --no-pub` 和全量测试，作为
`tool/run_all.sh` 的离线等价；三包静态分析均无问题。
核心边界、严格分析探针、边界违规探针与 `git diff --check` 均通过。

| 全量初跑 | 通过 | 跳过 | 失败 |
|---|---:|---:|---:|
| reader_core | 1679 | 8 | 0 |
| reader_ui | 768 | 0 | 4 |
| reader_mobile | 1080 | 6 | 12 |

移动初跑中的《诸神愚戏》旧字号断言已按原书层叠修正并在最终专项中通过。
其余失败文件用 `git archive 877c079` 建立独立基线，三包源码和依赖均指向隔离目录，
以 `--concurrency=1` 同口径复跑：基线 73 通过／12 失败，当前 75 通过／10 失败，新增失败 0。
稳定失败集合相同，共 10 项，涉及窄幅标题、开书流程、inline 块、浮动、CSS gaps、
分页更新、缓存和统计页；背景即时重绘两项存在基线和当前复跑差异，仍按既有偶发失败记录。
界面包 `prepared_decoration_flow_test.dart` 的 4 项失败与上一封面验收一致。

**全量测试尚未通过。** 本次字号行为通过专项、跨书样本和真机验证；范围外失败保留。
绝对字号等原有策略未扩展，其他设备、平台和全部 EPUB 未逐页验收。
既有两份逐书核查文档和未跟踪 EPUB 的 SHA-256 保持不变，未纳入本次提交。

## 5. 证据与来源

临时证据保留在仓库外，原书、截图、APK、日志和探针均未提交：

- 专项：`/tmp/spectacular-font-scale-final-focused-20261111.log`、
  `/tmp/spectacular-font-scale-core-focused-20261111.log`、
  `/tmp/spectacular-font-scale-real-book-20261111.log`。
- 原书字号：`/tmp/spectacular-font-scale-20261111/008简介修复后字号.json`、
  `/tmp/spectacular-font-scale-20261111/008普通正文修复后字号.json`。
- 截图：`/tmp/spectacular-font-scale-intro-final-20261111.png`、
  `/tmp/spectacular-font-scale-settings-after-20261111.png`、
  `/tmp/spectacular-font-scale-prose-{before,after}-20261111.png`。
- 像素测量与基线对照：`/tmp/spectacular-font-scale-prose-pixels-20261111.json`、
  `/tmp/spectacular-font-scale-baseline-comparison-20261111.json`。
- 构建、安装与进程：`/tmp/spectacular-font-scale-build-release-final-20261111.log`、
  `/tmp/spectacular-font-scale-install-20261111.log`、
  `/tmp/spectacular-font-scale-device-errors-20261111.log`。

[W3C CSS Values 4 字体相对长度](https://www.w3.org/TR/css-values-4/#font-relative-lengths)
用于核对 `em` 的父字号与 `rem` 的根字号语义。阅读器字号作为缩放基准是本项目策略，
没有将阅读器字号替换作者级联根后重算全部盒模型。

下一步：后续同类字号改动沿用本次合成 EPUB 与跨书回归，并另行处理已有全量失败。
