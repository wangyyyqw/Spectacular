import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/annotation_layer.dart';
import 'package:reader_ui/annotations/decorations.dart';
import 'package:reader_ui/annotations/thought_marker.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

String _cfi(int spine, int offset) =>
    'epubcfi(/6/${(spine + 1) * 2}!/4/2/1:$offset)';

String _chapterText(int spine) => 'word in chapter $spine';

String _anchorData(int spine) => AnchorRecord(
  original: AnchorBook(
    revision: 'reader-layout',
    chapters: [
      AnchorChapter(
        spineIndex: spine,
        href: '$spine.xhtml',
        blocks: [AnchorBlock(cfi: _cfi(spine, 0), text: _chapterText(spine))],
      ),
    ],
  ).capture(_cfi(spine, 0), endCfi: _cfi(spine, 4))!,
).encode();

class _Source implements ReaderChapterSource {
  final style = ComputedStyle(const {
    'font-family': 'Ahem',
    'font-size': '16px',
    'line-height': '1.5',
  });

  @override
  int get chapterCount => 3;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async =>
      Paginator(pageHeight: 160)
          .measureChapter(
            spineIndex: spineIndex,
            blocks: [
              PageBlock(
                layout: TextLayoutEngine.layout(
                  text: _chapterText(spineIndex),
                  style: style,
                  maxWidth: 160,
                ),
                style: style,
                startCfi: _cfi(spineIndex, 0),
              ),
            ],
          )
          .pages;
}

class _Annotations implements ReaderAnnotationStore {
  @override
  Future<List<ReaderAnnotation>> list() async => [
    for (var spine = 0; spine < 3; spine++)
      ReaderAnnotation(
        id: 'thought-$spine',
        type: ReaderAnnotationType.thought,
        startCfi: _cfi(spine, 0),
        endCfi: _cfi(spine, 4),
        quote: 'word',
        note: '第${spine + 1}章想法',
        anchorData: _anchorData(spine),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];

  @override
  Future<ReaderAnnotation?> add({
    required ReaderAnnotationType type,
    required String startCfi,
    required String endCfi,
    required String quote,
    String? contextBefore,
    String? contextAfter,
    int? color,
    ReaderAnnotationStyle style = ReaderAnnotationStyle.background,
    double? opacity,
    String? note,
  }) async => throw UnsupportedError('只读回归存储');

  @override
  Future<void> update(
    String id, {
    ReaderAnnotationType? type,
    int? color,
    ReaderAnnotationStyle? style,
    double? opacity,
    String? note,
    bool clearNote = false,
  }) async => throw UnsupportedError('只读回归存储');

  @override
  Future<void> remove(String id) async => throw UnsupportedError('只读回归存储');
}

void main() {
  testWidgets('连续滚动邻章可见时即绘制想法，不必等当前章进度切换', (tester) async {
    final source = _Source();
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            annotations: _Annotations(),
            bookId: 'neighbor-thoughts',
            overrides: const ReaderOverrides(),
            pageTurnMode: PageTurnMode.scroll,
            showPageFooter: false,
            onSessionReady: (value) => session = value,
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump();
    }
    expect(session.progress?.spineIndex, 0);
    final pageFinder = find.byKey(const ValueKey('scroll-page-1-0'));
    expect(pageFinder, findsOneWidget);
    final layer = find.descendant(
      of: pageFinder,
      matching: find.byType(AnnotationLayer),
    );
    final rendered = tester.widget<AnnotationLayer>(layer);
    final lines = AnnotationDecorations.linesFor(
      rendered.page,
      rendered.annotations,
    );
    expect(lines.map((line) => line.annotation.id), contains('thought-1'));
    final marker = ThoughtMarkerGeometry.markersFor(
      rendered.page,
      lines,
      contentWidth: tester.getSize(layer).width,
    ).single;
    await tester.tapAt(tester.getTopLeft(layer) + marker.center);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('annotation-editor-sheet')),
      findsOneWidget,
    );
    expect(find.text('第2章想法'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨章跳转后核验新章标记，返回仍可绘制原章标记', (tester) async {
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: _Source(),
            store: MemoryReaderProgressStore(),
            annotations: _Annotations(),
            bookId: 'jump-thoughts',
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            onSessionReady: (value) => session = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final spine in [2, 0]) {
      await session.jumpToChapter(spine);
      await tester.pumpAndSettle();
      final layers = tester.widgetList<AnnotationLayer>(
        find.byType(AnnotationLayer),
      );
      expect(
        layers.any(
          (layer) =>
              layer.page.spineIndex == spine &&
              layer.annotations.any(
                (annotation) => annotation.id == 'thought-$spine',
              ),
        ),
        isTrue,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
