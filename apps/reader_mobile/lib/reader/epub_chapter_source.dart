import 'dart:typed_data';

import 'package:reader_core/api.dart' hide ComputedStyle, Paginator;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_ui/reader_session.dart';

/// 从 EPUB 文档读取章节并提供分页结果。
class EpubChapterSource implements ReaderChapterSource {
  EpubChapterSource._({
    required this.document,
    required this.contentWidth,
    required this.contentHeight,
    required this.style,
  });

  /// 打开 EPUB 并创建来源。
  static Future<EpubChapterSource> open(
    Uint8List bytes, {
    double contentWidth = 320,
    double contentHeight = 480,
    ComputedStyle? style,
  }) async {
    final result = await openEpub(bytes);
    final document = result.document;
    if (document == null) {
      throw StateError(result.report.message ?? '打开 EPUB 失败');
    }
    return EpubChapterSource._(
      document: document,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      style:
          style ??
          ComputedStyle(const <String, String>{
            'font-size': '16px',
            'line-height': '1.5',
            'font-family': 'serif',
          }),
    );
  }

  /// 已打开文档。
  final EpubDocumentImpl document;

  /// 正文区宽。
  final double contentWidth;

  /// 正文区高。
  final double contentHeight;

  /// 文本块样式。
  final ComputedStyle style;

  @override
  int get chapterCount => document.spine.length;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final aggregated = document.aggregateText(
      spineIndex,
      whiteSpace: style.whiteSpace,
    );
    final blocks = <PageBlock>[];
    void collect(EpubNode node) {
      if (node is TextBlockNode) {
        final text = node.text;
        if (text.trim().isEmpty) {
          return;
        }
        final layout = TextLayoutEngine.layout(
          text: text,
          style: style,
          maxWidth: contentWidth,
        );
        if (layout.lineCount > 0) {
          blocks.add(
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: contentWidth,
            ),
          );
        }
      } else if (node is BlockNode) {
        for (final child in node.children) {
          collect(child);
        }
      } else if (node is InlineNode) {
        for (final child in node.children) {
          collect(child);
        }
      }
    }

    collect(aggregated.root);
    return Paginator(pageHeight: contentHeight)
        .measureChapter(blocks: blocks, spineIndex: spineIndex)
        .pages;
  }
}
