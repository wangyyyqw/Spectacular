import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show TocEntry;
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
const _delayedSearchResult = SearchPanelResult(
  spineIndex: 0,
  charOffset: 200,
  chapterTitle: '第一章',
  context: 'word',
  matchLength: 4,
);

class _Source implements ReaderChapterSource {
  _Source({int baseOffset = 0, double fontSize = 16}) {
    final style = ComputedStyle({
      'font-size': '${fontSize}px',
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

class _SelectionReflowSource implements RestylableChapterSource {
  double fontSize = 16;
  bool fail = false;

  @override
  int get chapterCount => 1;

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    fontSize = overrides.fontSize ?? fontSize;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (fail) throw StateError('重排失败');
    return _Source(fontSize: fontSize).pages;
  }
}

class _ScrollTurnWindowSource implements ReaderChapterSource {
  final started = Completer<void>();
  final resume = Completer<void>();

  @override
  int get chapterCount => 3;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (spineIndex == 2) {
      if (!started.isCompleted) started.complete();
      await resume.future;
    }
    final style = ComputedStyle(const {
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final words = switch (spineIndex) {
      0 => 72,
      1 => 16,
      _ => 120,
    };
    final layout = TextLayoutEngine.layout(
      text: 'word ' * words,
      style: style,
      maxWidth: 320,
    );
    return Paginator(pageHeight: 200)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: 320,
              startCfi: 'epubcfi(/6/${(spineIndex + 1) * 2}!/4/2/1:0)',
            ),
          ],
          spineIndex: spineIndex,
        )
        .pages;
  }
}

class _NavigationObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}

class _ParagraphGapSource implements ReaderChapterSource {
  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final blocks = <PageBlock>[];
    for (final (index, text) in [
      'long first line\nend',
      'other paragraph',
    ].indexed) {
      final style = ComputedStyle({
        'font-size': '16px',
        'line-height': '2.5',
        'font-family': 'Ahem',
        'white-space': 'pre-wrap',
        if (index == 1) 'margin-top': '40px',
      });
      blocks.add(
        PageBlock.styled(
          layout: TextLayoutEngine.layout(
            text: text,
            style: style,
            maxWidth: 280,
          ),
          style: style,
          containingWidth: 280,
          startCfi: 'epubcfi(/6/2!/4/${2 + index * 2}/1:0)',
        ),
      );
    }
    return Paginator(pageHeight: 400)
        .measureChapter(blocks: blocks, spineIndex: 0)
        .pages;
  }
}

class _ImageEditSource implements ReaderChapterSource {
  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = ComputedStyle(const {
      'font-size': '16px',
      'width': '80px',
      'height': '80px',
      'margin-left': '20px',
    });
    final layout = TextLayoutEngine.layout(
      text: ' ',
      style: style,
      maxWidth: 80,
    );
    return Paginator(pageHeight: 120)
        .measureChapter(
          blocks: [
            PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: 160,
              startCfi: 'epubcfi(/6/2!/4/2)',
              isReplaced: true,
            ),
          ],
          spineIndex: 0,
        )
        .pages;
  }
}

