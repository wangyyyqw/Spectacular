import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

class _RestylableSource implements RestylableChapterSource {
  final gate = Completer<void>();
  double fontSize = 16;

  @override
  int get chapterCount => 3;

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    await gate.future;
    fontSize = overrides.fontSize ?? fontSize;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = ComputedStyle({'font-size': '${fontSize}px'});
    final layout = TextLayoutEngine.layout(
      text: '第 $spineIndex 章',
      style: style,
      maxWidth: 300,
    );
    return [
      PageContent(
        spineIndex: spineIndex,
        pageIndex: 0,
        slices: [
          PageBlockSlice(
            block: PageBlock(
              layout: layout,
              style: style,
              startCfi: 'epubcfi(/6/${(spineIndex + 1) * 2}!/4/2/1:0)',
            ),
            startLine: 0,
            endLine: layout.lineCount,
            height: layout.height,
          ),
        ],
        usedHeight: layout.height,
        pageHeight: 400,
        topPadding: 0,
      ),
    ];
  }
}

class _RetryStore extends MemoryReaderProgressStore {
  int attempts = 0;

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    attempts++;
    if (attempts == 1) throw StateError('模拟暂时写入失败');
    await super.save(bookId, progress);
  }
}

class _NavigationSource extends _RestylableSource {
  @override
  int get chapterCount => 4;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (spineIndex == 1) return [];
    final page = (await super.loadChapter(spineIndex)).single;
    return [
      for (var index = 0; index < 2; index++)
        PageContent(
          spineIndex: spineIndex,
          pageIndex: index,
          slices: page.slices,
          usedHeight: page.usedHeight,
          pageHeight: page.pageHeight,
          topPadding: page.topPadding,
        ),
    ];
  }
}

class _GatedStore extends MemoryReaderProgressStore {
  final gate = Completer<void>();
  final writes = <ReaderProgress>[];
  bool failFirst = false;

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    writes.add(progress);
    if (writes.length == 1) {
      await gate.future;
      if (failFirst) throw StateError('模拟在途写入失败');
    }
    await super.save(bookId, progress);
  }
}

void main() {
  test('分页导航覆盖章边界并在重新打开时恢复书尾', () async {
    final store = MemoryReaderProgressStore();
    final session = ReaderSession(
      source: _NavigationSource(),
      store: store,
      bookId: '导航闭环',
    );
    await session.open();
    expect(session.progress?.spineIndex, 0);
    expect(await session.previous(), isFalse);
    expect(await session.next(), isTrue);
    expect(session.progress?.pageIndex, 1);
    final prepared = await session.preparePageTurn(true);
    expect(session.progress?.spineIndex, 0);
    expect(session.commitPageTurn(prepared!), isTrue);
    expect(session.commitPageTurn(prepared), isFalse);
    expect(session.progress?.spineIndex, 2, reason: '跨章时跳过空章');
    expect(session.progress?.pageIndex, 0);
    expect(await session.next(), isTrue);
    expect(session.progress?.pageIndex, 1);
    while (await session.next()) {}
    expect(session.progress?.spineIndex, 3);
    expect(session.progress?.finished, isTrue);
    expect(await session.next(), isFalse);
    await session.flushProgress();
    final saved = session.progress;
    session.dispose();

    final restored = ReaderSession(
      source: _NavigationSource(),
      store: store,
      bookId: '导航闭环',
    );
    addTearDown(restored.dispose);
    await restored.open();
    expect(restored.progress, saved);
    expect(restored.currentText, contains('第 3 章'));
  });

  test('设置重排后保持当前章节的 CFI 锚点', () async {
    final source = _RestylableSource()..gate.complete();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '锚点恢复',
    );
    addTearDown(session.dispose);
    await session.open();
    await session.next();
    final anchor = session.currentCfi;

    await session.applyOverrides(const ReaderOverrides(fontSize: 24));

    expect(session.loading, isFalse);
    expect(session.error, isNull);
    expect(session.progress?.spineIndex, 1);
    expect(session.currentCfi, anchor);
    expect(session.page?.slices.first.block.style?.fontSize, 24);
  });

  test('进度保存失败后相同位置可以重新落盘', () async {
    final store = _RetryStore();
    final session = ReaderSession(
      source: _RestylableSource(),
      store: store,
      bookId: '重试',
    );
    addTearDown(session.dispose);
    await session.open();
    await session.next();

    await expectLater(session.flushProgress(), throwsStateError);
    await session.flushProgress();

    expect(store.attempts, 2);
    expect(await store.load('重试'), session.progress);
  });

  test('在途进度保存与退出保存按顺序完成', () async {
    final store = _GatedStore();
    final session = ReaderSession(
      source: _RestylableSource(),
      store: store,
      bookId: '串行',
    );
    await session.open();
    await session.next();
    final first = session.flushProgress();
    await session.next();
    final latest = session.progress;
    session.dispose();
    await Future<void>.value();
    expect(store.writes, hasLength(1));

    store.gate.complete();
    await first;
    await session.flushProgress();
    expect(store.writes, hasLength(2));
    expect(await store.load('串行'), latest);
  });

  test('退出时重试失败的在途写入并保存最终位置', () async {
    final store = _GatedStore()..failFirst = true;
    final session = ReaderSession(
      source: _RestylableSource(),
      store: store,
      bookId: '退出重试',
    );
    await session.open();
    await session.next();
    final failed = expectLater(session.flushProgress(), throwsStateError);
    await session.next();
    final latest = session.progress;
    session.dispose();
    store.gate.complete();
    await failed;
    await Future<void>.value();
    expect(store.writes, hasLength(2));
    expect(await store.load('退出重试'), latest);
  });

  for (final cfi in [false, true]) {
    test('重排期间${cfi ? 'CFI' : '章节'}跳转等待新分页并结束加载', () async {
      final source = _RestylableSource();
      final session = ReaderSession(
        source: source,
        store: MemoryReaderProgressStore(),
        bookId: '重排跳转',
      );
      addTearDown(session.dispose);
      await session.open();
      final reload = session.applyOverrides(
        const ReaderOverrides(fontSize: 24),
      );
      expect(session.loading, isTrue);
      final jump = cfi
          ? session.jumpToCfi('epubcfi(/6/4!/4/2/1:0)')
          : session.jumpToChapter(1);
      source.gate.complete();
      await reload;
      expect(await jump, isTrue);

      expect(session.loading, isFalse);
      expect(session.progress?.spineIndex, 1);
      expect(session.page?.slices.first.block.style?.fontSize, 24);
      expect(await session.preparePageTurn(true), isNotNull);
    });
  }

  test('重排期间多个跳转只提交最后一个目标', () async {
    final source = _RestylableSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '最新跳转',
    );
    addTearDown(session.dispose);
    await session.open();
    final reload = session.applyOverrides(const ReaderOverrides(fontSize: 24));
    final first = session.jumpToChapter(1);
    final second = session.jumpToCfi('epubcfi(/6/6!/4/2/1:0)');
    source.gate.complete();
    await reload;

    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(session.progress?.spineIndex, 2);
    expect(session.loading, isFalse);
    expect(session.jumpLoadingTitle, isNull);
  });
}
