import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

/// 每段独占一块、带唯一 CFI 的可重排测试源。
///
/// 段落短到任何字号下都只占一行，因此页码变化只能来自每页可容纳的段落数，
/// 便于把“正文位置是否漂移”与“页号变化”分开断言。
class _ParagraphSource
    implements
        RestylableChapterSource,
        ResizableChapterSource,
        LayoutDependencyChapterSource {
  _ParagraphSource({this.paragraphs = 100, this.pageHeight = 300});

  @override
  int get chapterCount => 1;
  final int paragraphs;
  double pageHeight;
  double contentWidth = 280;
  double fontSize = 16;
  double lineHeight = 1.5;
  double paragraphSpacing = 0;
  double padding = 0;
  String fontFamily = 'Ahem';

  @override
  String get layoutDependency =>
      'test-font=$fontFamily;lh=$lineHeight;ps=$paragraphSpacing;pad=$padding';

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    fontSize = overrides.fontSize ?? fontSize;
    lineHeight = overrides.lineHeight ?? lineHeight;
    paragraphSpacing = overrides.paragraphSpacing ?? paragraphSpacing;
    padding = overrides.padding?.top ?? padding;
    fontFamily = overrides.fontFamily ?? fontFamily;
  }

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
    ContentSideInsets? sideInsets,
  }) async {
    final changed = contentWidth != width || pageHeight != height;
    contentWidth = width;
    pageHeight = height;
    return changed;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = ComputedStyle(<String, String>{
      'font-size': '${fontSize}px',
      'line-height': '$lineHeight',
      'font-family': fontFamily,
      'margin-top': '${paragraphSpacing / 2}px',
      'margin-bottom': '${paragraphSpacing / 2}px',
      'padding-top': '${padding}px',
      'padding-bottom': '${padding}px',
    });
    final blocks = <PageBlock>[
      for (var index = 0; index < paragraphs; index++)
        PageBlock.styled(
          layout: TextLayoutEngine.layout(
            text: '第$spineIndex章段落${index.toString().padLeft(3, '0')}',
            style: style,
            maxWidth: contentWidth,
          ),
          style: style,
          containingWidth: contentWidth,
          startCfi: _cfiAt(spineIndex, index),
        ),
    ];
    return Paginator(pageHeight: pageHeight)
        .measureChapter(blocks: blocks, spineIndex: spineIndex)
        .pages;
  }

  static String _cfiAt(int spineIndex, int paragraph) =>
      'epubcfi(/6/${(spineIndex + 1) * 2}!/4/${(paragraph + 1) * 2}/1)';
}

class _CountingStore extends MemoryReaderProgressStore {
  int writes = 0;
  int failures = 0;

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    writes += 1;
    if (failures > 0) {
      failures -= 1;
      throw StateError('模拟写盘失败');
    }
    await super.save(bookId, progress);
  }
}

class _SlowStore extends MemoryReaderProgressStore {
  Completer<void>? gate;
  ReaderProgressSaveResult? rejection;
  int writes = 0;

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    writes += 1;
    final pending = gate;
    final result = rejection;
    if (pending != null) await pending.future;
    if (result != null) throw ReaderProgressSaveException(result);
    await super.save(bookId, progress);
  }
}

