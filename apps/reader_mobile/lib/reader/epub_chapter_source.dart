import 'dart:math' as math;
import 'dart:typed_data';

import 'package:reader_core/api.dart' hide ComputedStyle, Paginator;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_ui/reader_session.dart';

/// 从 EPUB 文档读取章节并提供分页结果。
class EpubChapterSource implements RestylableChapterSource {
  EpubChapterSource._({
    required this.document,
    required this.baseContentWidth,
    required this.baseContentHeight,
    required this.baseStyle,
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
      baseContentWidth: contentWidth,
      baseContentHeight: contentHeight,
      baseStyle:
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

  /// 原始正文区宽（未扣设置页边距）。
  final double baseContentWidth;

  /// 原始正文区高。
  final double baseContentHeight;

  /// 书籍基础样式。
  final ComputedStyle baseStyle;

  ReaderOverrides _overrides = const ReaderOverrides();

  /// 段落布局缓存（P2-26）：同一文本+样式的重复测量直接复用。
  final TextLayoutCache _layoutCache = TextLayoutCache();

  /// 章节分页缓存：设置不变时重复进入章节不再重排。
  final Map<int, List<PageContent>> _pageCache = <int, List<PageContent>>{};

  /// 当前阅读器设置。
  ReaderOverrides get overrides => _overrides;

  /// 正文区宽：基础宽扣除设置页边距。
  double get contentWidth => math.max(
    80,
    baseContentWidth -
        (_overrides.padding?.left ?? 0) -
        (_overrides.padding?.right ?? 0),
  );

  /// 正文区高：基础高扣除设置页边距。
  double get contentHeight => math.max(
    120,
    baseContentHeight -
        (_overrides.padding?.top ?? 0) -
        (_overrides.padding?.bottom ?? 0),
  );

  /// 文本块样式：书籍样式叠加阅读器覆盖。
  ComputedStyle get style =>
      _overrides.apply(baseStyle, containingWidth: contentWidth);

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    _overrides = overrides;
    // 设置变化：段落缓存与分页缓存都要失效（P2-24 重排）。
    _layoutCache.clear();
    _pageCache.clear();
  }

  @override
  int get chapterCount => document.spine.length;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final cachedPages = _pageCache[spineIndex];
    if (cachedPages != null) {
      return cachedPages;
    }
    final aggregated = document.aggregateText(
      spineIndex,
      whiteSpace: style.whiteSpace,
    );
    final blocks = <PageBlock>[];
    void collect(EpubNode node) {
      if (node is TextBlockNode) {
        final cfi = node is TextContentNode ? node.cfi.serialize() : null;
        final text = node.text;
        if (text.trim().isEmpty) {
          return;
        }
        final layout = _layoutCache.layout(
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
              startCfi: cfi,
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
    final pages = Paginator(pageHeight: contentHeight)
        .measureChapter(blocks: blocks, spineIndex: spineIndex)
        .pages;
    _pageCache[spineIndex] = pages;
    return pages;
  }
}
