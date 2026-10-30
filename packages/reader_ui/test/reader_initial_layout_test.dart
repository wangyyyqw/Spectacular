import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

class _Source implements RestylableChapterSource, ResizableChapterSource {
  final loads = <({int spine, double? font, double? width, double? height})>[];
  final Set<int> empty = {};
  Completer<void>? gate;
  ReaderOverrides overrides = const ReaderOverrides();
  double? width;
  double? height;
  double topInset = 0;

  @override
  int get chapterCount => 2000;

  @override
  Future<void> applyOverrides(ReaderOverrides value) async => overrides = value;

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
  }) async {
    final changed =
        this.width != width ||
        this.height != height ||
        this.topInset != topInset;
    this.width = width;
    this.height = height;
    this.topInset = topInset;
    return changed;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add((
      spine: spineIndex,
      font: overrides.fontSize,
      width: width,
      height: height,
    ));
    await gate?.future;
    return [
      if (!empty.contains(spineIndex))
        for (var page = 0; page < 3; page++)
          PageContent(
            spineIndex: spineIndex,
            pageIndex: page,
            slices: const [],
            usedHeight: 0,
            pageHeight: height ?? 100,
            topPadding: 0,
          ),
    ];
  }
}

Future<ReaderSession> _restored(_Source source) async {
  final store = MemoryReaderProgressStore();
  await store.save(
    'saved',
    const ReaderProgress(spineIndex: 1500, pageIndex: 1),
  );
  final session = ReaderSession(source: source, store: store, bookId: 'saved');
  await session.open();
  return session;
}

void main() {
  test('正文尺寸相同时，上内缩变化仍传给章节源并重排', () async {
    final source = _Source();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'top-inset',
    );
    addTearDown(session.dispose);
    await session.open(
      contentWidth: 300,
      contentHeight: 500,
      contentTopInset: 80,
    );
    expect(source.topInset, 80);
    source.loads.clear();
    await session.applyContentSize(width: 300, height: 500, topInset: 100);
    expect(source.topInset, 100);
    expect(source.loads.map((e) => e.spine), [0]);
    source.loads.clear();
    await session.applyContentSize(width: 300, height: 500, topInset: 100);
    expect(source.loads, isEmpty);
  });

  test('保存的高章序直接恢复，改字号及尺寸仅重排当前章一次', () async {
    final source = _Source();
    final session = await _restored(source);
    expect(source.loads.map((e) => e.spine), [1500]);
    expect(
      session.progress,
      const ReaderProgress(spineIndex: 1500, pageIndex: 1),
    );
    source.loads.clear();
    await session.applyOverrides(const ReaderOverrides(fontSize: 23));
    expect(source.loads.map((e) => e.spine), [1500]);
    source.loads.clear();
    await session.applyContentSize(width: 310, height: 768);
    expect(source.loads.map((e) => e.spine), [1500]);
    session.dispose();
  });

  test('上一章跳转越过空章仍向前，落在前一有内容章首页', () async {
    final source = _Source()..empty.addAll([1498, 1499]);
    final session = await _restored(source);
    await session.jumpToChapter(1499);
    expect(
      session.progress,
      const ReaderProgress(spineIndex: 1497, pageIndex: 0),
    );
    expect(source.loads.map((e) => e.spine), [1500, 1499, 1498, 1497]);
    session.dispose();
  });

  testWidgets('阅读页首排直接使用最终字号和可用尺寸，只加载一次', (tester) async {
    final source = _Source();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          bookId: 'initial',
          padding: EdgeInsets.zero,
          showPageFooter: false,
          overrides: const ReaderOverrides(fontSize: 23),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.loads, [(spine: 0, font: 23.0, width: 800.0, height: 600.0)]);
  });

  testWidgets('首开未完成时改变尺寸会在完成后重排，不会卡在加载态', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gate = Completer<void>();
    final source = _Source()..gate = gate;
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          bookId: 'resize',
          padding: EdgeInsets.zero,
          showPageFooter: false,
          onSessionReady: (value) => session = value,
        ),
      ),
    );
    await tester.pump();
    await tester.binding.setSurfaceSize(const Size(400, 600));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(session.loading, isFalse);
    expect(session.page, isNotNull);
    expect(source.loads.map((e) => e.width), [
      760,
      360,
    ], reason: '扣除默认左右各 20 像素页边距');
    await tester.binding.setSurfaceSize(null);
  });
}
