import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';

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
}) => MaterialApp(
  home: PageTurnView(
    key: key,
    session: session,
    mode: PageTurnMode.cover,
    revision: revision,
    preparePageImages: prepare,
    paperBuilder: (page, size) => ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Text('${page.spineIndex}'),
    ),
    paperColor: const Color(0xFFFFFFFF),
  ),
);

void main() {
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
}
