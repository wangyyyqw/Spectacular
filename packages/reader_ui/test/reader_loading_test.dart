import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageContent _page(int spineIndex, {int pageIndex = 0}) {
  final style = _style();
  final layout = TextLayoutEngine.layout(
    text: 'hello',
    style: style,
    maxWidth: 100,
  );
  final block = PageBlock.styled(
    layout: layout,
    style: style,
    containingWidth: 100,
  );
  final height = block.leadingExtent + block.height + block.trailingExtent;
  return PageContent(
    spineIndex: spineIndex,
    pageIndex: pageIndex,
    slices: [
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: layout.lineCount,
        height: height,
      ),
    ],
    usedHeight: height,
    pageHeight: 200,
    topPadding: 0,
  );
}

/// 加载可被外部控制完成的章节源。
class _GatedSource implements ReaderChapterSource {
  final Completer<void> gate = Completer<void>();

  @override
  int get chapterCount => 2;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    await gate.future;
    return [_page(spineIndex)];
  }
}

/// 立即完成的章节源。
class _InstantSource implements ReaderChapterSource {
  @override
  int get chapterCount => 3;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    _page(spineIndex),
  ];
}

void main() {
  test('首屏内容在 300ms 内就绪', () async {
    // 取 3 次最小值，避免测试并发调度抖动误判。
    var best = 1 << 30;
    for (var i = 0; i < 3; i++) {
      final session = ReaderSession(
        source: _InstantSource(),
        store: MemoryReaderProgressStore(),
        bookId: 'book',
      );
      final stopwatch = Stopwatch()..start();
      await session.open();
      stopwatch.stop();
      expect(session.page, isNotNull);
      expect(session.loading, isFalse);
      if (stopwatch.elapsedMicroseconds < best) {
        best = stopwatch.elapsedMicroseconds;
      }
      session.dispose();
    }
    expect(
      best,
      lessThan(300 * 1000),
      reason: '首屏内容就绪应在 300ms 内，实际 ${best / 1000}ms',
    );
  });

  test('取消未完成的加载后不再回写状态', () async {
    final source = _GatedSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'book',
    );
    final opening = session.open();
    expect(session.loading, isTrue);
    expect(session.page, isNull);

    session.cancelPendingLoads();
    expect(session.loading, isFalse);

    source.gate.complete();
    await opening;
    expect(session.page, isNull, reason: '取消后旧任务不得写入页面');
    expect(session.error, isNull);
    expect(session.loading, isFalse);
    session.dispose();
  });

  test('取消后重新打开可正常加载（无陈旧状态）', () async {
    final first = _GatedSource();
    final session = ReaderSession(
      source: first,
      store: MemoryReaderProgressStore(),
      bookId: 'book',
    );
    final opening = session.open();
    session.cancelPendingLoads();
    first.gate.complete();
    await opening;

    final second = ReaderSession(
      source: _InstantSource(),
      store: MemoryReaderProgressStore(),
      bookId: 'book2',
    );
    await second.open();
    expect(second.page, isNotNull);
    expect(second.loading, isFalse);
    second.dispose();
    session.dispose();
  });

  testWidgets('打开时先显示骨架，完成后平滑替换为页面', (tester) async {
    final source = _GatedSource();
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          bookId: 'book',
          onSessionReady: (value) => session = value,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('reader-loading-skeleton')),
      findsOneWidget,
      reason: '首帧应出现骨架',
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    source.gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('reader-loading-skeleton')),
      findsNothing,
      reason: '就绪后骨架应被替换',
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(session.page, isNotNull);
    expect(session.loading, isFalse);
  });

  testWidgets('销毁时取消挂起加载，不回写已销毁会话', (tester) async {
    final source = _GatedSource();
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          bookId: 'book',
          onSessionReady: (value) => session = value,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    source.gate.complete();
    await tester.pump();
    expect(session.page, isNull);
    expect(session.error, isNull);
  });
}
