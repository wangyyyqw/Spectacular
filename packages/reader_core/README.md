# reader_core

基于 Flutter 的阅读核心，提供 EPUB 资源读取、文档解析、CSS 计算、构块测量、分页、Canvas 绘制及 CFI 定位。应用与 `reader_ui` 依赖核心；核心不依赖应用、UI 包或平台插件。

`api.dart` 汇总跨层契约和模型。统一打开契约位于 `source/format_opener.dart`，EPUB 实现从 `epub/epub_format_opener.dart` 导入。TXT、PDF 已预留格式和重排／固定页能力描述，尚无解析器。

下面的函数可在已经初始化 Flutter binding 的应用或测试中调用。文字测量使用主 isolate，文件来源继续按需读取资源。

```dart
import 'dart:io';

import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';

Future<List<PageContent>> loadFirstChapter(File file) async {
  final source = await const EpubFormatOpener().openFile(file);
  try {
    return await source.loadChapter(0);
  } finally {
    source.close();
    await source.preparationsStopped;
  }
}
```

书籍资源由 `BookResources` 唯一持有关闭权；排版输入通过 `LayoutSnapshot` 冻结，取消或过期作业不能提交结果。应用与测试直接导入核心模块，章节契约从 `source/chapter_source.dart` 导入，文字布局从 `layout/line_breaker.dart` 导入。

原文、样式和注释只由可取消的准备任务生成。同步访问只消费已准备缓存；读取原文位置或满屏分析前，等待 `source.loadAnchorChapter(spine)` 或 `source.loadChapter(spine)`，百分比跳转使用 `source.prepareCfiForReadingPercent(percent)`。

实际阅读章的结构独立于辅助定位请求固定在有界缓存中。页面与原文索引分别缓存，页面已预加载不代表原文索引仍然就绪；跨章提交位置前应检查目标 CFI，缺失时等待原文准备。视口变化后索引尚未准备时，`readingPercentForCfi` 按不可定位契约返回 `null`，不会同步解析；准备完成后重新计算比例。

UA 默认值通过 `uaRules()` 统一参与 `Cascade.compute()`，CSS 加载、行内样式与 Flex 构块各使用一个异步入口。全部视口单位在样式计算时按 `LayoutSnapshot` 冻结成像素；百分比保留到布局阶段，按包含块解析。准备后的布局保存注释载荷，资源缓存淘汰不触发隐式同步重解析。

已具备字体、图片、浮动、表格、ruby、强调符、竖排及连续流布局等具体能力；高级取值和组合场景仍有明确边界。核心依赖 Flutter 的文字测量、字体注册与 Canvas，不能作为纯 Dart 无界面引擎运行。

模块职责与运行契约见 [EPUB 引擎架构](../../docs/epub-engine-architecture.md)，样式取值、消费路径与明确边界见 [CSS 属性审计](../../docs/css-property-audit.md)，应用整体进度见 [根 README](../../README.md)。

从仓库根目录按改动职责使用本地依赖验证，分类与预期同步规则见 [测试分类](../../docs/测试分类.md)：

```sh
python3 tool/run_tests.py css
python3 tool/run_tests.py layout paint
python3 tool/run_tests.py resources position integration --analyze
```
