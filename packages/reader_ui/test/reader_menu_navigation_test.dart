import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

class _Source implements ReaderChapterSource {
  _Source(this.chapterCount);

  @override
  final int chapterCount;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    for (var page = 0; page < 3; page++)
      PageContent(
        spineIndex: spineIndex,
        pageIndex: page,
        slices: const [],
        usedHeight: 0,
        pageHeight: 300,
        topPadding: 0,
      ),
  ];
}

Future<ReaderSession> _open(WidgetTester tester, int chapters) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderPage(
        source: _Source(chapters),
        store: MemoryReaderProgressStore(),
        bookId: 'menu',
        onSessionReady: (value) => session = value,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ReaderView));
  await tester.pumpAndSettle();
  return session;
}

Finder _button(String direction) =>
    find.byKey(ValueKey('menu-$direction-chapter'));

void main() {
  testWidgets('进度按钮跳到相邻章首页，滑块仍按全书进度跳转', (tester) async {
    final semantics = tester.ensureSemantics();
    final session = await _open(tester, 3);
    expect(find.bySemanticsLabel('上一章'), findsOneWidget);
    expect(find.bySemanticsLabel('下一章'), findsOneWidget);
    expect(tester.widget<InkResponse>(_button('prev')).onTap, isNull);

    await session.next();
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 1));
    await tester.tap(_button('next'));
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 1, pageIndex: 0));
    await tester.tap(_button('prev'));
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 0));

    final slider = find.byKey(const ValueKey('menu-progress-slider'));
    final bounds = tester.getRect(slider);
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 0.9, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 2, pageIndex: 0));
    expect(tester.widget<InkResponse>(_button('next')).onTap, isNull);
    await tester.tap(_button('next'));
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 2, pageIndex: 0));
    semantics.dispose();
  });

  testWidgets('单章书两侧章节按钮均禁用', (tester) async {
    final session = await _open(tester, 1);
    expect(tester.widget<InkResponse>(_button('prev')).onTap, isNull);
    expect(tester.widget<InkResponse>(_button('next')).onTap, isNull);
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 0));
  });
}
