import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
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
import 'package:reader_ui/a11y/semantics_layer.dart';
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
  _Source({int baseOffset = 0, double fontSize = 16, bool rtl = false}) {
    final style = ComputedStyle({
      'font-size': '${fontSize}px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'direction': rtl ? 'rtl' : 'ltr',
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

class _DelayedChapterSource extends _ChapterBoundarySource {
  final ready = Completer<void>();

  @override
  int get chapterCount => 3;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (spineIndex == 1) await ready.future;
    return super.loadChapter(spineIndex);
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
  PageTurnMode pageTurnMode = PageTurnMode.cover,
  ValueChanged<ReaderEditTarget>? onEditTarget,
  Future<List<SearchPanelResult>> Function(String)? onSearch,
}) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: source ?? _Source(),
          editMode: editMode,
          pageTurnMode: pageTurnMode,
          onEditTarget: onEditTarget,
          onSearch: onSearch,
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
  await tester.tap(find.byKey(const ValueKey('search-hit-0-200')));
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

Future<void> _scrollWheel(
  WidgetTester tester,
  double delta, {
  bool settle = true,
}) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(find.byType(ReaderView)),
      scrollDelta: Offset(0, delta),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('键盘翻页使用正式入口，支持方向键、分页键与空格组合', (tester) async {
    final session = await _showReader(tester);
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(session.page?.pageIndex, 4);
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.pageUp,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(session.page?.pageIndex, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(session.page?.pageIndex, 0);
  });

  testWidgets('键盘翻页准备期间不叠加请求，完成后可跨章回翻', (tester) async {
    final source = _DelayedChapterSource();
    addTearDown(() {
      if (!source.ready.isCompleted) source.ready.complete();
    });
    final session = await _showReader(tester, source: source);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
    source.ready.complete();
    await tester.pumpAndSettle();
    expect(session.page?.spineIndex, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(session.page?.spineIndex, 0);
  });

  testWidgets('RTL 正文左右方向键随阅读方向反转', (tester) async {
    final session = await _showReader(tester, source: _Source(rtl: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(session.page?.pageIndex, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(session.page?.pageIndex, 0);
  });

  testWidgets('连续滚动模式空格沿用滚动入口改变阅读位置', (tester) async {
    final session = await _showReader(
      tester,
      pageTurnMode: PageTurnMode.scroll,
    );
    final initial = session.readingCfi;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(session.readingCfi, isNot(initial));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(session.readingCfi, initial);
  });

  testWidgets(
    '已选正文可用复制快捷键，选区期间分页键不翻页',
    (tester) async {
      final copied = _captureClipboard(tester);
      final session = await _showReader(tester);
      await _selectWord(tester, session.page!);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(session.page?.pageIndex, 0);
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(copied(), 'word');
      expect(find.byType(SelectionLayer), findsNothing);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    '搜索快捷键聚焦输入，Esc 逐层退出后恢复正文键盘翻页',
    (tester) async {
      final session = await _showReader(tester, onSearch: (_) async => []);
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('search-input'));
      expect(input, findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);
      final editable = tester.widget<EditableText>(
        find.descendant(of: input, matching: find.byType(EditableText)),
      );
      editable.focusNode.unfocus();
      await tester.pump();
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.enterText(input, 'word');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(session.page?.pageIndex, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(_menuOpen(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(session.page?.pageIndex, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_menuOpen(tester), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(session.page?.pageIndex, 1);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('右键正文打开菜单而不翻页，再次右键关闭菜单', (tester) async {
    final session = await _showReader(tester);
    final point =
        tester.getRect(find.byType(ReaderView)).centerRight -
        const Offset(20, 0);
    for (final open in [true, false]) {
      await tester.tapAt(
        point,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(session.page?.pageIndex, 0);
      expect(_menuOpen(tester), open);
    }
  });

  testWidgets('编辑预览忽略阅读快捷键，不夺取源码焦点', (tester) async {
    final session = await _showReader(
      tester,
      editMode: true,
      onSearch: (_) async => [],
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(session.page?.pageIndex, 0);
    expect(_menuOpen(tester), isFalse);
    expect(
      find.byWidgetPredicate((widget) => widget is AlertDialog),
      findsNothing,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('reader-first-block'),
    );
  });

  testWidgets('快捷键帮助可关闭，弹窗期间按键不翻动底层正文', (tester) async {
    final session = await _showReader(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.text('桌面阅读操作'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(session.page?.pageIndex, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((widget) => widget is AlertDialog),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(session.page?.pageIndex, 1);
  });

  for (final mode in [
    PageTurnMode.cover,
    PageTurnMode.slideHorizontal,
    PageTurnMode.simulationBessel,
    PageTurnMode.simulation3d,
    PageTurnMode.none,
  ]) {
    testWidgets('滚轮通过正式阅读入口执行${mode.label}翻页', (tester) async {
      final session = await _showReader(tester, pageTurnMode: mode);
      expect(session.page?.pageIndex, 0);
      await _scrollWheel(tester, 120);
      expect(session.page?.pageIndex, 1);
      await tester.pump(const Duration(milliseconds: 300));
      await _scrollWheel(tester, -120);
      expect(session.page?.pageIndex, 0);
    });
  }

  testWidgets('滚轮跨章节翻页后可返回上一章', (tester) async {
    final session = await _showReader(tester, source: _ChapterBoundarySource());
    await _scrollWheel(tester, 120);
    expect(session.page?.spineIndex, 1);
    await tester.pump(const Duration(milliseconds: 300));
    await _scrollWheel(tester, -120);
    expect(session.page?.spineIndex, 0);
  });

  testWidgets('滚轮在翻页准备期间不排队，完成后仍可继续翻页', (tester) async {
    final source = _DelayedChapterSource();
    addTearDown(() {
      if (!source.ready.isCompleted) source.ready.complete();
    });
    final session = await _showReader(tester, source: source);
    await _scrollWheel(tester, 120, settle: false);
    await tester.pump(const Duration(milliseconds: 300));
    await _scrollWheel(tester, 120, settle: false);
    source.ready.complete();
    await tester.pumpAndSettle();
    expect(session.page?.spineIndex, 1);
    await tester.pump(const Duration(milliseconds: 300));
    await _scrollWheel(tester, 120);
    expect(session.page?.spineIndex, 2);
  });

  testWidgets('阅读菜单打开和编辑预览时滚轮不翻正文', (tester) async {
    final session = await _showReader(tester);
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(_menuOpen(tester), isTrue);
    await _scrollWheel(tester, 120);
    expect(session.page?.pageIndex, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    final preview = await _showReader(tester, editMode: true);
    await _scrollWheel(tester, 120);
    expect(preview.page?.pageIndex, 0);
  });

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

  testWidgets('连续滚动正文仅上下滑动，点击和横滑不移动，菜单仍可用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await _showReader(
      tester,
      pageTurnMode: PageTurnMode.scroll,
    );
    final reader = find.byType(ReaderView);
    final bounds = tester.getRect(reader);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: reader, matching: find.byType(Scrollable)),
        )
        .position;
    final start = position.pixels;
    final saved = session.progress;
    for (final point in [
      bounds.centerLeft + const Offset(8, 0),
      bounds.centerRight - const Offset(8, 0),
      bounds.topCenter + const Offset(0, 8),
      bounds.bottomCenter - const Offset(0, 8),
    ]) {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(position.pixels, start);
      expect(session.progress, saved);
    }
    await tester.drag(reader, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, start);
    expect(_menuOpen(tester), isFalse);
    await tester.tapAt(bounds.center);
    await tester.pumpAndSettle();
    expect(_menuOpen(tester), isTrue);
    await tester.tapAt(bounds.center);
    await tester.pumpAndSettle();
    expect(_menuOpen(tester), isFalse);
    expect(position.pixels, start);
    await tester.drag(reader, const Offset(0, -220));
    await tester.pumpAndSettle();
    final forward = position.pixels;
    expect(forward, greaterThan(start));
    expect(session.progress, isNot(saved));
    await tester.drag(reader, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(forward));
    expect(_menuOpen(tester), isFalse);
  });

  testWidgets('连续滚动松手后保持惯性，再次按下可立即接管', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _showReader(tester, pageTurnMode: PageTurnMode.scroll);
    final reader = find.byType(ReaderView);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: reader, matching: find.byType(Scrollable)),
        )
        .position;
    await tester.fling(reader, const Offset(0, -180), 900);
    await tester.pump();
    final released = position.pixels;
    await tester.pump(const Duration(milliseconds: 32));
    expect(position.pixels, greaterThan(released));
    final touch = await tester.startGesture(tester.getCenter(reader));
    await tester.pump();
    final stopped = position.pixels;
    await tester.pump(const Duration(milliseconds: 100));
    expect(position.pixels, closeTo(stopped, 0.01));
    await touch.moveBy(const Offset(0, 40));
    await tester.pump();
    await touch.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(position.pixels, lessThan(stopped));
    await touch.up();
    await tester.pumpAndSettle();
    expect(_menuOpen(tester), isFalse);
  });

  testWidgets('连续滚动保留长按和双击选字，点击正文仅取消选区', (tester) async {
    final session = await _showReader(
      tester,
      pageTurnMode: PageTurnMode.scroll,
    );
    await _selectWord(tester, session.page!);
    expect(find.byType(SelectionLayer), findsOneWidget);
    final before = session.progress;
    final bounds = tester.getRect(find.byType(ReaderView));
    await tester.tapAt(bounds.centerRight - const Offset(8, 0));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);
    expect(_menuOpen(tester), isFalse);
    expect(session.progress, before);
    await _selectWord(tester, session.page!);
    final selected = _selectionLayer(tester).selection.start.charOffset;
    final origin = tester.getTopLeft(find.byType(ReaderView));
    final line = TextHitTester.lineBoxes(session.page!).first;
    final target = origin + _padding.topLeft + Offset(86, line.rect.center.dy);
    await tester.tapAt(target);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(target);
    await tester.pumpAndSettle();
    expect(
      _selectionLayer(tester).selection.start.charOffset,
      greaterThan(selected),
    );
    expect(_menuOpen(tester), isFalse);
    expect(session.progress, before);
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

  for (final start in [false, true]) {
    testWidgets('单页${start ? '起点' : '终点'}跨行反复越过另一端仍保留固定端点并正确复制', (
      tester,
    ) async {
      final clipboardText = _captureClipboard(tester);
      final session = await _showReader(tester);
      final page = session.page!;
      await _selectWord(tester, page);
      final lines = TextHitTester.lineBoxes(page);
      Offset position(int line, double x) =>
          Offset(lines[line].rect.left + x, lines[line].rect.center.dy);
      await _dragHandle(tester, 'end', position(1, 112));
      await _dragHandle(tester, 'start', position(1, 64));
      final initial = _selectionLayer(tester).selection;
      final fixed = start ? initial.end : initial.start;
      final origin = tester.getTopLeft(find.byType(ReaderView));
      final gesture = await tester.startGesture(
        tester.getCenter(_handle(start ? 'start' : 'end')),
      );
      final targets = start
          ? [
              position(1, 144),
              position(2, 64),
              position(1, 112),
              position(1, 80),
              position(2, 96),
            ]
          : [
              position(1, 48),
              position(0, 80),
              position(1, 64),
              position(1, 96),
              position(0, 32),
            ];
      for (final target in targets) {
        await gesture.moveTo(origin + _padding.topLeft + target);
        await tester.pump();
        final actual = _selectionLayer(tester).selection;
        final expected = ReaderSelection.normalized(
          fixed,
          SelectionOps.charAt(page, target),
        );
        expect(
          (
            actual.start.sliceIndex,
            actual.start.lineIndex,
            actual.start.charOffset,
          ),
          (
            expected.start.sliceIndex,
            expected.start.lineIndex,
            expected.start.charOffset,
          ),
        );
        expect(
          (actual.end.sliceIndex, actual.end.lineIndex, actual.end.charOffset),
          (
            expected.end.sliceIndex,
            expected.end.lineIndex,
            expected.end.charOffset,
          ),
        );
        expect(
          identical(actual.start, fixed) || identical(actual.end, fixed),
          isTrue,
        );
        expect(actual.startPageIndex, page.pageIndex);
        expect(actual.endPageIndex, page.pageIndex);
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // 松手后按新的起止顺序拖动，不能复用上一轮的固定端点。
      final nextFixed = _selectionLayer(tester).selection.end;
      final nextTarget = position(0, 16);
      await _dragHandle(tester, 'start', nextTarget);
      final next = _selectionLayer(tester).selection;
      expect(next.end, same(nextFixed));
      expect(next.start.lineIndex, 0);
      expect(
        next.start.charOffset,
        SelectionOps.charAt(page, nextTarget).charOffset,
      );
      final expectedText = SelectionOps.textOf(page, next);
      expect(expectedText, isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('selection-action-copy')));
      await tester.pumpAndSettle();
      expect(clipboardText(), expectedText);
      expect(tester.takeException(), isNull);
    });
  }

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
    await tester.tap(find.byKey(const ValueKey('search-hit-0-10')));
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
    await tester.tap(find.byKey(const ValueKey('search-hit-0-10')));
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

  testWidgets('连续滚动辅助翻屏等待补章时，旧搜索解析不得发起跳转', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('search-hit-0-200')));
    await tester.pumpAndSettle();
    final expected = pending.session.progress;
    final expectedCfi = pending.session.readingCfi;
    final before = scroll.position.pixels;
    final pageNode = tester.widget<Semantics>(
      find.byKey(const ValueKey('page-semantics-0')),
    );
    pageNode.properties.customSemanticsActions![ReaderSemanticsLayer
        .nextPageAction]!();
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
