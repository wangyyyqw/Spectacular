import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

const _platforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
});

Future<LibraryStore> _library(WidgetTester tester) async {
  final library = LibraryStore.memory();
  await tester.runAsync(() async {
    for (var index = 0; index < 12; index++) {
      await library.importBytes(
        buildTestEpub(title: '书目$index：关于自然、城市与日常生活的长篇观察'),
      );
    }
  });
  return library;
}

void main() {
  testWidgets('连续缩窗与超宽屏封面不超过160，侧栏与单本搜索不会放大封面', (tester) async {
    final library = await _library(tester);
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomeShell(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    final covers = find.byKey(const ValueKey('book-card-cover'));
    final state = tester.state(find.byType(BookshelfPage));
    for (final width in [
      320.0,
      390.0,
      600.0,
      768.0,
      999.0,
      1000.0,
      1280.0,
      1360.0,
      1920.0,
      2560.0,
    ]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      final size = tester.getSize(covers.first);
      expect(size.width, lessThanOrEqualTo(160.01), reason: '窗口宽度 $width');
      expect(size.width, greaterThanOrEqualTo(80));
      expect(size.aspectRatio, closeTo(.75, .001));
      expect(
        tester.getSize(find.byKey(const ValueKey('bookshelf-grid'))).width,
        lessThanOrEqualTo(1440),
      );
      expect(tester.getSize(search).width, lessThanOrEqualTo(440));
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        width >= 1000,
      );
      expect(tester.state(find.byType(BookshelfPage)), same(state));
      expect(tester.takeException(), isNull, reason: '窗口宽度 $width');
    }
    final before = tester.getSize(covers.first);
    await tester.enterText(search, '书目11：');
    await tester.pumpAndSettle();
    expect(covers, findsOneWidget);
    expect(tester.getSize(covers), before);
    await tester.tap(find.byTooltip('收起侧边栏'));
    await tester.pumpAndSettle();
    expect(tester.getSize(covers), before);
    expect(tester.widget<TextField>(search).controller!.text, '书目11：');
    tester.view.physicalSize = const Size(640, 760);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isFalse,
      reason: '保留用户手动收起',
    );
    await tester.tap(find.byTooltip('展开侧边栏'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isTrue,
    );
  }, variant: _platforms);

  testWidgets('窄窗放大文字仍可多选，宽窗列表有宽度上限并保留筛选', (tester) async {
    final library = await _library(tester);
    tester.view
      ..physicalSize = const Size(320, 850)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: HomeShell(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bookshelf-multi-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('book-card-cover')).first);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 本'), findsOneWidget);
    for (final key in [
      'bookshelf-batch-create-group',
      'bookshelf-batch-group',
      'bookshelf-batch-delete',
    ]) {
      final button = find.byKey(ValueKey(key));
      expect(button.hitTestable(), findsOneWidget);
      final rect = tester.getRect(button);
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(2560, 1000);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 本'), findsOneWidget);
    await tester.tap(find.byTooltip('退出多选'));
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    final rows = find.byWidgetPredicate(
      (widget) =>
          widget is InkWell && widget.key.toString().contains('book-row-'),
    );
    expect(tester.getSize(rows.first).width, lessThanOrEqualTo(920));
    expect(
      tester.getSize(find.byKey(const ValueKey('book-row-cover')).first),
      const Size(66, 88),
    );
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('书评嵌在窄内容栏时按栏宽收起搜索，键盘入口仍可用', (tester) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 520,
            child: ReviewsPage(library: LibraryStore.memory()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reviews-search-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('reviews-search-field')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reviews-search-button')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('reviews-search-field'));
    await tester.enterText(search, '保留筛选');
    await tester.pumpAndSettle();
    expect(tester.getRect(search).right, lessThanOrEqualTo(520));
    expect(tester.takeException(), isNull);
  }, variant: _platforms);
}
