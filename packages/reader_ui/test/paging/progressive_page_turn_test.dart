import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
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
            revision: session.pageCountRevision,
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
    source.publish(1, 3);
    await tester.pump(const Duration(milliseconds: 16));
    expect(key.currentState!.controller.active, isTrue);
    source.complete(1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      key.currentState!.controller.active,
      isTrue,
      reason: '总页数补全在动画结束后刷新快照',
    );
    await tester.pumpAndSettle();
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
}
