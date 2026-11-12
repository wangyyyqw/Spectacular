import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_ui/paging/duokan_curl_shader.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageContent _page(int spine) {
  final layout = TextLayoutEngine.layout(
    text: '第${spine + 1}章',
    style: _style(),
    maxWidth: 280,
  );
  return PageContent(
    spineIndex: spine,
    pageIndex: 0,
    slices: [
      PageBlockSlice(
        block: PageBlock(layout: layout, style: _style()),
        startLine: 0,
        endLine: layout.lineCount,
        height: layout.height,
      ),
    ],
    usedHeight: layout.height,
    pageHeight: 200,
    topPadding: 0,
  );
}

class _Source implements ReaderChapterSource {
  final List<int> loads = <int>[];

  @override
  int get chapterCount => 3;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    return [_page(spineIndex)];
  }
}

class _FiveChapterSource extends _Source {
  @override
  int get chapterCount => 5;
}

class _GatedSource extends _Source {
  final previous = Completer<List<PageContent>>();

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) =>
      spineIndex == 0 ? previous.future : super.loadChapter(spineIndex);
}

class _RestylingSource extends _Source implements RestylableChapterSource {
  final restyled = Completer<void>();

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) => restyled.future;
}

Future<ReaderSession> _openInputSession() async {
  final store = MemoryReaderProgressStore();
  await store.save(
    'warm-input',
    const ReaderProgress(spineIndex: 1, pageIndex: 0),
  );
  final session = ReaderSession(
    source: _Source(),
    store: store,
    bookId: 'warm-input',
  );
  await session.open();
  return session;
}

Widget _inputView(
  ReaderSession session,
  GlobalKey<PageTurnViewState> key, {
  ReaderPageImagesPreparer? prepare,
  int revision = 1,
  PageTurnMode mode = PageTurnMode.cover,
  ReaderPaperBackgroundPainter? paintBackground,
}) => MaterialApp(
  home: PageTurnView(
    key: key,
    session: session,
    mode: mode,
    revision: revision,
    preparePageImages: prepare,
    paintBackground: paintBackground,
    paperBuilder: (page, size) => ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Text('${page.spineIndex}'),
    ),
    paperColor: const Color(0xFFFFFFFF),
  ),
);

class _LongChapterSource extends _Source {
  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    return [for (var i = 0; i < 8; i++) _page(spineIndex)];
  }
}

class _LocatedChapterSource extends _Source {
  @override
  int get chapterCount => 6;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: '章内定位内容',
      style: style,
      maxWidth: 280,
    );
    return [
      for (var index = 0; index < 8; index++)
        PageContent(
          spineIndex: spineIndex,
          pageIndex: index,
          slices: [
            PageBlockSlice(
              block: PageBlock(
                layout: layout,
                style: style,
                startCfi:
                    'epubcfi(/6/${(spineIndex + 1) * 2}!/4/${(index + 1) * 2}/1:0)',
              ),
              startLine: 0,
              endLine: layout.lineCount,
              height: layout.height,
            ),
          ],
          usedHeight: layout.height,
          pageHeight: 200,
          topPadding: 0,
        ),
    ];
  }
}