class _ChapterBoundarySource implements ReaderChapterSource {
  @override
  int get chapterCount => 2;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = ComputedStyle(const {
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: spineIndex == 0 ? 'first chapter' : 'second chapter',
      style: style,
      maxWidth: 280,
    );
    return Paginator(pageHeight: 120)
        .measureChapter(
          blocks: [
            PageBlock(
              layout: layout,
              style: style,
              startCfi: 'epubcfi(/6/${(spineIndex + 1) * 2}!/4/2/1:0)',
            ),
          ],
          spineIndex: spineIndex,
        )
        .pages;
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

Future<ReaderSession> _showReader(
  WidgetTester tester, {
  ReaderChapterSource? source,
  bool editMode = false,
  ValueChanged<ReaderEditTarget>? onEditTarget,
}) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: source ?? _Source(),
          editMode: editMode,
          onEditTarget: onEditTarget,
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

Future<void> _extendSelection(WidgetTester tester, bool forward) async {
  final bounds = tester.getRect(find.byType(ReaderView));
  final gesture = await tester.startGesture(
    tester.getCenter(_handle(forward ? 'end' : 'start')),
  );
  await gesture.moveTo(
    Offset(bounds.center.dx, forward ? bounds.bottom - 4 : bounds.top + 4),
  );
  await tester.pump(const Duration(milliseconds: 350));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _dragHandle(WidgetTester tester, String end, Offset target) async {
  final origin = tester.getTopLeft(find.byType(ReaderView));
  final gesture = await tester.startGesture(tester.getCenter(_handle(end)));
  await gesture.moveTo(origin + _padding.topLeft + target);
  await gesture.up();
  await tester.pumpAndSettle();
}

String? Function() _captureClipboard(WidgetTester tester) {
  String? text;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      final arguments = call.arguments as Map<Object?, Object?>;
      text = arguments['text'] as String;
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return () => text;
}

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

Future<({ReaderSession session, Completer<String?> resolved})>
_showDelayedSearchReader(
  WidgetTester tester, {
  ReaderChapterSource? source,
  PageTurnMode mode = PageTurnMode.cover,
}) async {
  late ReaderSession session;
  final resolved = Completer<String?>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: source ?? _Source(),
          store: MemoryReaderProgressStore(),
          bookId: 'delayed-search',
          padding: _padding,
          overrides: const ReaderOverrides(),
          showPageFooter: false,
          pageTurnMode: mode,
          onSessionReady: (value) => session = value,
          onSearch: (_) async => const [_delayedSearchResult],
          onResolveSearchCfi: (_) => resolved.future,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (session: session, resolved: resolved);
}

Future<({ReaderSession session, Completer<String?> resolved})>
_startDelayedSearch(WidgetTester tester) async {
  final pending = await _showDelayedSearchReader(tester);
  await _openSearch(tester);
  await tester.tap(find.byType(ListTile));
  await tester.pumpAndSettle();
  return pending;
}

bool _hasSearchHighlight(WidgetTester tester) => tester
    .widgetList<AnnotationLayer>(find.byType(AnnotationLayer))
    .any((layer) => layer.annotations.any((item) => item.id == 'search-hit'));

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
  testWidgets('编辑模式命中同段两行间空白，不命中段间空白或页边距', (tester) async {
    final targets = <ReaderEditTarget>[];
    final session = await _showReader(
      tester,
      source: _ParagraphGapSource(),
      editMode: true,
      onEditTarget: targets.add,
    );
    final lines = TextHitTester.lineBoxes(session.page!);
    expect(lines, hasLength(3));
    final origin =
        tester.getTopLeft(find.byType(ReaderView)) + _padding.topLeft;
    final gap = Offset(
      lines.first.rect.center.dx,
      (lines[0].rect.center.dy + lines[1].rect.center.dy) / 2,
    );
    expect(lines[1].rect.inflate(3).contains(gap), isFalse);
    await tester.tapAt(origin + gap);
    await tester.pumpAndSettle();
    expect(targets, hasLength(1));
    expect(targets.single.cfi, 'epubcfi(/6/2!/4/2/1)');
    await tester.tapAt(
      origin + Offset(gap.dx, (lines[1].rect.bottom + lines[2].rect.top) / 2),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(origin + Offset(-20, gap.dy));
    await tester.pumpAndSettle();
    expect(targets, hasLength(1));
  });

  testWidgets('普通阅读点击段落行间空白不触发编辑', (tester) async {
    final targets = <ReaderEditTarget>[];
    final session = await _showReader(
      tester,
      source: _ParagraphGapSource(),
      onEditTarget: targets.add,
    );
    final lines = TextHitTester.lineBoxes(session.page!);
    final origin =
        tester.getTopLeft(find.byType(ReaderView)) + _padding.topLeft;
    await tester.tapAt(
      origin +
          Offset(
            lines.first.rect.center.dx,
            (lines[0].rect.center.dy + lines[1].rect.center.dy) / 2,
          ),
    );
    await tester.pumpAndSettle();
    expect(targets, isEmpty);
  });

  testWidgets('编辑模式点击独立图片内容区返回元素CFI，不附加文字偏移', (tester) async {
    final targets = <ReaderEditTarget>[];
    await _showReader(
      tester,
      source: _ImageEditSource(),
      editMode: true,
      onEditTarget: targets.add,
    );
    final origin = tester.getTopLeft(find.byType(ReaderView));
    await tester.tapAt(origin + _padding.topLeft + const Offset(50, 45));
    await tester.pumpAndSettle();
    expect(targets, hasLength(1));
    expect(targets.single.cfi, 'epubcfi(/6/2!/4/2)');
    await tester.tapAt(origin + _padding.topLeft + const Offset(150, 45));
    await tester.pumpAndSettle();
    expect(targets, hasLength(1));
  });
  testWidgets('编辑模式真实点击正文回传精确CFI，页边距不误选', (tester) async {
    final targets = <ReaderEditTarget>[];
    final session = await _showReader(
      tester,
      editMode: true,
      onEditTarget: targets.add,
    );
    final origin = tester.getTopLeft(find.byType(ReaderView));
    final line = TextHitTester.lineBoxes(session.page!).first;
    await tester.tapAt(
      origin +
          _padding.topLeft +
          Offset(line.rect.left + 6, line.rect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(targets, hasLength(1));
    expect(targets.single.spineIndex, 0);
    expect(targets.single.cfi, startsWith('epubcfi(/6/2!'));
    expect(session.progress!.pageIndex, 0);
    await tester.tapAt(origin + const Offset(4, 12));
    await tester.pumpAndSettle();
    expect(targets, hasLength(1));
  });

  testWidgets('普通阅读长按选区可请求编辑原文', (tester) async {
    final targets = <ReaderEditTarget>[];
    final session = await _showReader(tester, onEditTarget: targets.add);
    await _selectWord(tester, session.page!);
    await tester.tap(find.text('编辑原文'));
    await tester.pumpAndSettle();
    expect(targets, hasLength(1));
    expect(find.byType(SelectionLayer), findsNothing);
  });

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

  for (final forward in [true, false]) {
    testWidgets('跨页扩选后拖${forward ? '终点' : '起点'}保留另一页端点并支持交叉归一', (tester) async {
      final session = await _showReader(tester);
      if (!forward) {
        await session.next();
        await tester.pumpAndSettle();
      }
      await _selectWord(tester, session.page!);
      final original = _selectionLayer(tester).selection;
      await _extendSelection(tester, forward);
      expect(session.page!.pageIndex, forward ? 1 : 0);
      final line = TextHitTester.lineBoxes(session.page!).first;
      final firstTarget = Offset(line.rect.left + 110, line.rect.center.dy);
      await _dragHandle(tester, forward ? 'end' : 'start', firstTarget);
      final spanning = _selectionLayer(tester).selection;
      expect(spanning.startPageIndex, 0);
      expect(spanning.endPageIndex, 1);
      expect(
        forward ? spanning.start : spanning.end,
        same(forward ? original.start : original.end),
      );
      final fixed = forward ? spanning.end : spanning.start;
      final crossingTarget = Offset(
        line.rect.left + (forward ? 150 : 30),
        line.rect.center.dy,
      );
      await _dragHandle(tester, forward ? 'start' : 'end', crossingTarget);
      final crossed = _selectionLayer(tester).selection;
      expect(crossed.startPageIndex, session.page!.pageIndex);
      expect(crossed.endPageIndex, session.page!.pageIndex);
      expect(forward ? crossed.start : crossed.end, same(fixed));
      expect(crossed.start.charOffset, lessThan(crossed.end.charOffset));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('跨页拖柄跨过另一端后，同一手势继续移动仍保留固定端点', (tester) async {
    final session = await _showReader(tester);
    await _selectWord(tester, session.page!);
    await _extendSelection(tester, true);
    final line = TextHitTester.lineBoxes(session.page!).first;
    await _dragHandle(
      tester,
      'end',
      Offset(line.rect.left + 110, line.rect.center.dy),
    );
    final fixed = _selectionLayer(tester).selection.end;
    final origin = tester.getTopLeft(find.byType(ReaderView));
    final gesture = await tester.startGesture(
      tester.getCenter(_handle('start')),
    );
    await gesture.moveTo(
      origin +
          _padding.topLeft +
          Offset(line.rect.left + 150, line.rect.center.dy),
    );
    await tester.pump();
    final crossed = _selectionLayer(tester).selection;
    final target = Offset(line.rect.left + 160, line.rect.center.dy);
    await gesture.moveTo(origin + _padding.topLeft + target);
    await gesture.up();
    await tester.pumpAndSettle();
    final continued = _selectionLayer(tester).selection;

    expect(crossed.isMultiPage, isFalse);
    expect(crossed.start, same(fixed));
    expect(
      continued.start.charOffset,
      fixed.charOffset,
      reason: '固定端点不能随继续拖动移动',
    );
    expect(continued.start, same(fixed));
    expect(continued.startPageIndex, 1);
    expect(continued.endPageIndex, 1);
    expect(
      continued.end.charOffset,
      TextHitTester.hitTest(session.page!, target)!.charOffset,
    );
  });

  for (final fail in [false, true]) {
    testWidgets('同章重排${fail ? '失败保留' : '成功清除'}仍在旧页范围内的选区', (tester) async {
      final source = _SelectionReflowSource();
      final session = await _showReader(tester, source: source);
      await _selectWord(tester, session.page!);
      await _extendSelection(tester, true);
      final oldPage = session.page!;
      final selection = _selectionLayer(tester).selection;
      expect(selection.startPageIndex, 0);
      expect(selection.endPageIndex, 1);
      source.fail = fail;
      await session.applyOverrides(const ReaderOverrides(fontSize: 15));
      await tester.pumpAndSettle();

      expect(session.page!.pageIndex, 1, reason: '新页仍在旧选区范围内');
      expect(identical(session.page, oldPage), fail);
      if (fail) {
        expect(session.error, isNotNull);
        expect(_selectionLayer(tester).selection, same(selection));
        expect(find.byType(SelectionMenu), findsOneWidget);
      } else {
        expect(session.error, isNull);
        expect(find.byType(SelectionLayer), findsNothing);
        expect(find.byType(SelectionMenu), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final forward in [true, false]) {
    testWidgets('向${forward ? '后' : '前'}扩选在章边界停止并复制本章文字', (tester) async {
      final clipboardText = _captureClipboard(tester);
      final session = await _showReader(
        tester,
        source: _ChapterBoundarySource(),
      );
      final spine = forward ? 0 : 1;
      if (!forward) {
        await session.jumpToChapter(spine);
        await tester.pumpAndSettle();
      }
      await _selectWord(tester, session.page!);
      final bounds = tester.getRect(find.byType(ReaderView));
      final gesture = await tester.startGesture(
        tester.getCenter(_handle(forward ? 'end' : 'start')),
      );
      await gesture.moveTo(
        Offset(bounds.center.dx, forward ? bounds.bottom - 4 : bounds.top + 4),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(session.page!.spineIndex, spine);
      final selection = _selectionLayer(tester).selection;
      final cfi = SelectionOps.cfiOf(selection)!;
      expect(cfi.start, contains('/6/${(spine + 1) * 2}!'));
      expect(cfi.end, contains('/6/${(spine + 1) * 2}!'));
      final expected = SelectionOps.textOf(session.page!, selection);
      expect(expected, isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('selection-action-copy')));
      await tester.pumpAndSettle();
      expect(clipboardText(), expected);
      expect(tester.takeException(), isNull);
    });
  }

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

  for (final navigation in [
    '翻页',
    '翻回原页',
    '目录跳转',
    '同页滚动',
    '动画翻页',
    '失败翻页',
    '失败 CFI 跳转',
    '缺失目录项',
  ]) {
    testWidgets('搜索 CFI 延迟解析不能覆盖$navigation', (tester) async {
      final pending = await _startDelayedSearch(tester);
      final session = pending.session;
      switch (navigation) {
        case '翻页':
          await session.next();
        case '翻回原页':
          await session.next();
          await session.previous();
        case '目录跳转':
          await session.jumpToTocEntry(
            TocEntry(
              title: '目录位置',
              spineIndex: 0,
              cfi: EpubCfi.parse(cfiWithCharOffset(_cfi, 100)),
            ),
          );
        case '同页滚动':
          await session.commitScrollPosition(
            0,
            0,
            12,
            cfi: cfiWithCharOffset(_cfi, 5),
          );
        case '动画翻页':
          final turn = await session.preparePageTurn(true);
          expect(turn, isNotNull);
          expect(session.commitPageTurn(turn!), isTrue);
        case '失败翻页':
          expect(await session.previous(), isFalse);
        case '失败 CFI 跳转':
          expect(await session.jumpToCfi('invalid'), isFalse);
        case '缺失目录项':
          expect(
            await session.jumpToTocEntry(
              const TocEntry(title: '缺失', spineIndex: -1, missing: true),
            ),
            isFalse,
          );
      }
      final expected = session.progress;
      pending.resolved.complete(cfiWithCharOffset(_cfi, 200));
      await tester.pumpAndSettle();
      final actual = session.progress;
      final highlighted = _hasSearchHighlight(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(actual, expected);
      expect(highlighted, isFalse);
    });
  }

  testWidgets('搜索 CFI 延迟解析未被新导航取代时正常跳转，邻页预热不取消', (tester) async {
    final pending = await _startDelayedSearch(tester);
    final turn = await pending.session.preparePageTurn(true, prefetch: true);
    expect(turn, isNotNull);
    pending.session.releasePageTurn(turn!);
    pending.resolved.complete(cfiWithCharOffset(_cfi, 200));
    await tester.pumpAndSettle();
    final pageIndex = pending.session.page!.pageIndex;
    final highlighted = _hasSearchHighlight(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(pageIndex, 4);
    expect(highlighted, isTrue);
  });

  testWidgets('连续滚动翻屏请求等待补章时，旧搜索解析不得发起跳转', (tester) async {
    final source = _ScrollTurnWindowSource();
    addTearDown(() {
      if (!source.resume.isCompleted) source.resume.complete();
    });
    final pending = await _showDelayedSearchReader(
      tester,
      source: source,
      mode: PageTurnMode.scroll,
    );
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('continuous-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(source.started.isCompleted, isTrue);
    await _openSearch(tester);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    final expected = pending.session.progress;
    final expectedCfi = pending.session.readingCfi;
    final before = scroll.position.pixels;
    final bounds = tester.getRect(find.byType(ReaderView));
    await tester.tapAt(bounds.centerRight - const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.position.pixels, before, reason: '补章完成前翻屏仍在等待');
    pending.resolved.complete(cfiWithCharOffset(_cfi, 200));
    await tester.pumpAndSettle();
    final actual = pending.session.progress;
    final actualCfi = pending.session.readingCfi;
    final highlighted = _hasSearchHighlight(tester);
    source.resume.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(actual, expected);
    expect(actualCfi, expectedCfi);
    expect(highlighted, isFalse);
    expect(scroll.position.pixels, greaterThan(before));
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
