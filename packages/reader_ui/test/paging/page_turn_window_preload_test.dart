import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';

class _Source implements ReaderChapterSource {
  final pages = List.generate(
    9,
    (index) => PageContent(
      spineIndex: 0,
      pageIndex: index,
      slices: const [],
      usedHeight: 0,
      pageHeight: 400,
      topPadding: 0,
    ),
  );

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => pages;
}

Future<ReaderSession> _open() async {
  final store = MemoryReaderProgressStore();
  await store.save('窗口', const ReaderProgress(spineIndex: 0, pageIndex: 3));
  final session = ReaderSession(source: _Source(), store: store, bookId: '窗口');
  await session.open();
  return session;
}

Widget _view(
  ReaderSession session,
  GlobalKey<PageTurnViewState> key,
  ReaderPageImagesPreparer prepare,
  PageTurnMode mode,
) => MaterialApp(
  home: ListenableBuilder(
    listenable: session,
    builder: (_, _) => PageTurnView(
      key: key,
      session: session,
      mode: mode,
      revision: 1,
      paperBuilder: (page, size) =>
          ColoredBox(color: Colors.white, child: Text('${page.pageIndex}')),
      paperColor: Colors.white,
      preparePageImages: prepare,
    ),
  ),
);

void main() {
  for (final mode in [
    PageTurnMode.cover,
    PageTurnMode.coverStack,
    PageTurnMode.simulationBessel,
    PageTurnMode.slideHorizontal,
  ]) {
    testWidgets('${mode.label} 成功提交仅补窗口差集，回退不移动窗口', (tester) async {
      final session = await _open();
      addTearDown(session.dispose);
      final key = GlobalKey<PageTurnViewState>();
      final prepared = <int>[];
      await tester.pumpWidget(
        _view(session, key, (page) async {
          prepared.add(page.pageIndex);
        }, mode),
      );
      await tester.pumpAndSettle();
      expect(prepared, [3, 4, 2, 5, 1]);
      final controller = key.currentState!.controller;
      controller.pointerDown(const Offset(790, 300));
      controller.beginDrag(
        DragStartDetails(localPosition: const Offset(790, 300)),
      );
      controller.updateDrag(
        DragUpdateDetails(
          globalPosition: const Offset(770, 300),
          localPosition: const Offset(770, 300),
        ),
      );
      await tester.pump();
      controller.endDrag(DragEndDetails());
      await tester.pumpAndSettle();
      expect(session.page!.pageIndex, 3);
      expect(key.currentState!.snapshotCount, 5);
      expect(prepared.where((index) => index != 3), [4, 2, 5, 1]);
      prepared.clear();
      controller.request(true);
      await tester.pumpAndSettle();
      expect(session.page!.pageIndex, 4);
      expect(key.currentState!.snapshotCount, 5);
      expect(prepared.where((index) => index != 4), [6]);
      prepared.clear();
      controller.request(false);
      await tester.pumpAndSettle();
      expect(session.page!.pageIndex, 3);
      expect(key.currentState!.snapshotCount, 5);
      expect(prepared.where((index) => index != 3), [1]);
      await session.flushProgress();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('窗口外的延迟准备不阻塞翻页且完成后不回写缓存', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <int>[];
    await tester.pumpWidget(
      _view(session, key, (page) {
        prepared.add(page.pageIndex);
        return page.pageIndex == 1 ? gate.future : Future<void>.value();
      }, PageTurnMode.cover),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 4);
    expect(prepared, [3, 4, 2, 5, 1]);
    key.currentState!.controller.request(true);
    await tester.pumpAndSettle();
    expect(session.page!.pageIndex, 4);
    expect(key.currentState!.snapshotCount, 5);
    gate.complete();
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 5);
    expect(prepared.where((index) => index == 1).length, 1);
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('目标预热复用同一准备任务，后台截图推迟到收尾后', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final prepared = <int>[];
    final key = GlobalKey<PageTurnViewState>();
    await tester.pumpWidget(
      _view(session, key, (page) {
        prepared.add(page.pageIndex);
        return page.pageIndex == 4 ? gate.future : Future<void>.value();
      }, PageTurnMode.cover),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(prepared, [3, 4]);
    final controller = key.currentState!.controller;
    controller.pointerDown(const Offset(790, 300));
    controller.beginDrag(
      DragStartDetails(localPosition: const Offset(790, 300)),
    );
    controller.updateDrag(
      DragUpdateDetails(
        globalPosition: const Offset(500, 300),
        localPosition: const Offset(500, 300),
      ),
    );
    await tester.pump();
    expect(controller.phase, PageTurnPhase.preparing);
    expect(prepared.where((index) => index == 4).length, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.phase, PageTurnPhase.dragging);
    expect(session.page!.pageIndex, 3);
    expect(key.currentState!.snapshotCount, 2);
    expect(prepared, [3, 4, 2]);
    controller.cancel();
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 5);
    expect(prepared.where((index) => index == 2).length, 1);
    expect(prepared, containsAll([3, 4, 2, 5, 1]));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
