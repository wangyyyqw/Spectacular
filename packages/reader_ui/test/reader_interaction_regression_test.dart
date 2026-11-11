import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/annotation_layer.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/selection/selection.dart';
import 'package:reader_ui/selection/selection_layer.dart';
import 'package:reader_ui/selection/selection_menu.dart';
import 'package:reader_core/source/chapter_source.dart';

const _padding = EdgeInsets.fromLTRB(40, 70, 40, 40);
const _cfi = 'epubcfi(/6/2!/4/2/1:0)';

class _Source implements ReaderChapterSource {
  _Source({int baseOffset = 0}) {
    final style = ComputedStyle(const {
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: 'word ' * 120,
      style: style,
      maxWidth: 160,
    );
    final block = PageBlock.styled(
      layout: layout,
      style: style,
      containingWidth: 160,
      startCfi: cfiWithCharOffset(_cfi, baseOffset),
    );
    pages = Paginator(pageHeight: 120)
        .measureChapter(blocks: [block], spineIndex: 0)
        .pages;
  }

  late final List<PageContent> pages;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => pages;
}

class _NavigationObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}

class _BlankLineSource implements RestylableChapterSource {
  final _style = ComputedStyle(const {
    'font-size': '16px',
    'line-height': '1.5',
    'white-space': 'pre-wrap',
  });

  @override
  int get chapterCount => 1;

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {}

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final layout = TextLayoutEngine.layout(
      text: '第一行\n第二行\n\n第四行',
      style: _style,
      maxWidth: 300,
    );
    return Paginator(pageHeight: 24)
        .measureChapter(
          blocks: [PageBlock(layout: layout, style: _style, startCfi: _cfi)],
          spineIndex: spineIndex,
        )
        .pages;
  }
}

Future<ReaderSession> _showReader(WidgetTester tester) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: _Source(),
          store: MemoryReaderProgressStore(),
          bookId: 'interaction-regression',
          padding: _padding,
          overrides: const ReaderOverrides(),
          showPageFooter: false,
          onSessionReady: (value) => session = value,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _selectWord(WidgetTester tester, PageContent page) async {
  final origin = tester.getTopLeft(find.byType(ReaderView));
  final line = TextHitTester.lineBoxes(page).first;
  await tester.longPressAt(
    origin + _padding.topLeft + Offset(line.rect.left + 6, line.rect.center.dy),
  );
  await tester.pumpAndSettle();
}

SelectionLayer _selectionLayer(WidgetTester tester) =>
    tester.widget<SelectionLayer>(find.byType(SelectionLayer));

Finder _handle(String end) => find.byKey(ValueKey('selection-handle-$end'));

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-entry-toc')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('drawer-tab-search')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('search-input')), 'word');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

ReaderPage _searchReader({bool elementAnchor = false}) {
  final result = SearchPanelResult(
    spineIndex: 0,
    charOffset: 10,
    chapterTitle: '第一章',
    context: 'word',
    matchLength: 4,
    cfi: elementAnchor ? 'epubcfi(/6/2!/4/2/1)' : 'epubcfi(/6/2!/4/2/1:10)',
  );
  return ReaderPage(
    source: _Source(),
    store: MemoryReaderProgressStore(),
    bookId: 'search-regression',
    padding: _padding,
    overrides: const ReaderOverrides(),
    showPageFooter: false,
    onSearch: (_) async => [result],
  );
}

Future<void> _pushSearchReader(
  WidgetTester tester,
  _NavigationObserver observer, {
  bool elementAnchor = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _searchReader(elementAnchor: elementAnchor),
              ),
            ),
            child: const Text('打开阅读'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开阅读'));
  await tester.pumpAndSettle();
}

/// 以路由方式打开阅读页，便于验证系统返回键的逐层关闭。
Future<ReaderSession> _pushReader(
  WidgetTester tester,
  _NavigationObserver observer,
) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReaderPage(
                  source: _Source(),
                  store: MemoryReaderProgressStore(),
                  bookId: 'back-regression',
                  padding: _padding,
                  overrides: const ReaderOverrides(),
                  showPageFooter: false,
                  onSessionReady: (value) => session = value,
                ),
              ),
            ),
            child: const Text('打开阅读'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开阅读'));
  await tester.pumpAndSettle();
  return session;
}

bool _menuOpen(WidgetTester tester) =>
    tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open;

