import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/progressive_source.dart';

void main() {
  testWidgets('余页追加不取消跨章动画，空闲后重新预热新邻页', (tester) async {
    final source = ProgressiveTestSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '渐进动画',
    );
    await session.open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final images = <PageContent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: session,
          builder: (_, _) => PageTurnView(
            key: key,
            session: session,
            mode: PageTurnMode.cover,
            revision: 0,
            preparePageImages: (page) async => images.add(page),
            paperBuilder: (page, _) => ColoredBox(
              color: Colors.white,
              child: Text('${page.spineIndex}/${page.pageIndex}'),
            ),
            paperColor: Colors.white,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final first = source.chapters[1].first;
    expect(images, contains(first));
    key.currentState!.controller.request(true);
    await tester.pump(const Duration(milliseconds: 16));
    expect(key.currentState!.controller.active, isTrue);
    expect(source.backgroundPaused, isTrue, reason: '翻页活动暂停后台排版');
    source.publish(1, 3);
    await tester.pump(const Duration(milliseconds: 16));
    expect(key.currentState!.controller.active, isTrue);
    source.publishPageCount(1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(key.currentState!.controller.active, isTrue);
    expect(source.handles[1]!.isComplete, isFalse);
    source.complete(1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      key.currentState!.controller.active,
      isTrue,
      reason: '总页数补全在动画结束后刷新快照',
    );
    await tester.pumpAndSettle();
    expect(source.backgroundPaused, isFalse, reason: '动画结束后恢复空闲排版');
    expect(session.page, same(first));
    expect(session.pageTurns, 1);
    expect(images, contains(source.chapters[1][1]));
    expect(images, contains(source.chapters[1][2]));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(session.page, same(first));
    expect(session.chapterPageCount, 6);
    await tester.pumpWidget(const SizedBox.shrink());
    await session.flushProgress();
  });

  testWidgets('右上角在总数确定的下一帧显示，不等待整章缓存完成', (tester) async {
    final source = ProgressiveTestSource(
      counts: [6],
      heldSpines: {0},
      initialPages: 3,
    );
    final store = MemoryReaderProgressStore();
    await store.save(
      '提前显示页码',
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
    );
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: source,
          store: store,
          bookId: '提前显示页码',
          pageTurnMode: PageTurnMode.none,
          onSessionReady: (value) => session = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final header = find.byType(ReaderPageHeader);
    expect(tester.widget<ReaderPageHeader>(header).pageLabel, '第 2 页');
    final page = session.page;
    source.publishPageCount(0);
    await tester.pump();
    expect(tester.widget<ReaderPageHeader>(header).pageLabel, '2/6');
    expect(
      find.descendant(of: header, matching: find.text('2/6')),
      findsOneWidget,
    );
    expect(source.handles[0]!.isComplete, isFalse);
    expect(session.page, same(page));
    source.complete(0);
    await tester.pumpAndSettle();
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('冷翻页截图期间收到总数，仍完成本次翻页并在落页后刷新', (tester) async {
    final source = ProgressiveTestSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '冷翻页总数',
    );
    await session.open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    var published = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: session,
          builder: (_, _) => PageTurnView(
            key: key,
            session: session,
            mode: PageTurnMode.cover,
            revision: 0,
            preload: false,
            paperBuilder: (page, _) {
              if (page.spineIndex == 1 && !published) {
                published = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  source.publishPageCount(1);
                });
              }
              return ColoredBox(
                color: Colors.white,
                child: Text(session.pageLabelOf(page)),
              );
            },
            paperColor: Colors.white,
          ),
        ),
      ),
    );
    expect(key.currentState!.snapshotCount, 0);
    key.currentState!.controller.request(true);
    await tester.pumpAndSettle();
    expect(published, isTrue);
    expect(session.page, same(source.chapters[1].first));
    expect(session.pageTurns, 1);
    expect(session.chapterPageCount, 6);
    expect(source.handles[1]!.isComplete, isFalse);
    source.complete(1);
    await tester.pumpAndSettle();
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 按真实交互顺序核验预热与通知，保留就近夹具以观察快照和作业的身份。
  testWidgets('邻章总数更新保留当前章快照，不取消预排或重复准备当前章图片', (tester) async {
    final source = ProgressiveTestSource(counts: [2, 6], initialPages: 3);
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '页码局部刷新',
    );
    await session.open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <PageContent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: session,
          builder: (_, _) => PageTurnView(
            key: key,
            session: session,
            mode: PageTurnMode.cover,
            revision: 0,
            paperBuilder: (page, _) => ColoredBox(
              color: Colors.white,
              child: Text(session.pageLabelOf(page)),
            ),
            preparePageImages: (page) async => prepared.add(page),
            paperColor: Colors.white,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 3);
    final currentPreparations = prepared
        .where((page) => page.spineIndex == 0)
        .length;
    final handle = source.handles[1];
    source.publishPageCount(1);
    await tester.pump();
    expect(key.currentState!.snapshotCount, 2, reason: '只撤下页码变化的邻章快照');
    expect(source.handles[1], same(handle));
    expect(handle!.cancelled, isFalse);
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 3);
    expect(
      prepared.where((page) => page.spineIndex == 0),
      hasLength(currentPreparations),
    );
    expect(source.requests, [0, 1]);
    source.complete(1);
    await tester.pumpAndSettle();
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
