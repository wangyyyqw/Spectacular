import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

class _SparseSource implements ReaderChapterSource {
  _SparseSource(this.blockedSpine);

  final int blockedSpine;
  final gate = Completer<void>();
  final loads = <int>[];

  @override
  int get chapterCount => 8;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    if (spineIndex == blockedSpine) await gate.future;
    return [
      if ({0, 1, 7}.contains(spineIndex))
        PageContent(
          spineIndex: spineIndex,
          pageIndex: 0,
          slices: const [],
          usedHeight: 0,
          pageHeight: 480,
          topPadding: 0,
        ),
    ];
  }
}

Widget _view(
  ReaderSession session,
  GlobalKey<PageTurnViewState> key,
  PageTurnMode mode,
) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 320,
      height: 480,
      child: ListenableBuilder(
        listenable: session,
        builder: (_, _) => PageTurnView(
          key: key,
          session: session,
          mode: mode,
          revision: 1,
          paperColor: Colors.white,
          paperBuilder: (page, size) => ColoredBox(
            color: Colors.white,
            child: Text('章节 ${page.spineIndex}'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 35 && !ready(); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: '应到达待检查的预热或翻页阶段');
}

void _startDrag(PageTurnController controller) {
  const down = Offset(310, 240);
  const touch = Offset(110, 240);
  controller.pointerDown(down);
  controller.beginDrag(DragStartDetails(localPosition: down));
  controller.updateDrag(
    DragUpdateDetails(localPosition: touch, globalPosition: touch),
  );
}

void main() {
  for (final mode in [
    PageTurnMode.simulationBessel,
    PageTurnMode.simulation3d,
  ]) {
    testWidgets('${mode.label} 空章预热期间仍能提交已准备的邻章', (tester) async {
      final source = _SparseSource(mode == PageTurnMode.simulation3d ? 5 : 2);
      final session = ReaderSession(
        source: source,
        store: MemoryReaderProgressStore(),
        bookId: '空章预热回归',
      );
      await session.open();
      addTearDown(session.dispose);
      final key = GlobalKey<PageTurnViewState>();
      await tester.pumpWidget(_view(session, key, mode));
      await _pumpUntil(
        tester,
        () => source.loads.contains(source.blockedSpine),
      );
      final controller = key.currentState!.controller;
      _startDrag(controller);
      await _pumpUntil(
        tester,
        () => controller.phase == PageTurnPhase.dragging,
      );
      expect(controller.turn!.target.spineIndex, 1);
      source.gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(source.loads, isNot(contains(7)), reason: '手势期间不续排后续空章');
      controller.endDrag(DragEndDetails());
      await tester.pumpAndSettle();
      expect(session.page!.spineIndex, 1, reason: '预热不能淘汰正在翻向的章节');
      expect(session.pageTurns, 1, reason: '收尾只提交一次阅读位置');
      await session.flushProgress();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
