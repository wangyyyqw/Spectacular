import 'dart:io';
import 'dart:typed_data';

import 'package:reader_core/source/format_opener.dart';

import 'epub_chapter_source.dart';

/// 统一打开契约的 EPUB 实现，复用现有资源与排版管线。
class EpubFormatOpener implements ReaderFormatOpener<EpubChapterSource> {
  const EpubFormatOpener({this.verifyCrc});

  /// 未指定时保持原入口默认值：字节校验，文件按需读取时不校验。
  final bool? verifyCrc;

  @override
  ReaderFormat get format => ReaderFormat.epub;

  @override
  Future<EpubChapterSource> openBytes(
    Uint8List bytes, {
    ReaderOpenOptions options = const ReaderOpenOptions(),
  }) => EpubChapterSource.open(
    bytes,
    contentWidth: options.contentWidth,
    contentHeight: options.contentHeight,
    style: options.style,
    verifyCrc: verifyCrc ?? true,
    trimTextEdges: options.trimTextEdges,
    contentVersion: options.contentVersion,
  );

  @override
  Future<EpubChapterSource> openFile(
    File file, {
    ReaderOpenOptions options = const ReaderOpenOptions(),
  }) => EpubChapterSource.openFile(
    file,
    contentWidth: options.contentWidth,
    contentHeight: options.contentHeight,
    style: options.style,
    verifyCrc: verifyCrc ?? false,
    trimTextEdges: options.trimTextEdges,
    contentVersion: options.contentVersion,
  );
}
