import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

/// 可按字号和尺寸重排的单章源；整章只有一个带 CFI 的文本块。
class _ReflowSource
    implements
        RestylableChapterSource,
        ResizableChapterSource,
        LayoutDependencyChapterSource {
  _ReflowSource({this.lines = 180});

  final int lines;
  double fontSize = 16;
  double lineHeight = 1.5;
  double width = 320;
  double height = 480;
  int loads = 0;
  Completer<void>? gate;

  @override
  int get chapterCount => 1;

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
              startCfi: 'epubcfi(/6/2!/4/2/1:0)',
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

Widget _readerPage(
  _ReflowSource source, {
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
