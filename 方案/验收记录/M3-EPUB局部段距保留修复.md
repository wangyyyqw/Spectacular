# EPUB 局部段距保留修复验收

日期：2026-11-11。修复标题装饰段的作者留白被阅读器段距覆盖的问题，适用于同类 EPUB。

## 1. 问题与规则

008《晋末长剑》的章节标题使用 `150%` 行高，标题内部间距正常。
下方英文装饰段 `.zw-x` 声明字号 `.5em`、`margin: 0em auto 4em auto`；
阅读器字号 21 时，段后边距已正确解算为 42 个逻辑像素，但构块时被“段距 0”覆盖，
导致正文贴近装饰行。

修复在[通用文字构块路径](../../apps/reader_mobile/lib/reader/epub/text_block_builder.dart)中逐侧选择段距：

| 声明范围 | 上下边距策略 |
|---|---|
| `p`、`.wrapper p` 等通用正文规则 | 使用阅读器段距 |
| 当前元素自身的 class、id、属性或伪类限定，以及行内样式 | 单独声明的边距保留作者计算值 |
| 仅声明段后边距 | 段前继续使用阅读器段距 |
| 标题、列表和既有特殊组件 | 沿用原有策略 |

字号和边距的声明检查复用同一入口，字号原有规则保持；逻辑边距使用已有方向映射，
多看段距别名使用既有解析结果。相邻段落仍按原路径折叠边距，显式 0 和负值也保留。
没有书名、书籍 ID 或章节特判，没有新增依赖、修改原书或修改阅读器设置。

## 2. 自动验证

新增 [authored_paragraph_spacing_test.dart](../../apps/reader_mobile/test/reader/authored_paragraph_spacing_test.dart)
共 9 项，覆盖设置变化、标题行高、装饰留白、普通正文字号和段距、class／id／行内声明、
单侧边距、逻辑属性与多看别名、通用容器规则、水平边距、零值／负值、级联和未匹配规则。
修改前首批 7 项全部失败；最终新增项全部通过。

相关专项 **56 项通过**：

```bash
cd apps/reader_mobile
flutter test --no-pub --reporter expanded \
  test/reader/authored_paragraph_spacing_test.dart \
  test/reader/reader_overrides_typography_test.dart \
  test/reader/authored_font_scale_test.dart \
  test/reader/epub/text_block_builder_test.dart \
  test/reader/prose_spacing_defaults_test.dart \
  test/reader/zhushen_diaoming_test.dart
```

008 原书临时探针 **3 项通过**：标题两行及 `150%` 行高保持；装饰字号 10.5、
`4em` 留白折叠到正文段前 42；普通正文块与 run 仍为字号 21，后续段距 0。
简介标题／正文／署名仍分别为 16.8／16.8／12.6，原书内嵌字体保留。

三包离线解析依赖、静态分析与全量测试作为 `tool/run_all.sh` 的离线等价执行。
三包静态分析、核心边界、严格分析探针、边界违规探针及 `git diff --check` 均通过。

| 全量测试 | 通过 | 跳过 | 失败 |
|---|---:|---:|---:|
| reader_core | 1679 | 8 | 0 |
| reader_ui | 768 | 0 | 4 |
| reader_mobile | 1091 | 6 | 10 |

移动端 10 项失败与字号修复前后已核对的稳定失败集合一致，界面包 4 项失败也与之前一致；
本次未重建基线，复用上一轮独立基线记录比较失败集合。**全量测试尚未通过，新增失败 0。**

## 3. 真机与构建

MEIZU 20 / Android 16，1080×2400；Android Use 操作与查看，ADB 保存截图和核验安装。
阅读器设置在安装前后均为字号 **21**、行高 **1.3**、段距 **0**。

- 装饰行到正文的字形净空由 18 增至 136 个物理像素，新增 118 px 与 42 个逻辑像素留白相符。
- 标题和英文装饰行的字形位置、宽高保持；普通正文首段两行仍为 833×61 px、75×54 px，换行保持。
- 前进至第 2 页后返回，第 1 页留白保持；最终停在当前章节第 1 页。
- 覆盖安装成功，书架仍 18 本；首次安装时间和主用户数据目录保持，当前应用进程错误级别日志为空。

Flutter 3.47.5 / Dart 3.13.4，正式构建配置刷新插件注册表，再使用本地 Gradle 缓存构建：

```bash
cd apps/reader_mobile
flutter build apk --release --config-only --target-platform=android-arm64
cd android
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
  ./gradlew --offline --console=plain :app:assembleRelease \
  -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart
```

Gradle 51 秒构建成功，包标识、arm64 架构与 APK 签名验证通过；更新时间为
2026-11-11 11:57:46。验收 APK 与手机安装后的 `base.apk` 逐字节相同，SHA-256：

```text
ecbd20762bee5104b5a49d0b11db17b1f2f1c5af101a482c12fc8c23ff737f70
```

## 4. 证据与剩余范围

临时文件均在仓库外，截图、日志、原书和 APK 未提交：

- 真机：`/tmp/spectacular-authored-spacing-{before,after,final}-20261111.png`、
  `/tmp/spectacular-authored-spacing-settings-{before,after}-20261111.png`。
- 原书与像素：`/tmp/spectacular-authored-spacing-real-after-20261111.json`、
  `/tmp/spectacular-authored-spacing-pixels-20261111.json`。
- 验证：`/tmp/spectacular-authored-spacing-focused-final-20261111.log`、
  `/tmp/spectacular-authored-spacing-real-book-20261111.log`、
  `/tmp/spectacular-authored-spacing-baseline-comparison-20261111.json`。
- 构建与安装：`/tmp/spectacular-authored-spacing-build-release-20261111.log`、
  `/tmp/spectacular-authored-spacing-install-20261111.log`、
  `/tmp/spectacular-authored-spacing-device-errors-20261111.log`。

本次只修复文字块局部边距覆盖，容器、图片和表格的既有段距策略未扩展。
其他设备和全部 EPUB 未逐页验收，008 未标记整书完成，逐书核查仍暂停。

下一步：后续同类边距改动沿用本次回归；另行处理既有全量失败。
