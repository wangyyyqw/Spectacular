import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

PageContent _page(int spine, int index) {
  const text = '页脚测试内容，多页填充。';
  final layout = TextLayoutEngine.layout(
    text: text,
    style: ComputedStyle(const <String, String>{
      'font-size': '14px',
      'line-height': '1.4',
    }),
    maxWidth: 300,
  );
  final block = PageBlock(layout: layout);
  return PageContent(
    spineIndex: spine,
    pageIndex: index,
    slices: [
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: layout.lineCount,
        height: layout.height,
      ),
    ],
    usedHeight: layout.height,
    pageHeight: 400,
    topPadding: 0,
  );
}

class _MultiPageSource implements ReaderChapterSource {
  _MultiPageSource({required this.chapters, required this.pagesPerChapter});

  final int chapters;

  final int pagesPerChapter;

  @override
  int get chapterCount => chapters;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    for (var i = 0; i < pagesPerChapter; i++) _page(spineIndex, i),
  ];
}

void main() {
  testWidgets('P8-10 页脚页码显示（6 槽第一槽）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _MultiPageSource(chapters: 2, pagesPerChapter: 3),
          store: MemoryReaderProgressStore(),
          bookId: 'footer-test',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('第1/2章'), findsOneWidget, reason: '页脚章码');
    expect(find.textContaining('1/3页'), findsOneWidget, reason: '页脚页码');
  });

  testWidgets('showPageFooter=false 关闭页脚', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _MultiPageSource(chapters: 2, pagesPerChapter: 3),
          store: MemoryReaderProgressStore(),
          bookId: 'footer-off',
          showPageFooter: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('第1/2章'), findsNothing);
  });
}
