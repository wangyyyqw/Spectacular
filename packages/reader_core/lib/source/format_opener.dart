import 'dart:io';
import 'dart:typed_data';

import '../css/computed_style.dart';
import 'chapter_source.dart';

/// 阅读文件格式；各格式由对应的打开器提供实现。
enum ReaderFormat { epub, txt, pdf }

/// 来源采用的内容布局。
enum ReaderContentLayout { reflowable, fixedPages }

/// 已打开的出版物，沿用章节加载与同步关闭契约。
abstract interface class ReaderPublicationSource
    implements ReaderChapterSource {
  ReaderFormat get format;
  ReaderContentLayout get layout;
  void close();
}

/// 打开来源时的公共排版参数。
class ReaderOpenOptions {
  const ReaderOpenOptions({
    this.contentWidth = 320,
    this.contentHeight = 480,
    this.style,
    this.trimTextEdges = true,
    this.contentVersion,
  });

  final double contentWidth;
  final double contentHeight;
  final ComputedStyle? style;
  final bool trimTextEdges;
  final String? contentVersion;
}

/// 格式打开入口；文件实现可保留资源按需读取能力。
abstract interface class ReaderFormatOpener<S extends ReaderPublicationSource> {
  ReaderFormat get format;

  Future<S> openBytes(
    Uint8List bytes, {
    ReaderOpenOptions options = const ReaderOpenOptions(),
  });

  Future<S> openFile(
    File file, {
    ReaderOpenOptions options = const ReaderOpenOptions(),
  });
}
