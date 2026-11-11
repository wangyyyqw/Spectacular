import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('书架支持按书名、作者搜索，不再显示阅读状态标签', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry reading;
    await tester.runAsync(() async {
      reading = await library.importBytes(
        buildTestEpub(title: '海边的卡夫卡', author: '村上春树', identifier: 'filter-a'),
      );
      await library.importBytes(
        buildTestEpub(title: '山茶文具店', author: '小川糸', identifier: 'filter-b'),
      );
      await library.importBytes(
        buildTestEpub(title: '长安的荔枝', author: '马伯庸', identifier: 'filter-c'),
      );
      await library.touchLastRead(reading.id);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('全部 3'), findsNothing);
    expect(find.text('未读 2'), findsNothing);
    expect(find.text('在读 1'), findsNothing);
    expect(find.text('已读完 0'), findsNothing);

    await tester.tap(find.byTooltip('搜索书架'));
    await _settle(tester, frames: 3);
    await tester.enterText(
      find.byKey(const ValueKey<String>('bookshelf-search-field')),
      '山茶',
    );
    await _settle(tester, frames: 3);
    expect(find.text('山茶文具店'), findsWidgets);
    expect(find.text('海边的卡夫卡'), findsNothing);
    expect(find.text('长安的荔枝'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('bookshelf-search-field')),
      '村上',
    );
    await _settle(tester, frames: 3);
    expect(find.text('海边的卡夫卡'), findsWidgets);
    expect(find.text('山茶文具店'), findsNothing);

    await tester.tap(find.byTooltip('关闭搜索'));
    await _settle(tester, frames: 3);
    await tester.tap(find.byTooltip('搜索书架'));
    await _settle(tester, frames: 3);
    await tester.enterText(
      find.byKey(const ValueKey<String>('bookshelf-search-field')),
      '不存在',
    );
    await _settle(tester, frames: 3);
    expect(find.text('没有找到相关书籍'), findsOneWidget);
    expect(find.text('没有书名或作者包含“不存在”'), findsOneWidget);

    await tester.tap(find.text('清除筛选'));
    await _settle(tester, frames: 3);
    expect(find.text('海边的卡夫卡'), findsWidgets);
    expect(find.text('山茶文具店'), findsWidgets);
    expect(find.text('长安的荔枝'), findsWidgets);
  });
}