Future<ReaderSession> _openSession(
  _ParagraphSource source, {
  String? bookId,
  ReaderProgressStore? store,
}) async {
  final session = ReaderSession(
    source: source,
    store: store ?? MemoryReaderProgressStore(),
    bookId: bookId ?? 'reading-progress-regression',
    contentRevision: 'r1',
  );
  await session.open(
    contentWidth: source.contentWidth,
    contentHeight: source.pageHeight,
  );
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final result in [
    ReaderProgressSaveResult.stale,
    ReaderProgressSaveResult.bookMissing,
  ]) {
    test('延迟保存被 $result 拒绝后保留原位置，成功重试才清除错误', () async {
      const bookId = 'rejected-progress';
      final store = _SlowStore();
      final session = await _openSession(
        _ParagraphSource(pageHeight: 120),
        store: store,
        bookId: bookId,
      );
      addTearDown(session.dispose);
      await session.next();
      await session.flushProgress();
      final saved = await store.load(bookId);
      final writes = store.writes;
      final persisted = session.persistWriteCount;
      final errors = <Object?>[];
      session.addListener(() => errors.add(session.progressSaveError));
      store.gate = Completer<void>();
      store.rejection = result;
      await session.next();
      final pending = expectLater(
        session.flushProgress(),
        throwsA(
          isA<ReaderProgressSaveException>().having(
            (error) => error.result,
            '保存结果',
            result,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.progressSaveError, isNull);
      store.gate!.complete();
      await pending;

      expect(session.progressSaveError, isA<ReaderProgressSaveException>());
      expect(errors.last, same(session.progressSaveError));
      expect(await store.load(bookId), saved);
      expect(session.persistWriteCount, persisted);
      store.gate = null;
      store.rejection = null;
      await session.flushProgress();
      expect(store.writes, writes + 2, reason: '失败位置仍待保存，重试必须再次写入');
      expect(await store.load(bookId), session.progress);
      expect(session.persistWriteCount, persisted + 1);
      expect(session.progressSaveError, isNull);
      expect(errors.last, isNull);
    });
  }

  test('分页下反复调整字号/字体/行高/段距/边距/尺寸不漂移原始 CFI', () async {
    final source = _ParagraphSource();
    final store = MemoryReaderProgressStore();
    final session = await _openSession(source, store: store);
    addTearDown(session.dispose);
    await session.next();
    await session.next();
    final originalCfi = session.progress!.cfi;
    final originalLine = session.currentLineText;
    expect(originalCfi, isNotNull);

    final overrides = <ReaderOverrides>[
      const ReaderOverrides(fontSize: 20),
      const ReaderOverrides(fontSize: 16),
      const ReaderOverrides(fontFamily: 'serif'),
      const ReaderOverrides(fontFamily: 'Ahem'),
      const ReaderOverrides(lineHeight: 1.9),
      const ReaderOverrides(lineHeight: 1.5),
      const ReaderOverrides(paragraphSpacing: 8),
      const ReaderOverrides(paragraphSpacing: 0),
      ReaderOverrides(
        padding: const CssEdges(top: 6, right: 6, bottom: 6, left: 6),
      ),
      const ReaderOverrides(),
    ];
    for (final item in overrides) {
      await session.applyOverrides(item);
      expect(session.progress!.cfi, originalCfi, reason: '设置变化后 CFI 不得前移');
      expect(session.currentText, contains(originalLine));
    }
    await session.applyContentSize(width: 250, height: 280);
    expect(session.progress!.cfi, originalCfi);
    expect(session.currentText, contains(originalLine));
    await session.applyContentSize(width: 280, height: 300);
    expect(session.progress!.cfi, originalCfi);
    expect(session.currentText, contains(originalLine));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await session.flushProgress();
    expect((await store.load('reading-progress-regression'))?.cfi, originalCfi);
  });

  test('连续滚动重排保持当前行并保留页内偏移', () async {
    final source = _ParagraphSource();
    final session = await _openSession(source);
    addTearDown(session.dispose);
    await session.commitScrollPosition(0, 2, 0);
    final originalLine = session.currentLineText;
    expect(originalLine, isNotEmpty);
    for (final size in <double>[20, 16, 20]) {
      await session.applyOverrides(ReaderOverrides(fontSize: size));
      expect(session.currentLineText, originalLine);
      expect(session.progress!.scrollOffset, isNotNull);
    }
    await session.applyContentSize(width: 250, height: 280);
    expect(session.currentLineText, originalLine);
    expect(session.progress!.scrollOffset, isNotNull);
  });

  test('同排版冷开复用 37.25px 的精确滚动偏移', () async {
    final source = _ParagraphSource();
    final store = MemoryReaderProgressStore();
    final first = ReaderSession(
      source: source,
      store: store,
      bookId: 'offset-precision',
      contentRevision: 'r1',
    );
    await first.open(contentWidth: 280, contentHeight: 300);
    await first.commitScrollPosition(0, 2, 37.25);
    await first.flushProgress();
    final saved = first.progress!;
    expect(saved.scrollOffset, 37.25);
    first.dispose();

    final reopened = ReaderSession(
      source: _ParagraphSource(),
      store: store,
      bookId: 'offset-precision',
      contentRevision: 'r1',
    );
    addTearDown(reopened.dispose);
    await reopened.open(contentWidth: 280, contentHeight: 300);
    expect(reopened.currentCfi, saved.cfi);
    expect(reopened.progress!.scrollOffset, closeTo(37.25, 1e-9));
  });

  test('滚动进入书尾留白时锚点取正文末端，不回退块首', () async {
    final source = _ParagraphSource(paragraphs: 20, pageHeight: 120);
    final session = await _openSession(source);
    addTearDown(session.dispose);
    final pages = await source.loadChapter(0);
    final page = pages.last;
    final lastSlice = page.slices.last;
    final cfi = session.cfiAtPageOffset(page, page.usedHeight + 30);
    final expected =
        '${lastSlice.block.startCfi!.replaceFirst(')', '')}'
        ':${lastSlice.block.layout.text.length})';
    expect(cfi, expected);
    await session.commitScrollPosition(0, page.pageIndex, page.usedHeight + 30);
    expect(session.progress!.cfi, expected);
    expect(session.progress!.finished, isTrue);
  });

  test('持续阅读按固定间隔落盘，失败后保留待保存状态并重试', () async {
    final store = _CountingStore();
    final session = ReaderSession(
      source: _ParagraphSource(paragraphs: 80, pageHeight: 120),
      store: store,
      bookId: 'persist-window',
      contentRevision: 'r1',
      persistInterval: const Duration(milliseconds: 100),
    );
    addTearDown(session.dispose);
    await session.open(contentWidth: 280, contentHeight: 120);
    for (var i = 0; i < 8; i++) {
      await session.next();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    await Future<void>.delayed(const Duration(milliseconds: 130));
    final latest = session.progress!;
    expect(store.writes, greaterThan(1), reason: '不能只靠不断延期的防抖');
    expect((await store.load('persist-window'))?.pageIndex, latest.pageIndex);

    store.failures = 1;
    await session.next();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    await session.flushProgress();
    expect(store.writes, greaterThan(2));
    expect(
      (await store.load('persist-window'))?.pageIndex,
      session.progress!.pageIndex,
    );
  });

  test('慢写期间 flush 等待完成并写入最新位置', () async {
    final store = _SlowStore();
    final session = ReaderSession(
      source: _ParagraphSource(paragraphs: 80, pageHeight: 120),
      store: store,
      bookId: 'slow-write',
      contentRevision: 'r1',
      persistInterval: const Duration(milliseconds: 80),
    );
    addTearDown(session.dispose);
    await session.open(contentWidth: 280, contentHeight: 120);
    final gate = Completer<void>();
    store.gate = gate;
    await session.next();
    final pending = session.flushProgress();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await session.next();
    await session.next();
    final latest = session.progress!;
    expect(store.writes, greaterThan(0));
    expect((await store.load('slow-write'))?.pageIndex, isNull);
    gate.complete();
    await pending;
    expect((await store.load('slow-write'))?.pageIndex, latest.pageIndex);
    expect(store.writes, 2, reason: '第一次写盘完成后补写期间产生的新位置');
  });

  test('本次阅读到书尾后回翻保留读完状态和当前正文位置', () async {
    final store = MemoryReaderProgressStore();
    final session = await _openSession(
      _ParagraphSource(paragraphs: 20, pageHeight: 120),
      store: store,
    );
    addTearDown(session.dispose);
    while (await session.next()) {}
    expect(session.progress!.finished, isTrue);
    final lastCfi = session.progress!.cfi;
    await session.previous();
    expect(session.progress!.finished, isTrue);
    expect(session.progress!.cfi, isNot(lastCfi));
    await session.flushProgress();
    final saved = await store.load('reading-progress-regression');
    expect(saved!.finished, isTrue);
    expect(saved.cfi, session.progress!.cfi);
  });

  testWidgets('可控时钟下持续阅读不推迟保存截止时间', (tester) async {
    final store = _CountingStore();
    final session = ReaderSession(
      source: _ParagraphSource(paragraphs: 100, pageHeight: 120),
      store: store,
      bookId: 'fixed-deadline',
      contentRevision: 'r1',
      persistInterval: const Duration(seconds: 2),
    );
    await session.open(contentWidth: 280, contentHeight: 120);
    await session.next();
    await tester.pump();
    expect(store.writes, 1, reason: '首次真实变化立即写入');
    for (var i = 0; i < 12; i++) {
      await session.next();
      await tester.pump(const Duration(milliseconds: 500));
      expect(store.writes, 1 + (i + 1) ~/ 4);
    }
    expect((await store.load('fixed-deadline'))!.cfi, session.progress!.cfi);
    await session.flushProgress();
    session.dispose();
  });

  testWidgets('慢写跨过周期后立即串行补写新位置', (tester) async {
    final store = _SlowStore();
    final session = ReaderSession(
      source: _ParagraphSource(paragraphs: 80, pageHeight: 120),
      store: store,
      bookId: 'slow-deadline',
      contentRevision: 'r1',
      persistInterval: const Duration(seconds: 2),
    );
    await session.open(contentWidth: 280, contentHeight: 120);
    final gate = Completer<void>();
    store.gate = gate;
    await session.next();
    await tester.pump();
    await session.next();
    await tester.pump(const Duration(seconds: 3));
    expect(store.writes, 1, reason: '写入串行，不能并发落盘');
    store.gate = null;
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(store.writes, 2, reason: '已经到期，不在 IO 完成后再等两秒');
    expect((await store.load('slow-deadline'))!.cfi, session.progress!.cfi);
    await session.flushProgress();
    session.dispose();
  });
}