void main() {
  testWidgets('跳转等待期间旧页延迟预热不重新加载邻章', (tester) async {
    final source = _GatedSource();
    final store = MemoryReaderProgressStore();
    await store.save('跳转预热', const ReaderProgress(spineIndex: 1, pageIndex: 0));
    final session = ReaderSession(source: source, store: store, bookId: '跳转预热');
    await session.open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    await tester.pumpWidget(_inputView(session, key, mode: PageTurnMode.none));
    final jump = session.jumpToChapter(0);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(session.jumpLoadingTitle, isNotNull);
    expect(source.loads, [1], reason: '目标章未完成时不能重新预排旧位置的第3章');
    source.previous.complete([_page(0)]);
    expect(await jump, isTrue);
    await tester.pumpWidget(_inputView(session, key, mode: PageTurnMode.none));
    await tester.pumpAndSettle();
    expect(source.loads, contains(2), reason: '跳转完成后恢复正常近邻预热');
    await tester.pumpWidget(const SizedBox.shrink());
    await session.flushProgress();
  });

  testWidgets('取消代次之后旧页计时器失效，新代次仍可正常预热', (tester) async {
    final source = _Source();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '取消预热',
    );
    await session.open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    await tester.pumpWidget(_inputView(session, key, mode: PageTurnMode.none));
    session.cancelPendingLoads();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(source.loads, [0]);
    await tester.pumpWidget(_inputView(session, key, mode: PageTurnMode.none));
    await tester.pumpAndSettle();
    expect(source.loads, [0, 1, 2]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('字号重排等待期间不生成旧页图片或快照', (tester) async {
    final source = _RestylingSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '重排预热',
    );
    await session.open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <int>[];
    await tester.pumpWidget(
      _inputView(
        session,
        key,
        prepare: (page) async {
          prepared.add(page.spineIndex);
        },
      ),
    );
    final reflow = session.applyOverrides(const ReaderOverrides(fontSize: 20));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(session.loading, isTrue);
    expect(prepared, isEmpty);
    expect(key.currentState!.snapshotCount, 0);
    source.restyled.complete();
    await reflow;
    await tester.pumpWidget(const SizedBox.shrink());
    await session.flushProgress();
  });

  testWidgets('旧代次图片晚到不重新启动排队快照', (tester) async {
    final session = await _openInputSession();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final images = Completer<void>();
    await tester.pumpWidget(
      _inputView(session, key, prepare: (_) => images.future),
    );
    await tester.pump(const Duration(milliseconds: 100));
    session.cancelPendingLoads();
    images.complete();
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('3D 起手等待着色器期间取消后不把旧页作为新任务截图', (tester) async {
    await tester.runAsync(DuokanCurlShader.load);
    final session = await _openInputSession();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PageTurnView(
          key: key,
          session: session,
          mode: PageTurnMode.simulation3d,
          revision: 1,
          preload: false,
          preparePageImages: (page) async => prepared.add(page.spineIndex),
          paperBuilder: (_, _) => const ColoredBox(color: Colors.white),
          paperColor: Colors.white,
        ),
      ),
    );
    key.currentState!.controller.request(true);
    session.cancelPendingLoads();
    await tester.pumpAndSettle();
    expect(prepared, isEmpty);
    expect(key.currentState!.snapshotCount, 0);
    expect(session.pageTurns, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('后翻后跳到章末，前向内容预排不等待当前页图片', (tester) async {
    final source = _LocatedChapterSource();
    final store = MemoryReaderProgressStore();
    await store.save(
      '跳章末预排',
      const ReaderProgress(spineIndex: 0, pageIndex: 3),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: '跳章末预排',
    );
    await session.open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: session,
        builder: (_, _) => _inputView(
          session,
          key,
          mode: PageTurnMode.simulation3d,
          prepare: (page) => page.spineIndex == 3 && page.pageIndex == 7
              ? gate.future
              : Future<void>.value(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.controller.request(false);
    await tester.pumpAndSettle();
    expect(session.page!.pageIndex, 2);
    expect(key.currentState!.controller.next, isFalse);
    await session.jumpToCfi('epubcfi(/6/8!/4/16/1:0)');
    expect((session.page!.spineIndex, session.page!.pageIndex), (3, 7));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(source.loads, contains(4), reason: '上次后翻方向不能把章末内容预排改为后向');
    expect(gate.isCompleted, isFalse);
    expect(session.pageTurns, 1);
    gate.complete();
    await tester.pumpAndSettle();
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('空闲一百毫秒后才预热，内容预排不等待当前页慢图片', (tester) async {
    final source = _Source();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '内容与位图独立',
    );
    await session.open();
    addTearDown(session.dispose);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <int>[];
    await tester.pumpWidget(
      _inputView(
        session,
        key,
        mode: PageTurnMode.simulation3d,
        prepare: (page) {
          prepared.add(page.spineIndex);
          return page.spineIndex == 0 ? gate.future : Future<void>.value();
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 99));
    expect(prepared, isEmpty);
    expect(source.loads, [0]);
    await tester.pump(const Duration(milliseconds: 1));
    expect(prepared, [0]);
    expect(source.loads, [0, 1], reason: '慢原图不阻塞内容储备，单轮只补一非空章');
    expect(key.currentState!.snapshotCount, 0);
    gate.complete();
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 3);
    expect(session.pageTurns, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('3D 原页图片未完成时已并行准备目标，截图仍按各自纸面捕获', (tester) async {
    final session = await _openInputSession();
    addTearDown(session.dispose);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <int>[];
    await tester.pumpWidget(
      _inputView(
        session,
        key,
        mode: PageTurnMode.simulation3d,
        prepare: (page) {
          prepared.add(page.spineIndex);
          return page.spineIndex == 1 ? gate.future : Future<void>.value();
        },
      ),
    );
    final controller = key.currentState!.controller;
    controller.request(true);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(prepared, [1, 2]);
    expect(controller.phase, PageTurnPhase.preparing);
    expect(controller.originImage, isNull);
    expect(controller.targetImage, isNotNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(session.page!.spineIndex, 2);
    expect(session.pageTurns, 1);
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('3D 纸底只捕获一次、按版本重建并计入位图预算', (tester) async {
    final session = await _openInputSession();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    var paints = 0;
    void background(Canvas canvas, Size size) {
      paints++;
      canvas.drawColor(const Color(0xFFEDE5CF), BlendMode.src);
    }

    Future<void> show(int revision) async {
      await tester.pumpWidget(
        _inputView(
          session,
          key,
          revision: revision,
          mode: PageTurnMode.simulation3d,
          paintBackground: background,
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(1);
    expect(paints, 1);
    expect(key.currentState!.snapshotCount, 4, reason: '三页快照加一张主题纸底');
    expect(
      key.currentState!.snapshotBytes,
      lessThanOrEqualTo(64 * 1024 * 1024),
    );
    key.currentState!.controller.request(true);
    await tester.pumpAndSettle();
    expect(paints, 1, reason: '翻页帧不重新绘制或捕获背景');
    await show(2);
    expect(paints, 2);
    key.currentState!.releaseCachedBitmaps();
    await tester.pump();
    expect(key.currentState!.snapshotCount, 0);
    expect(key.currentState!.snapshotBytes, 0);
    key.currentState!.resumeWarmup();
    await tester.pumpAndSettle();
    expect(paints, 3);
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in PageTurnMode.values.where(
    (mode) => mode != PageTurnMode.none,
  )) {
    testWidgets('${mode.label} 跨两章按近邻优先预热前后各两页', (tester) async {
      final source = _FiveChapterSource();
      final store = MemoryReaderProgressStore();
      await store.save(
        '跨章两页',
        const ReaderProgress(spineIndex: 2, pageIndex: 0),
      );
      final session = ReaderSession(
        source: source,
        store: store,
        bookId: '跨章两页',
      );
      await session.open();
      addTearDown(session.dispose);
      final key = GlobalKey<PageTurnViewState>();
      final prepared = <int>[];
      await tester.pumpWidget(
        _inputView(
          session,
          key,
          mode: mode,
          prepare: (page) async {
            prepared.add(page.spineIndex);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(source.loads, [2, 3, 1, 4, 0]);
      expect(prepared, [2, 3, 1, 4, 0]);
      expect(key.currentState!.snapshotCount, 5);
      expect(
        key.currentState!.snapshotBytes,
        lessThanOrEqualTo(64 * 1024 * 1024),
      );
      expect(
        session.progress,
        const ReaderProgress(spineIndex: 2, pageIndex: 0),
      );
      expect(session.pageTurns, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final mode in [PageTurnMode.cover, PageTurnMode.none]) {
    testWidgets('${mode.label} 前方四页已就绪时不抢跑邻章', (tester) async {
      final source = _LongChapterSource();
      final session = ReaderSession(
        source: source,
        store: MemoryReaderProgressStore(),
        bookId: '章内预取',
      );
      await session.open();
      addTearDown(session.dispose);
      final key = GlobalKey<PageTurnViewState>();
      await tester.pumpWidget(_inputView(session, key, mode: mode));
      await tester.pumpAndSettle();
      expect(source.loads, [0]);
      expect(session.page!.spineIndex, 0);
      expect(session.pageTurns, 0);
      if (mode == PageTurnMode.none) expect(key.currentState!.snapshotCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('静止时预热前后章快照且不改变阅读位置', (tester) async {
    final source = _Source();
    final store = MemoryReaderProgressStore();
    await store.save('warm', const ReaderProgress(spineIndex: 1, pageIndex: 0));
    final session = ReaderSession(source: source, store: store, bookId: 'warm');
    await session.open();
    final key = GlobalKey<PageTurnViewState>();
    final built = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: PageTurnView(
            key: key,
            session: session,
            mode: PageTurnMode.cover,
            revision: 1,
            paperBuilder: (page, size) {
              built.add(page.spineIndex);
              return ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: Text('${page.spineIndex}'),
              );
            },
            paperColor: const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(source.loads.toSet(), containsAll(<int>[0, 1, 2]));
    expect(built.toSet(), containsAll(<int>[0, 1, 2]));
    expect(key.currentState!.snapshotCount, 3);
    expect(session.progress, const ReaderProgress(spineIndex: 1, pageIndex: 0));
    session.dispose();
  });

  testWidgets('快照前等待目标页图片准备完成', (tester) async {
    final source = _Source();
    final store = MemoryReaderProgressStore();
    await store.save(
      'warm-gate',
      const ReaderProgress(spineIndex: 1, pageIndex: 0),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'warm-gate',
    );
    await session.open();
    final key = GlobalKey<PageTurnViewState>();
    final gate = Completer<void>();
    final prepared = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: PageTurnView(
            key: key,
            session: session,
            mode: PageTurnMode.cover,
            revision: 1,
            preparePageImages: (page) {
              prepared.add(page.spineIndex);
              return page.spineIndex == 1 ? gate.future : Future<void>.value();
            },
            paperBuilder: (page, size) => ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Text('${page.spineIndex}'),
            ),
            paperColor: const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(prepared, contains(1));
    expect(key.currentState!.snapshotCount, 0);
    gate.complete();
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(key.currentState!.snapshotCount, 3);
    session.dispose();
  });

  testWidgets('切后台释放翻页位图，回前台后再预热', (tester) async {
    final source = _Source();
    final store = MemoryReaderProgressStore();
    await store.save(
      'warm-lifecycle',
      const ReaderProgress(spineIndex: 1, pageIndex: 0),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'warm-lifecycle',
    );
    await session.open();
    final key = GlobalKey<PageTurnViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: PageTurnView(
            key: key,
            session: session,
            mode: PageTurnMode.cover,
            revision: 1,
            paperBuilder: (page, size) => ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Text('${page.spineIndex}'),
            ),
            paperColor: const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(key.currentState!.snapshotCount, 3);

    key.currentState!.releaseCachedBitmaps();
    await tester.pump();
    expect(key.currentState!.snapshotCount, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(key.currentState!.snapshotCount, 0);

    key.currentState!.resumeWarmup();
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(key.currentState!.snapshotCount, 3);
    session.dispose();
  });

  testWidgets('前进快照不等待尚未完成的后退章节排版', (tester) async {
    final source = _GatedSource();
    final store = MemoryReaderProgressStore();
    await store.save(
      'warm-order',
      const ReaderProgress(spineIndex: 1, pageIndex: 0),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'warm-order',
    );
    await session.open();
    addTearDown(session.dispose);
    addTearDown(() {
      if (!source.previous.isCompleted) source.previous.complete([_page(0)]);
    });
    final key = GlobalKey<PageTurnViewState>();
    await tester.pumpWidget(_inputView(session, key));
    await tester.pumpAndSettle();

    expect(key.currentState!.snapshotCount, 2, reason: '前进页就绪后立即生成快照');
    expect(source.previous.isCompleted, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final complete in [true, false]) {
    testWidgets('${complete ? '完成' : '回退'}缓存翻页不等解码，补图期间保持完整纸面', (tester) async {
      final session = await _openInputSession();
      final gate = Completer<void>();
      var blocked = false;
      addTearDown(session.dispose);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final key = GlobalKey<PageTurnViewState>();
      await tester.pumpWidget(
        _inputView(
          session,
          key,
          prepare: (_) => blocked ? gate.future : Future<void>.value(),
        ),
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.snapshotCount, 3);
      blocked = true;
      final controller = key.currentState!.controller;
      final originSpine = session.page!.spineIndex;
      if (complete) {
        controller.request(true);
      } else {
        const down = Offset(790, 300);
        const latest = Offset(770, 300);
        controller.pointerDown(down);
        controller.beginDrag(DragStartDetails(localPosition: down));
        controller.updateDrag(
          DragUpdateDetails(globalPosition: latest, localPosition: latest),
        );
      }
      await tester.pump();

      expect(
        controller.phase,
        complete ? PageTurnPhase.settling : PageTurnPhase.dragging,
        reason: '已有完整快照时不应等待原图重新解码',
      );
      if (!complete) controller.endDrag(DragEndDetails());
      await tester.pumpAndSettle();
      expect(session.page!.spineIndex, complete ? 2 : originSpine);
      expect(
        find.byKey(const ValueKey('page-turn-static-snapshot')),
        findsOneWidget,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('page-turn-static-snapshot')),
        findsNothing,
      );
      await session.flushProgress();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('前进翻页不等待未完成的上一章图片预热', (tester) async {
    final session = await _openInputSession();
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
      session.dispose();
    });
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <int>[];
    await tester.pumpWidget(
      _inputView(
        session,
        key,
        prepare: (page) {
          prepared.add(page.spineIndex);
          return page.spineIndex == 0 ? gate.future : Future<void>.value();
        },
      ),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(key.currentState!.snapshotCount, 2);
    expect(prepared, contains(0));
    key.currentState!.controller.request(true);
    await tester.pumpAndSettle();

    expect(session.page!.spineIndex, 2, reason: '上一章的图片加载不应阻塞前进输入');
    expect(gate.isCompleted, isFalse);
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final duringTurn in [true, false]) {
    testWidgets('3D ${duringTurn ? '动画中' : '落页后'}刷新版本，补图期间仍保持完整快照', (
      tester,
    ) async {
      final session = await _openInputSession();
      final gate = Completer<void>();
      final revision = ValueNotifier<int>(1);
      var blocked = false;
      addTearDown(session.dispose);
      addTearDown(revision.dispose);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final key = GlobalKey<PageTurnViewState>();
      await tester.pumpWidget(
        ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (_, value, _) => _inputView(
            session,
            key,
            revision: value,
            mode: PageTurnMode.simulation3d,
            prepare: (_) => blocked ? gate.future : Future<void>.value(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      blocked = true;
      key.currentState!.controller.request(true);
      if (duringTurn) {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));
        expect(key.currentState!.controller.active, isTrue);
        revision.value++;
      }
      await tester.pumpAndSettle();
      expect(session.page!.spineIndex, 2);
      expect(
        find.byKey(const ValueKey('page-turn-static-snapshot')),
        findsOneWidget,
      );

      if (!duringTurn) {
        revision.value++;
        await tester.pump();
      }
      expect(gate.isCompleted, isFalse);
      expect(
        find.byKey(const ValueKey('page-turn-static-snapshot')),
        findsOneWidget,
        reason: '补图未完成时版本刷新只能失效预热缓存，不能撤下落页快照',
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('page-turn-static-snapshot')),
        findsNothing,
      );
      await session.flushProgress();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('收尾后的纸面版本刷新不丢失尚未松手的下一次滑动', (tester) async {
    final session = await _openInputSession();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final revision = ValueNotifier<int>(1);
    addTearDown(revision.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: revision,
        builder: (_, value, _) => _inputView(session, key, revision: value),
      ),
    );
    await tester.pumpAndSettle();
    final controller = key.currentState!.controller;
    controller.request(false);
    await tester.pump();
    final down = Offset(controller.size.width - 10, controller.size.height / 2);
    final latest = down.translate(-controller.size.width * 0.6, 0);
    controller.pointerDown(down);
    controller.beginDrag(DragStartDetails(localPosition: down));
    controller.updateDrag(
      DragUpdateDetails(globalPosition: latest, localPosition: latest),
    );
    revision.value++;
    await tester.pumpAndSettle();
    expect(session.page!.spineIndex, 0);
    controller.endDrag(DragEndDetails());
    await tester.pumpAndSettle();

    expect(session.page!.spineIndex, 1);
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('章内预热当前页前后各两页', (tester) async {
    final source = _LongChapterSource();
    final store = MemoryReaderProgressStore();
    await store.save(
      'warm-radius',
      const ReaderProgress(spineIndex: 1, pageIndex: 3),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'warm-radius',
    );
    await session.open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    await tester.pumpWidget(_inputView(session, key));
    await tester.pumpAndSettle();

    expect(key.currentState!.snapshotCount, 5, reason: '当前页加前后各两页');
    expect(session.adjacentPages.length, 4);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
