import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/panels/margin_editor.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/theme/reader_margins.dart';

import '../support/test_epub.dart';

void main() {
  testWidgets('拖动只重排当前章，保存后已访问和未访问章节均按需更新', (tester) async {
    final harness = await _mountReader(tester);
    final session = harness.session;
    await session.jumpToChapter(1);
    final oldOtherCount = session.chapterPageCount;
    await session.jumpToChapter(0);
    await tester.pumpAndSettle();
    final beforeCount = session.chapterPageCount;
    final beforeHeight = session.contentHeight!;
    harness.source.loads.clear();
    await _openEditor(tester);
    final view = tester.getRect(find.byType(ReaderView));
    await tester.tapAt(view.topRight + Offset(-4, view.height * 0.4));
    await tester.pumpAndSettle();
    expect(session.progress!.pageIndex, 0, reason: '编辑时点击空白不应穿透翻页');
    final change =
        60 -
        tester
            .widget<MarginEditor>(find.byType(MarginEditor))
            .margins
            .bottomInner;
    await tester.drag(_control('bottom-inner'), const Offset(0, -48));
    await tester.pumpAndSettle();
    expect(session.chapterPageCount, greaterThan(beforeCount));
    expect(session.contentHeight, beforeHeight - change);
    expect(harness.source.loads, isNotEmpty);
    expect(harness.source.loads.every((spine) => spine == 0), isTrue);
    expect(harness.applied, isEmpty, reason: '预览不写入边距设置');
    _expectHeaderMatches(tester, session);
    final loads = harness.source.loads.length;
    await tester.tap(_control('apply'));
    await tester.pumpAndSettle();
    expect(harness.applied, hasLength(1));
    expect(harness.source.loads.length, loads, reason: '保存不重复排当前章，也不预排其他章');
    await session.jumpToChapter(1);
    await tester.pumpAndSettle();
    expect(harness.source.loads.last, 1);
    expect(session.page!.pageHeight, beforeHeight - change);
    expect(session.chapterPageCount, greaterThan(oldOtherCount));
    expect(harness.source.loads, isNot(contains(2)));
    await session.jumpToChapter(2);
    await tester.pumpAndSettle();
    expect(harness.source.loads.last, 2);
    expect(session.page!.pageHeight, beforeHeight - change);
  });

  testWidgets('章内页码变化不打断拖动，取消恢复分页、原页与持久化进度', (tester) async {
    final harness = await _mountReader(tester);
    final session = harness.session;
    for (var index = 0; index < 8; index++) {
      expect(await session.next(), isTrue);
    }
    await session.flushProgress();
    await tester.pumpAndSettle();
    final before = session.progress!;
    final beforeCount = session.chapterPageCount;
    final beforeHeight = session.contentHeight!;
    await _openEditor(tester);
    final editor = tester.state(find.byType(MarginEditor));
    final origin = tester.getCenter(_control('top-outer'));
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(0, 20));
    await tester.pumpAndSettle();
    for (var index = 0; index < 10; index++) {
      await gesture.moveBy(const Offset(0, 3));
      await tester.pumpAndSettle();
      expect(session.contentHeight, beforeHeight - 23 - index * 3);
      expect(tester.state(find.byType(MarginEditor)), same(editor));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(session.progress!.pageIndex, greaterThan(before.pageIndex));
    expect(
      tester.getCenter(_control('top-outer')) - origin,
      const Offset(0, 50),
    );
    _expectHeaderMatches(tester, session);
    await session.flushProgress();
    expect(await harness.store.load('margin-pagination'), before);
    await tester.tap(_control('cancel'));
    await tester.pumpAndSettle();
    expect(session.chapterPageCount, beforeCount);
    expect(session.contentHeight, beforeHeight);
    expect(session.progress, before);
    expect(harness.applied, isEmpty);
    _expectHeaderMatches(tester, session);
  });

  testWidgets('保存时等待在途重排完成再允许翻页，不抢跑其他章节', (tester) async {
    final harness = await _mountReader(tester);
    await _openEditor(tester);
    final before = harness.session.progress;
    final height = harness.session.contentHeight!;
    harness.source.loadGate = Completer<void>();
    await tester.drag(_control('top-outer'), const Offset(0, 24));
    await tester.pump();
    await tester.tap(_control('apply'));
    await tester.pump();
    expect(find.byType(MarginEditor), findsNothing);
    expect(_control('pagination-barrier'), findsOneWidget);
    final view = tester.getRect(find.byType(ReaderView));
    await tester.tapAt(view.topRight + Offset(-4, view.height * 0.4));
    await tester.pump();
    expect(harness.session.progress, before);
    harness.source.loadGate!.complete();
    await tester.pumpAndSettle();
    expect(_control('pagination-barrier'), findsNothing);
    expect(harness.session.contentHeight, height - 24);
    expect(harness.source.loads.every((spine) => spine == 0), isTrue);
  });
}

Finder _control(String name) => find.byKey(ValueKey<String>('margin-$name'));

void _expectHeaderMatches(WidgetTester tester, ReaderSession session) {
  final header = tester.widget<ReaderPageHeader>(find.byType(ReaderPageHeader));
  expect(
    header.pageLabel,
    '${session.progress!.pageIndex + 1}/${session.chapterPageCount}',
  );
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('menu-entry-type')));
  await tester.pumpAndSettle();
  final entry = find.byKey(const ValueKey<String>('settings-margin-editor'));
  await tester.scrollUntilVisible(
    entry,
    80,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

Future<_Harness> _mountReader(WidgetTester tester) async {
  final chapter = List.filled(
    180,
    '本章正文用于验证边距调节中的分页变化，阅读位置应保持在原来的文字附近。',
  ).join();
  final source = await openTestChapterSource(
    buildMultiChapterEpub(chapters: [chapter, chapter, chapter]),
  );
  final harness = _Harness(_CountingSource(source));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 520,
            child: ReaderPage(
              source: harness.source,
              store: harness.store,
              bookId: 'margin-pagination',
              onSessionReady: (value) => harness.session = value,
              onMarginsChanged: harness.applied.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

class _Harness {
  _Harness(this.source);

  final _CountingSource source;
  final store = MemoryReaderProgressStore();
  final applied = <ReaderMargins>[];
  late ReaderSession session;
}

class _CountingSource
    implements RestylableChapterSource, ResizableChapterSource {
  _CountingSource(this.delegate);

  final EpubChapterSource delegate;
  final loads = <int>[];
  Completer<void>? loadGate;

  @override
  int get chapterCount => delegate.chapterCount;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    await loadGate?.future;
    return delegate.loadChapter(spineIndex);
  }

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) =>
      delegate.applyOverrides(overrides);

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
  }) => delegate.applyContentSize(
    width: width,
    height: height,
    topInset: topInset,
  );
}