void main() {
  testWidgets('墨水屏模式仍可使用连续滚动', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: _Source(),
            store: MemoryReaderProgressStore(),
            bookId: 'ink-continuous-scroll',
            padding: _padding,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            inkMode: true,
            pageTurnMode: PageTurnMode.scroll,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('scroll-page-0-0')),
      findsOneWidget,
    );
  });

  testWidgets('第二页长按、选句和全选保留当前页码', (tester) async {
    final session = await _showReader(tester);
    await session.next();
    await tester.pumpAndSettle();
    final page = session.page!;
    expect(page.pageIndex, 1);
    await _selectWord(tester, page);
    expect(find.byType(SelectionLayer), findsOneWidget);
    final layer = _selectionLayer(tester);
    expect(layer.selection.startPageIndex, 1);
    expect(layer.selection.endPageIndex, 1);
    final hit = layer.selection.start;
    final sentence = SelectionOps.sentenceAt(page, hit);
    expect(sentence.startPageIndex, 1);
    expect(sentence.endPageIndex, 1);

    await tester.tap(find.byKey(const ValueKey('selection-action-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-action-select-all')));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsOneWidget);
    expect(_selectionLayer(tester).selection.startPageIndex, 1);
    expect(_selectionLayer(tester).selection.endPageIndex, 1);
    expect(_selectionLayer(tester).selection.start.charOffset, 0);
  });

  testWidgets('正文内缩同步到手柄、选区菜单和拖拽命中', (tester) async {
    final session = await _showReader(tester);
    await _selectWord(tester, session.page!);
    final origin = tester.getTopLeft(find.byType(ReaderView));
    final selection = _selectionLayer(tester).selection;
    final geometry = SelectionOps.geometryOf(session.page!, selection);
    expect(
      tester.getCenter(_handle('start')),
      origin + _padding.topLeft + geometry.startHandle,
    );
    final menu = tester.widget<SelectionMenu>(find.byType(SelectionMenu));
    expect(
      menu.anchor,
      SelectionOps.boundsOf(session.page!, selection).shift(_padding.topLeft),
    );

    final line = TextHitTester.lineBoxes(session.page!).first;
    final target = Offset(line.rect.left + 110, line.rect.center.dy);
    final gesture = await tester.startGesture(tester.getCenter(_handle('end')));
    await gesture.moveTo(origin + _padding.topLeft + target);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      _selectionLayer(tester).selection.end.charOffset,
      TextHitTester.hitTest(session.page!, target)!.charOffset,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('正文内缩不改变整页边缘跨页扩选热区', (tester) async {
    final session = await _showReader(tester);
    await _selectWord(tester, session.page!);
    final bounds = tester.getRect(find.byType(ReaderView));
    final gesture = await tester.startGesture(tester.getCenter(_handle('end')));
    await gesture.moveTo(Offset(bounds.center.dx, bounds.bottom - 4));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(session.page!.pageIndex, 1);
    final selection = _selectionLayer(tester).selection;
    expect(selection.startPageIndex, 0);
    expect(selection.endPageIndex, 1);
  });

  testWidgets('选中文字后点击正文只取消选中，不翻页', (tester) async {
    final session = await _showReader(tester);
    await _selectWord(tester, session.page!);
    expect(find.byType(SelectionLayer), findsOneWidget);
    final bounds = tester.getRect(find.byType(ReaderView));
    final right = bounds.centerRight - const Offset(20, 0);

    await tester.tapAt(right);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);
    expect(session.page!.pageIndex, 0, reason: '第一次点击只取消选中');
    expect(_menuOpen(tester), isFalse);
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 0));

    await tester.tapAt(right);
    await tester.pumpAndSettle();
    expect(session.page!.pageIndex, 1, reason: '再点一次恢复翻页');
  });

  testWidgets('选中文字后点击菜单区只取消选中，不打开阅读菜单', (tester) async {
    final session = await _showReader(tester);
    await _selectWord(tester, session.page!);
    expect(find.byType(SelectionLayer), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    // 选区存在时会注册双击识别器，单击要等双击窗口结束后才派发。
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);
    expect(_menuOpen(tester), isFalse);

    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(_menuOpen(tester), isTrue, reason: '再点一次恢复打开菜单');
  });

  testWidgets('菜单与抽屉打开时系统返回键只关闭浮层', (tester) async {
    final observer = _NavigationObserver();
    await _pushReader(tester, observer);
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(_menuOpen(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-toc')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(observer.pops, 0);
    expect(find.byType(ReaderPage), findsOneWidget, reason: '不能退出阅读页');
    expect(_menuOpen(tester), isFalse, reason: '返回键收起菜单与抽屉');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(observer.pops, 1, reason: '浮层都关闭后返回键才退出阅读页');
    expect(find.byType(ReaderPage), findsNothing);
  });

  testWidgets('点击区域编辑页打开时系统返回键只关闭编辑页', (tester) async {
    final observer = _NavigationObserver();
    await _pushReader(tester, observer);
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-settings')));
    await tester.pumpAndSettle();
    final tapZones = find.byKey(const ValueKey<String>('settings-tap-zones'));
    await tester.scrollUntilVisible(
      tapZones,
      200,
      scrollable: find
          .descendant(
            of: find.byType(SettingsPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(tapZones);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('tap-zone-apply')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(observer.pops, 0);
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('tap-zone-apply')), findsNothing);
  });

  testWidgets('菜单里的返回书架按钮在浮层打开时仍能退出阅读页', (tester) async {
    final observer = _NavigationObserver();
    await _pushReader(tester, observer);
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(_menuOpen(tester), isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('menu-back')));
    await tester.pumpAndSettle();
    expect(observer.pops, 1);
    expect(find.byType(ReaderPage), findsNothing);
  });

  testWidgets('点击内嵌搜索命中保留阅读路由并按正文内缩高亮', (tester) async {
    final observer = _NavigationObserver();
    await _pushSearchReader(tester, observer);
    await _openSearch(tester);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(observer.pops, 0);
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.byType(SearchPanel), findsNothing);
    expect(
      tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
      isFalse,
    );
    final annotationFinder = find.byType(AnnotationLayer);
    expect(annotationFinder, findsOneWidget);
    final origin = tester.getTopLeft(find.byType(ReaderView));
    expect(tester.getTopLeft(annotationFinder), origin + _padding.topLeft);
    final layer = tester.widget<AnnotationLayer>(annotationFinder);
    expect(layer.page.pageIndex, 0);
    expect(
      layer.annotations.any(
        (item) =>
            item.type == ReaderAnnotationType.mark && item.id == 'search-hit',
      ),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(AnnotationLayer), findsNothing);
  });

  testWidgets('元素页锚点搜索保留阅读路由且不伪造字符高亮', (tester) async {
    final observer = _NavigationObserver();
    await _pushSearchReader(tester, observer, elementAnchor: true);
    await _openSearch(tester);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(observer.pops, 0);
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.byType(SearchPanel), findsNothing);
    expect(
      tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
      isFalse,
    );
    expect(find.byType(AnnotationLayer), findsNothing);
  });

  for (final baseOffset in [0, 7]) {
    test('CFI 字符偏移与拆块基准偏移定位到同一段的正确页：$baseOffset', () async {
      final source = _Source(baseOffset: baseOffset);
      final session = ReaderSession(
        source: source,
        store: MemoryReaderProgressStore(),
        bookId: 'cfi-offset-$baseOffset',
      );
      addTearDown(session.dispose);
      await session.open();
      for (final expected in source.pages) {
        final slice = expected.slices.first;
        final local = slice.block.layout.lines[slice.startLine].start;
        final target = cfiWithCharOffset(_cfi, baseOffset + local);
        await session.jumpToCfi(target);
        expect(session.page!.pageIndex, expected.pageIndex);
      }
      await session.jumpToCfi(cfiWithCharOffset(_cfi, baseOffset + 10));
      expect(session.page!.pageIndex, 0);
    });
  }

  test('页首空行重排后保留原页，不回退到段落首页', () async {
    final session = ReaderSession(
      source: _BlankLineSource(),
      store: MemoryReaderProgressStore(),
      bookId: 'blank-line-anchor',
    );
    addTearDown(session.dispose);
    await session.open();
    await session.next();
    await session.next();
    expect(session.page!.pageIndex, 2);
    final slice = session.page!.slices.first;
    final line = slice.block.layout.lines[slice.startLine];
    expect(line.start, 8);
    expect(line.end, 8);
    await session.applyOverrides(const ReaderOverrides(fontSize: 18));
    expect(session.page!.pageIndex, 2);
  });
}
