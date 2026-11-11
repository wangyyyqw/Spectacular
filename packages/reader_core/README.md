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

书籍资源由 `BookResources` 唯一持有关闭权；排版输入通过 `LayoutSnapshot` 冻结，取消或过期作业不能提交结果。应用原来的章节入口保留兼容导出，不会创建第二份实现或缓存。

模块与全部迁移文件的职责见 [EPUB 引擎架构](../../docs/epub-engine-architecture.md)，样式取值、消费路径与明确边界见 [CSS 属性审计](../../docs/css-property-audit.md)。

使用本地依赖验证：

```sh
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
```
