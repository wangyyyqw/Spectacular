import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show TocEntry;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_core/source/chapter_source.dart';

/// 可按字号和尺寸重排的单章源；整章只有一个带 CFI 的文本块。
class _ReflowSource
    implements
        RestylableChapterSource,
        ResizableChapterSource,
        LayoutDependencyChapterSource {
  _ReflowSource({this.lines = 180, this.chapters = 1});

  final int lines;
  final int chapters;
  double fontSize = 16;
  double lineHeight = 1.5;
  double width = 320;
  double height = 480;
  int loads = 0;
  Completer<void>? gate;

  @override
  int get chapterCount => chapters;

  @override
  String get layoutDependency =>
      'font=$fontSize;line=$lineHeight;w=$width;h=$height';

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    fontSize = overrides.fontSize ?? fontSize;
    lineHeight = overrides.lineHeight ?? lineHeight;
  }

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
    ContentSideInsets? sideInsets,
  }) async {
    final changed = this.width != width || this.height != height;
    this.width = width;
    this.height = height;
    return changed;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads += 1;
    final pending = gate;
    if (pending != null) await pending.future;
    final style = ComputedStyle(<String, String>{
      'font-size': '${fontSize}px',
      'line-height': '$lineHeight',
      'font-family': 'Ahem',
      'white-space': 'pre-wrap',
    });
    final layout = TextLayoutEngine.layout(
      text: [for (var i = 0; i < lines; i++) 'line$i'].join('\n'),
      style: style,
      maxWidth: width,
    );
    return Paginator(pageHeight: height)
        .measureChapter(
          blocks: <PageBlock>[
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

class _TrackingStore extends MemoryReaderProgressStore {
  int writes = 0;

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    writes += 1;
    await super.save(bookId, progress);
  }
}

class _FixedPages implements ReaderChapterSource {
  _FixedPages({List<int> pageCounts = const [3]})
    : chapters = [
        for (var spine = 0; spine < pageCounts.length; spine++)
          _chapter(spine, pageCounts[spine]),
      ];

  final List<List<PageContent>> chapters;

  @override
  int get chapterCount => chapters.length;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async =>
      chapters[spineIndex];

  static List<PageContent> _chapter(int spine, int count) {
    final style = ComputedStyle(const {'font-size': '16px'});
    final layout = TextLayoutEngine.layout(
      text: '测试正文' * 10,
      style: style,
      maxWidth: 280,
    );
    return [
      for (var page = 0; page < count; page++)
        PageContent(
          spineIndex: spine,
          pageIndex: page,
          slices: [
            PageBlockSlice(
              block: PageBlock(
                layout: layout,
                style: style,
                startCfi:
                    'epubcfi(/6/${(spine + 1) * 2}!/4/2/1:${(page + 1) * 100})',
              ),
              startLine: 0,
              endLine: layout.lineCount,
              height: layout.height,
            ),
          ],
          usedHeight: layout.height,
          pageHeight: 400,
          topPadding: 0,
        ),
    ];
  }
}

class _PositionedPages extends _FixedPages implements PositionedChapterSource {
  bool positionsReady = true;

  @override
  double? readingPercentForCfi(String? cfi) =>
      !positionsReady || cfi == null ? null : (cfiCharOffset(cfi) ?? 0) / 1000;

  @override
  String? cfiForReadingPercent(double percent) => null;

  @override
  String? cfiForTocEntry(TocEntry entry) => null;
}

ReaderPageFooter _footerOf(Widget widget) {
  if (widget is ReaderPageFooter) return widget;
  final children = switch (widget) {
    MultiChildRenderObjectWidget() => widget.children,
    SingleChildRenderObjectWidget() => [
      if (widget.child != null) widget.child!,
    ],
    ProxyWidget() => [widget.child],
    _ => <Widget>[],
  };
  for (final child in children) {
    try {
      return _footerOf(child);
    } on StateError {
      continue;
    }
  }
  throw StateError('纸面没有页脚');
}

Widget _readerPage(
  ReaderChapterSource source, {
  required ReaderProgressStore store,
  required String bookId,
  required PageTurnMode mode,
  required ValueChanged<ReaderSession> onSessionReady,
  ReaderOverrides? overrides,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          height: 520,
          child: ReaderPage(
            source: source,
            store: store,
            bookId: bookId,
            contentRevision: 'r1',
            pageTurnMode: mode,
            overrides: overrides,
            onSessionReady: onSessionReady,
          ),
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _jumpScroll(WidgetTester tester, double offset) async {
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
  scrollable.position.jumpTo(offset);
  await tester.pump(const Duration(milliseconds: 160));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('预热、落页和回翻都显示各自页面的原文百分比', (tester) async {
    final source = _PositionedPages();
    late ReaderSession session;
    await tester.pumpWidget(
      _readerPage(
        source,
        store: MemoryReaderProgressStore(),
        bookId: 'page-percent',
        mode: PageTurnMode.coverStack,
        onSessionReady: (value) => session = value,
      ),
    );
    await _settle(tester);
    final view = tester.widget<PageTurnView>(find.byType(PageTurnView));
    final state = tester.state<PageTurnViewState>(find.byType(PageTurnView));
    for (final index in [1, 2, 1, 0]) {
      final expected = (index + 1) / 10;
      final target = source.chapters[0][index];
      final paper = view.paperBuilder(target, const Size(360, 520));
      expect(_footerOf(paper).progress, expected, reason: '预热不能借用当前页的百分比');
      state.controller.request(index > session.page!.pageIndex);
      for (
        var frame = 0;
        frame < 120 && state.controller.targetImage == null;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(state.controller.targetImage, isNotNull);
      await tester.pumpAndSettle();
      expect(session.page, same(target));
      expect(
        tester.widget<ReaderPageFooter>(find.byType(ReaderPageFooter)).progress,
        expected,
      );
    }
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('同页精确跳转保留逻辑进度，纸面百分比不受当前锚点影响', (tester) async {
    final source = _PositionedPages();
    final store = MemoryReaderProgressStore();
    late ReaderSession session;
    await tester.pumpWidget(
      _readerPage(
        source,
        store: store,
        bookId: 'same-page-percent',
        mode: PageTurnMode.coverStack,
        onSessionReady: (value) => session = value,
      ),
    );
    await _settle(tester);
    await session.jumpToCfi('epubcfi(/6/2!/4/2/1:210)');
    await _settle(tester);
    expect(session.page?.pageIndex, 1);
    expect(session.readingPercent, .21);
    expect(
      tester.widget<ReaderPageFooter>(find.byType(ReaderPageFooter)).progress,
      .2,
    );
    await session.flushProgress();
    expect((await store.load('same-page-percent'))?.readingPercent, .21);
    source.positionsReady = false;
    final view = tester.widget<PageTurnView>(find.byType(PageTurnView));
    expect(
      _footerOf(view.paperBuilder(source.chapters[0][1], const Size(360, 520)))
          .progress,
      .2,
      reason: '原文缓存淘汰后已准备纸面仍保持相同比例',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('普通来源跨章预热按目标章页数估算百分比', (tester) async {
    final source = _FixedPages(pageCounts: const [1, 4]);
    late ReaderSession session;
    await tester.pumpWidget(
      _readerPage(
        source,
        store: MemoryReaderProgressStore(),
        bookId: 'fallback-percent',
        mode: PageTurnMode.coverStack,
        onSessionReady: (value) => session = value,
      ),
    );
    await _settle(tester);
    final prepared = (await session.preparePageTurn(true, prefetch: true))!;
    final view = tester.widget<PageTurnView>(find.byType(PageTurnView));
    final target = prepared.target.content;
    expect(
      _footerOf(view.paperBuilder(target, const Size(360, 520))).progress,
      .625,
    );
    expect(session.commitPageTurn(prepared), isTrue);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReaderPageFooter>(find.byType(ReaderPageFooter)).progress,
      .625,
    );
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('重排期间旧滚动窗口不能反写最终 CFI', (tester) async {
    final source = _ReflowSource();
    final store = MemoryReaderProgressStore();
    late ReaderSession session;
    await tester.pumpWidget(
      _readerPage(
        source,
        store: store,
        bookId: 'stale-window',
        mode: PageTurnMode.scroll,
        onSessionReady: (value) => session = value,
      ),
    );
    await _settle(tester);
    await _jumpScroll(tester, 1400);
    final originalCfi = session.currentCfi;
    final originalLine = session.currentLineText;
    expect(originalCfi, isNotNull);
    expect(originalLine, isNotEmpty);

    final gate = Completer<void>();
    source.gate = gate;
    final pending = session.applyOverrides(const ReaderOverrides(fontSize: 24));
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.loading, isTrue);
    gate.complete();
    source.gate = null;
    await pending;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(session.currentCfi, originalCfi, reason: '重排后不能回到旧窗口页首');
    expect(session.currentLineText, originalLine);
    await session.flushProgress();
    expect((await store.load('stale-window'))?.cfi, originalCfi);
  });

  testWidgets('书尾末页切滚动不撤销读完也不回写较早页', (tester) async {
    final store = MemoryReaderProgressStore();
    final source = _ReflowSource(lines: 90);
    late ReaderSession first;
    await tester.pumpWidget(
      _readerPage(
        source,
        store: store,
        bookId: 'tail-switch',
        mode: PageTurnMode.cover,
        onSessionReady: (value) => first = value,
      ),
    );
    await _settle(tester);
    while (await first.next()) {}
    await first.flushProgress();
    final saved = first.progress!;
    expect(saved.finished, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    late ReaderSession reopened;
    await tester.pumpWidget(
      _readerPage(
        _ReflowSource(lines: 90),
        store: store,
        bookId: 'tail-switch',
        mode: PageTurnMode.scroll,
        onSessionReady: (value) => reopened = value,
      ),
    );
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(reopened.progress?.finished, isTrue);
    expect(reopened.progress?.pageIndex, saved.pageIndex);
    await reopened.flushProgress();
    final persisted = await store.load('tail-switch');
    expect(persisted?.pageIndex, saved.pageIndex);
    expect(persisted?.finished, isTrue);
  });

  testWidgets('跨章窗口字号循环及延迟弹道校正不重新定义阅读锚点', (tester) async {
    final source = _ReflowSource(chapters: 3);
    final store = MemoryReaderProgressStore();
    late ReaderSession session;
    await tester.pumpWidget(
      _readerPage(
        source,
        store: store,
        bookId: 'multi-reflow-correction',
        mode: PageTurnMode.scroll,
        onSessionReady: (value) => session = value,
      ),
    );
    await _settle(tester);
    await session.jumpToCfi('epubcfi(/6/4!/4/2/1:250)', continuous: true);
    await _settle(tester);
    final original = session.progress!.cfi;
    expect(session.progress!.spineIndex, 1);
    for (final size in [20.0, 16.0, 20.0, 16.0]) {
      await session.applyOverrides(ReaderOverrides(fontSize: size));
      await _settle(tester);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      // 系统校正由无拖动的滚动活动驱动；它不能授予当前位置写入权限。
      final correction = position.animateTo(
        position.pixels + 3,
        duration: const Duration(milliseconds: 80),
        curve: Curves.linear,
      );
      await tester.pumpAndSettle();
      await correction;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 3));
      expect(session.progress!.cfi, original);
      await session.flushProgress();
      expect((await store.load('multi-reflow-correction'))!.cfi, original);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('内容不足一屏时冷开保留精确滚动偏移', (tester) async {
    final store = MemoryReaderProgressStore();
    late ReaderSession saver;
    await tester.pumpWidget(
      _readerPage(
        _ReflowSource(lines: 6),
        store: store,
        bookId: 'short-scroll',
        mode: PageTurnMode.scroll,
        onSessionReady: (value) => saver = value,
      ),
    );
    await _settle(tester);
    await saver.commitScrollPosition(0, 0, 96);
    await saver.flushProgress();
    final saved = await store.load('short-scroll');
    expect(saved?.scrollOffset, closeTo(96, 1e-9));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    late ReaderSession reopened;
    await tester.pumpWidget(
      _readerPage(
        _ReflowSource(lines: 6),
        store: store,
        bookId: 'short-scroll',
        mode: PageTurnMode.scroll,
        onSessionReady: (value) => reopened = value,
      ),
    );
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(reopened.progress?.scrollOffset, closeTo(96, 1));
    await reopened.flushProgress();
    expect((await store.load('short-scroll'))?.scrollOffset, closeTo(96, 1));
  });

  for (final delay in <int>[1, 119, 121]) {
    testWidgets('滚动后 ${delay}ms 切模式保留最新位置', (tester) async {
      final source = _ReflowSource();
      final store = _TrackingStore();
      late ReaderSession session;
      await tester.pumpWidget(
        _readerPage(
          source,
          store: store,
          bookId: 'switch-$delay',
          mode: PageTurnMode.scroll,
          onSessionReady: (value) => session = value,
        ),
      );
      await _settle(tester);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(1400);
      await tester.pump(Duration(milliseconds: delay));

      await tester.pumpWidget(
        _readerPage(
          source,
          store: store,
          bookId: 'switch-$delay',
          mode: PageTurnMode.cover,
          onSessionReady: (value) => session = value,
        ),
      );
      await _settle(tester);
      final saved = await store.load('switch-$delay');
      expect(saved, isNotNull);
      expect(saved!.pageIndex, greaterThan(0));
      expect(saved.cfi, isNotNull);
      expect(session.currentCfi, saved.cfi);
      expect(session.progress?.pageIndex, saved.pageIndex);
    });
  }

  testWidgets('滚动后立即销毁阅读页仍保存最新位置', (tester) async {
    final source = _ReflowSource();
    final store = _TrackingStore();
    late ReaderSession session;
    await tester.pumpWidget(
      _readerPage(
        source,
        store: store,
        bookId: 'dispose-scroll',
        mode: PageTurnMode.scroll,
        onSessionReady: (value) => session = value,
      ),
    );
    await _settle(tester);
    final initialCfi = session.currentCfi;
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(1400);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    final saved = await store.load('dispose-scroll');
    expect(saved, isNotNull);
    expect(saved!.pageIndex, greaterThan(0));
    expect(saved.cfi, isNotNull);
    expect(saved.cfi, isNot(initialCfi));
  });

  testWidgets('滚动后切后台立即刷新最新位置', (tester) async {
    final source = _ReflowSource();
    final store = _TrackingStore();
    late ReaderSession session;
    await tester.pumpWidget(
      _readerPage(
        source,
        store: store,
        bookId: 'background-scroll',
        mode: PageTurnMode.scroll,
        onSessionReady: (value) => session = value,
      ),
    );
    await _settle(tester);
    final initialCfi = session.currentCfi;
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(1400);
    await tester.pump(const Duration(milliseconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final saved = await store.load('background-scroll');
    expect(saved, isNotNull);
    expect(saved!.pageIndex, greaterThan(0));
    expect(saved.cfi, isNot(initialCfi));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('五种分页模式往返不改写当前阅读进度', (tester) async {
    final source = _ReflowSource();
    final store = _TrackingStore();
    late ReaderSession session;
    Widget build(PageTurnMode mode) => _readerPage(
      source,
      store: store,
      bookId: 'mode-round-trip',
      mode: mode,
      onSessionReady: (value) => session = value,
    );

    await tester.pumpWidget(build(PageTurnMode.cover));
    await _settle(tester);
    await session.next();
    await tester.pumpAndSettle();
    final baseline = session.progress!;
    final writes = store.writes;
    for (final mode in <PageTurnMode>[
      PageTurnMode.coverStack,
      PageTurnMode.cover,
      PageTurnMode.simulationBessel,
      PageTurnMode.slideHorizontal,
      PageTurnMode.none,
    ]) {
      await tester.pumpWidget(build(mode));
      await tester.pumpAndSettle();
      expect(session.progress, baseline, reason: '${mode.label} 切换后位置不变');
    }
    expect(store.writes, writes, reason: '纯模式切换不产生额外写入');
  });

  testWidgets('菜单切到覆盖模式前先提交滚动容器最新位置', (tester) async {
    final source = _ReflowSource();
    final store = _TrackingStore();
    late ReaderSession session;
    await tester.pumpWidget(
      _readerPage(
        source,
        store: store,
        bookId: 'menu-mode-switch',
        mode: PageTurnMode.scroll,
        onSessionReady: (value) => session = value,
      ),
    );
    await _settle(tester);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(1400);
    await tester.pump(const Duration(milliseconds: 1));

    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-settings')));
    await tester.pumpAndSettle();
    final target = find.byKey(
      const ValueKey<String>('settings-page-turn-cover'),
    );
    await tester.tap(target);
    await _settle(tester);

    final saved = await store.load('menu-mode-switch');
    expect(saved, isNotNull);
    expect(saved!.pageIndex, greaterThan(0));
    expect(session.progress?.pageIndex, saved.pageIndex);
    expect(session.currentCfi, saved.cfi);
  });
}
