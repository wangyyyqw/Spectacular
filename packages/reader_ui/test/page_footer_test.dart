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
    // 设计稿样式（P8-10）：页眉左标题右页码，页脚左时间电池右进度百分比。
    expect(find.text('第 1 章'), findsOneWidget, reason: '页眉章标题');
    expect(find.text('1/3'), findsOneWidget, reason: '页眉页码');
    expect(
      find.textContaining(RegExp(r'^\d{2}:\d{2}$')),
      findsOneWidget,
      reason: '页脚时钟',
    );
    expect(
      find.textContaining(RegExp(r'%$')),
      findsOneWidget,
      reason: '页脚进度百分比',
    );
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
    expect(find.text('第 1 章'), findsNothing);
    expect(find.textContaining(RegExp(r'%$')), findsNothing);
  });
}
