import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/bookmarks/bookmark_ribbon.dart';
import 'package:reader_ui/bookmarks/bookmark_style.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

class _Book implements RestylableChapterSource {
  double fontSize = 16;

  @override
  int get chapterCount => 1;

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    fontSize = overrides.fontSize ?? 16;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = ComputedStyle({
      'font-size': '${fontSize}px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: '书签回归测试正文 ' * 400,
      style: style,
      maxWidth: 320,
    );
    return Paginator(pageHeight: 480)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              containingWidth: 320,
              layout: layout,
              style: style,
              startCfi: 'epubcfi(/6/2!/4/2/1:0)',
            ),
          ],
          spineIndex: spineIndex,
        )
        .pages;
  }
}

class _Bookmarks implements ReaderBookmarkStore {
  final items = <ReaderBookmark>[];
  bool fail = false;
  bool failRemove = false;

  @override
  Future<List<ReaderBookmark>> list() async => List.of(items);

  @override
  Future<ReaderBookmark?> add({
    required String cfi,
    required int spineIndex,
    required String label,
  }) async {
    if (fail) throw StateError('测试保存失败');
    if (items.any((item) => item.cfi == cfi)) return null;
    final item = ReaderBookmark(
      id: '${items.length}',
      cfi: cfi,
      spineIndex: spineIndex,
      label: label,
      createdAt: DateTime(2026),
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> remove(String id) async {
    if (failRemove) throw StateError('测试删除失败');
    items.removeWhere((item) => item.id == id);
  }
}

Future<ReaderSession> _open(
  WidgetTester tester,
  _Bookmarks bookmarks, {
  PageTurnMode mode = PageTurnMode.cover,
  ReaderBookmarkStyle style = const ReaderBookmarkStyle(),
  ValueChanged<ReaderBookmarkStyle>? onStyle,
}) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 520,
            child: ReaderPage(
              source: _Book(),
              store: MemoryReaderProgressStore(),
              bookId: '书签回归',
              bookmarks: bookmarks,
              bookmarkStyle: style,
              onBookmarkStyleChanged: onStyle,
              pageTurnMode: mode,
              overrides: const ReaderOverrides(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              onSessionReady: (value) => session = value,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
}

Future<void> _move(WidgetTester tester, Future<Object?> action) async {
  unawaited(action);
  await tester.pumpAndSettle();
}

Future<void> _pullBookmark(WidgetTester tester, {bool remove = false}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ReaderView)),
  );
  await gesture.moveBy(const Offset(0, 25));
  await tester.pump();
  await gesture.moveBy(const Offset(0, 145));
  await tester.pump();
  expect(find.text(remove ? '松手移除书签' : '松手添加书签'), findsOneWidget);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('替换书签存储立即清除旧命中，并按章节和重定位状态更新标记', (tester) async {
    ReaderBookmark bookmark(String id, int spine, {String? status}) =>
        ReaderBookmark(
          id: id,
          cfi: 'epubcfi(/6/2!/4/2/1:0)',
          spineIndex: spine,
          label: '缓存回归',
          createdAt: DateTime(2026),
          relocationStatus: status,
        );
    final marked = _Bookmarks()..items.add(bookmark('当前章', 0));
    final unrelated = _Bookmarks()
      ..items.add(bookmark('其它章', 1))
      ..items.add(bookmark('待重定位', 0, status: 'pending'));
    final store = ValueNotifier<_Bookmarks>(marked);
    final source = _Book();
    final progress = MemoryReaderProgressStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<_Bookmarks>(
            valueListenable: store,
            builder: (_, bookmarks, _) => ReaderPage(
              source: source,
              store: progress,
              bookId: '书签缓存替换',
              bookmarks: bookmarks,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ribbon = find.byKey(const ValueKey('reader-bookmark-ribbon'));
    expect(ribbon, findsOneWidget);
    await _openMenu(tester);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .bookmarked,
      isTrue,
    );

    store.value = unrelated;
    await tester.pumpAndSettle();
    expect(ribbon, findsNothing);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .bookmarked,
      isFalse,
    );
    store.value = marked;
    await tester.pumpAndSettle();
    expect(ribbon, findsOneWidget);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .bookmarked,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  for (final mode in PageTurnMode.values.where(
    (value) => value != PageTurnMode.scroll,
  )) {
    testWidgets('${mode.label}下拉添加与移除，短拖和上滑不触发，横滑仍翻页', (tester) async {
      final bookmarks = _Bookmarks();
      final session = await _open(tester, bookmarks, mode: mode);
      final view = find.byType(ReaderView);
      final initial = session.currentCfi;
      await tester.drag(view, const Offset(0, 45));
      await tester.pumpAndSettle();
      await tester.drag(view, const Offset(0, 125));
      await tester.pumpAndSettle();
      await tester.drag(view, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(bookmarks.items, isEmpty);
      final start = tester.getCenter(view);
      await _pullBookmark(tester);
      expect(bookmarks.items.single.cfi, initial);
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsOneWidget,
      );
      await _pullBookmark(tester, remove: true);
      expect(bookmarks.items, isEmpty);
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsNothing,
      );
      expect(find.text('已移除书签'), findsOneWidget);
      await _pullBookmark(tester);
      // 用多次采样兼容仿真模式的原生起拖规则。
      final horizontal = await tester.startGesture(
        start + const Offset(100, 0),
      );
      for (var i = 0; i < 12; i++) {
        await horizontal.moveBy(const Offset(-24, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await horizontal.up();
      await tester.pumpAndSettle();
      expect(session.currentCfi, isNot(initial));
      expect(bookmarks.items, hasLength(1));
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final mode in [PageTurnMode.cover, PageTurnMode.scroll]) {
    testWidgets('${mode.label}工具栏添加、重复去重、列表同步与删除标记', (tester) async {
      final bookmarks = _Bookmarks();
      final session = await _open(tester, bookmarks, mode: mode);
      if (mode == PageTurnMode.scroll) {
        final before = session.currentCfi;
        await tester.drag(find.byType(ReaderView), const Offset(0, -230));
        await tester.pumpAndSettle();
        expect(session.currentCfi, isNot(before));
        await tester.drag(find.byType(ReaderView), const Offset(0, 130));
        await tester.pumpAndSettle();
        expect(bookmarks.items, isEmpty, reason: '滚动阅读下拉不能添加书签');
      }
      final expected = session.currentCfi;
      await _openMenu(tester);
      final button = find.byKey(const ValueKey('menu-add-bookmark'));
      expect(
        tester.getCenter(button).dx,
        greaterThan(
          tester.getCenter(find.byKey(const ValueKey('menu-daynight'))).dx,
        ),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(bookmarks.items.single.cfi, expected);
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        mode == PageTurnMode.scroll ? findsNothing : findsOneWidget,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(bookmarks.items, hasLength(1));
      expect(find.text('该位置已有书签'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-entry-toc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drawer-tab-bookmarks')));
      await tester.pumpAndSettle();
      expect(find.text('共 1 条'), findsOneWidget);
      await tester.tap(find.byTooltip('删除书签'));
      await tester.pumpAndSettle();
      expect(find.text('共 0 条'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reader-bookmark-ribbon')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('斜向、先上滑、回拉和取消手势均不改变书签', (tester) async {
    final bookmarks = _Bookmarks();
    await _open(tester, bookmarks);
    final center = tester.getCenter(find.byType(ReaderView));
    for (final deltas in [
      [const Offset(0, 25), const Offset(70, 150)],
      [const Offset(0, -40), const Offset(0, 220)],
      [const Offset(0, 25), const Offset(0, 150), const Offset(0, -80)],
    ]) {
      final gesture = await tester.startGesture(center);
      for (final delta in deltas) {
        await gesture.moveBy(delta);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(bookmarks.items, isEmpty);
    }
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, 25));
    await gesture.moveBy(const Offset(0, 150));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(bookmarks.items, isEmpty);
    await _pullBookmark(tester);
    expect(bookmarks.items, hasLength(1));
  });

  testWidgets('下拉移除按当前页文本范围匹配，并保留其它页和待重定位书签', (tester) async {
    final bookmarks = _Bookmarks();
    final session = await _open(tester, bookmarks);
    final currentCfi = session.currentCfi!;
    await _move(tester, session.next());
    final nextCfi = session.currentCfi!;
    await _move(tester, session.previous());
    bookmarks.items.addAll([
      for (final offset in [5, 20])
        ReaderBookmark(
          id: '当前页-$offset',
          cfi: currentCfi.replaceFirst(':0)', ':$offset)'),
          spineIndex: 0,
          label: '当前页正文中的书签',
          createdAt: DateTime(2026),
        ),
      ReaderBookmark(
        id: '其它页',
        cfi: nextCfi,
        spineIndex: 0,
        label: '其它页书签',
        createdAt: DateTime(2026),
      ),
      ReaderBookmark(
        id: '待重定位',
        cfi: currentCfi,
        spineIndex: 0,
        label: '待重定位书签',
        createdAt: DateTime(2026),
        relocationStatus: 'pending',
      ),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await _open(tester, bookmarks);
    await _pullBookmark(tester, remove: true);
    expect(bookmarks.items.map((item) => item.id), ['其它页', '待重定位']);
    expect(find.byKey(const ValueKey('reader-bookmark-ribbon')), findsNothing);
  });

  testWidgets('下拉移除失败保留标记，重试可成功', (tester) async {
    final bookmarks = _Bookmarks();
    await _open(tester, bookmarks);
    await _pullBookmark(tester);
    bookmarks.failRemove = true;
    await _pullBookmark(tester, remove: true);
    expect(bookmarks.items, hasLength(1));
    expect(find.text('书签删除失败，请重试'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reader-bookmark-ribbon')),
      findsOneWidget,
    );
    bookmarks.failRemove = false;
    await _pullBookmark(tester, remove: true);
    expect(bookmarks.items, isEmpty);
    expect(find.byKey(const ValueKey('reader-bookmark-ribbon')), findsNothing);
  });

  testWidgets('重排后按文本位置恢复标记，书签样式可从面板修改并保存', (tester) async {
    final bookmarks = _Bookmarks();
    ReaderBookmarkStyle? saved;
    final session = await _open(
      tester,
      bookmarks,
      style: const ReaderBookmarkStyle(width: 32, length: 90),
      onStyle: (style) => saved = style,
    );
    await _move(tester, session.next());
    await _openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('menu-add-bookmark')));
    await tester.pumpAndSettle();
    final cfi = bookmarks.items.single.cfi;
    await _move(
      tester,
      session.applyOverrides(const ReaderOverrides(fontSize: 22)),
    );
    await _move(tester, session.jumpToCfi(cfi));
    final ribbon = find.byKey(const ValueKey('reader-bookmark-ribbon'));
    expect(ribbon, findsOneWidget);
    expect(tester.getSize(ribbon), const Size(32, 90));
    final readerRect = tester.getRect(find.byType(ReaderView));
    expect(tester.getTopRight(ribbon).dx, readerRect.right - 12);
    expect(tester.getTopRight(ribbon).dy, readerRect.top);
    await tester.tap(find.byKey(const ValueKey('menu-entry-toc')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-tab-bookmarks')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('样式'));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('bookmark-宽度'));
    await tester.ensureVisible(slider);
    await tester.tapAt(tester.getCenter(slider));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bookmark-style-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.width, isNot(32));
    expect(tester.widget<ReaderBookmarkRibbon>(ribbon).style, saved);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .bookmarked,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('保存失败不显示已添加，重试可成功', (tester) async {
    final bookmarks = _Bookmarks()..fail = true;
    await _open(tester, bookmarks);
    await _openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('menu-add-bookmark')));
    await tester.pumpAndSettle();
    expect(find.text('书签保存失败，请重试'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-bookmark-ribbon')), findsNothing);
    bookmarks.fail = false;
    await tester.tap(find.byKey(const ValueKey('menu-add-bookmark')));
    await tester.pumpAndSettle();
    expect(bookmarks.items, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
