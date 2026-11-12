import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show TocEntry;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

String _cfi(int spine, [int offset = 0]) =>
    'epubcfi(/6/${(spine + 1) * 2}!/4/2/1:$offset)';

List<PageContent> _pages(
  int spine,
  double fontSize,
  double height, {
  int pageCount = 1,
}) {
  final style = ComputedStyle({
    'font-size': '${fontSize}px',
    'font-family': 'Ahem',
    'line-height': '1.5',
  });
  final layout = TextLayoutEngine.layout(
    text: 'abcdefghijklmnopqrstuvwx',
    style: style,
    maxWidth: 280,
  );
  return [
    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++)
      PageContent(
        spineIndex: spine,
        pageIndex: pageIndex,
        slices: [
          PageBlockSlice(
            block: PageBlock(
              layout: layout,
              style: style,
              startCfi: _cfi(spine),
            ),
            startLine: 0,
            endLine: layout.lineCount,
            height: layout.height,
          ),
        ],
        usedHeight: layout.height,
        pageHeight: height,
        topPadding: 0,
      ),
  ];
}

class _Handle implements ChapterLoadHandle {
  _Handle(this.spine, this.font, this.height, this.priority);

  final int spine;
  final double font;
  final double height;
  final ChapterLayoutPriority priority;
  final _result = Completer<List<PageContent>>();
  bool cancelled = false;

  @override
  Future<List<PageContent>> get result => _result.future;

  void complete({int pageCount = 1}) {
    if (!_result.isCompleted) {
      _result.complete(_pages(spine, font, height, pageCount: pageCount));
    }
  }

  @override
  void cancel() {
    cancelled = true;
    if (!_result.isCompleted) {
      _result.completeError(const ChapterLoadCancelled());
    }
  }
}

class _ScheduledSource
    implements
        ScheduledChapterSource,
        RestylableChapterSource,
        ResizableChapterSource,
        AsyncPositionedChapterSource {
  final handles = <_Handle>[];
  double font = 16;
  double height = 200;
  bool hold = false;
  final percentRequests = <double>[];
  Completer<String?>? percentGate;

  @override
  int get chapterCount => 1000;

  @override
  ChapterLoadHandle scheduleChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    bool retainResult = true,
  }) {
    final handle = _Handle(spineIndex, font, height, priority);
    handles.add(handle);
    if (!hold) scheduleMicrotask(handle.complete);
    return handle;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) =>
      throw StateError('会话应使用可取消任务接口');

  @override
  void cancelPendingLayouts() {
    for (final handle in handles) {
      handle.cancel();
    }
  }

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    font = overrides.fontSize ?? 16;
  }

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
    ContentSideInsets? sideInsets,
  }) async {
    final changed = this.height != height;
    this.height = height;
    return changed;
  }

  @override
  double? readingPercentForCfi(String? cfi) =>
      cfi == null ? null : (cfiCharOffset(cfi) ?? 0) / 100;

  @override
  String? cfiForReadingPercent(double percent) =>
      throw StateError('百分比跳转应异步准备目标章');

  @override
  Future<String?> prepareCfiForReadingPercent(double percent) async {
    percentRequests.add(percent);
    return percentGate?.future ?? Future.value(_cfi((percent * 999).round()));
  }

  @override
  String? cfiForTocEntry(TocEntry entry) => _cfi(entry.spineIndex);
}

class _Preparation<T> implements ReaderPreparationHandle<T> {
  _Preparation() {
    result.ignore();
  }
  final completion = Completer<T>();
  bool cancelled = false;
  @override
  Future<T> get result => completion.future;
  @override
  void cancel() {
    if (completion.isCompleted) return;
    cancelled = true;
    completion.completeError(const ChapterLoadCancelled());
  }
}

class _ScheduledPositionSource extends _AnchorTocSource
    implements ScheduledAnchorChapterSource, ScheduledPositionedChapterSource {
  final anchors = <int, _Preparation<AnchorChapter>>{};
  final percents = <double, _Preparation<String?>>{};

  @override
  ReaderPreparationHandle<AnchorChapter> scheduleAnchorChapter(
    int spineIndex,
  ) => anchors[spineIndex] = _Preparation<AnchorChapter>();

  @override
  ReaderPreparationHandle<String?> scheduleCfiForReadingPercent(
    double percent,
  ) => percents[percent] = _Preparation<String?>();
}

class _AnchorTocSource extends _ScheduledSource implements AnchorChapterSource {
  final anchorRequests = <int>[];
  final anchorGates = <int, Completer<void>>{};
  final preparedSpines = <int>{};
  final resolvedEntries = <int>[];

  @override
  Future<AnchorChapter> loadAnchorChapter(int spineIndex) async {
    anchorRequests.add(spineIndex);
    await anchorGates[spineIndex]?.future;
    preparedSpines.add(spineIndex);
    return AnchorChapter(
      spineIndex: spineIndex,
      href: '$spineIndex.xhtml',
      blocks: [
        AnchorBlock(cfi: _cfi(spineIndex), text: 'abcdefghijklmnopqrstuvwx'),
      ],
    );
  }

  @override
  String? cfiForTocEntry(TocEntry entry) {
    expect(
      preparedSpines,
      contains(entry.spineIndex),
      reason: '同步目录定位只读取已准备原文',
    );
    resolvedEntries.add(entry.spineIndex);
    return _cfi(entry.spineIndex, 6);
  }
}

Future<ReaderSession> _open(
  _ScheduledSource source, {
  ReaderProgress? saved,
}) async {
  final store = MemoryReaderProgressStore();
  if (saved != null) await store.save('scheduled', saved);
  final session = ReaderSession(
    source: source,
    store: store,
    bookId: 'scheduled',
    contentRevision: 'r1',
  );
  await session.open();
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('恢复先使用 CFI 目标章，过期页号不会多排另一章', () async {
    final source = _ScheduledSource();
    final session = await _open(
      source,
      saved: ReaderProgress(
        spineIndex: 0,
        pageIndex: 9,
        cfi: _cfi(750, 8),
        contentRevision: 'r1',
      ),
    );
    addTearDown(session.dispose);
    expect(source.handles.map((handle) => handle.spine), [750]);
    expect(session.progress?.spineIndex, 750);
    expect(session.progress?.cfi, _cfi(750, 8));
    expect(session.readingPercent, 0.08);
  });

  test('新字号立即取消旧等待者，旧正文与进度保持到最新结果提交', () async {
    final source = _ScheduledSource();
    final session = await _open(
      source,
      saved: ReaderProgress(
        spineIndex: 0,
        pageIndex: 0,
        cfi: _cfi(0, 8),
        contentRevision: 'r1',
      ),
    );
    addTearDown(session.dispose);
    final original = session.page;
    final visibleStates = <(double, int, double?)>[];
    session.addListener(() {
      visibleStates.add((
        session.page!.slices.first.block.style!.fontSize,
        session.chapterPageCount,
        session.readingPercent,
      ));
    });
    source.hold = true;
    final first = session.applyOverrides(const ReaderOverrides(fontSize: 20));
    await Future<void>.delayed(Duration.zero);
    final old = source.handles.last;
    final latest = session.applyOverrides(const ReaderOverrides(fontSize: 30));
    await Future<void>.delayed(Duration.zero);
    expect(old.cancelled, isTrue);
    expect(source.handles.last.font, 30);
    expect(session.page, same(original));
    expect(session.readingPercent, 0.08);
    expect(session.chapterPageCount, 1);
    source.handles.last.complete(pageCount: 3);
    await Future.wait([first, latest]);
    expect(session.error, isNull);
    expect(session.loading, isFalse);
    expect(session.page!.slices.first.block.style!.fontSize, 30);
    expect(session.chapterPageCount, 3);
    expect(session.progress?.cfi, _cfi(0, 8));
    expect(session.readingPercent, 0.08);
    old.complete();
    expect(session.page!.slices.first.block.style!.fontSize, 30);
    expect(
      visibleStates,
      everyElement(anyOf((16.0, 1, 0.08), (30.0, 3, 0.08))),
      reason: '旧正文和旧页码必须保留到新正文、页码与百分比同次提交',
    );
  });

  test('旋转立即停止过期尺寸，最后尺寸无需等待旧章节算完', () async {
    final source = _ScheduledSource();
    final session = await _open(source);
    addTearDown(session.dispose);
    source.hold = true;
    final first = session.applyContentSize(width: 300, height: 300);
    await Future<void>.delayed(Duration.zero);
    final old = source.handles.last;
    final last = session.applyContentSize(width: 400, height: 400);
    await Future<void>.delayed(Duration.zero);
    expect(old.cancelled, isTrue);
    expect(source.handles.last.height, 400);
    source.handles.last.complete();
    await Future.wait([first, last]);
    expect(session.page!.pageHeight, 400);
    expect(session.error, isNull);
  });

  test('邻章预取优先级独立于当前阅读', () async {
    final source = _ScheduledSource();
    final session = await _open(source);
    addTearDown(session.dispose);
    final turn = await session.preparePageTurn(true, prefetch: true);
    expect(turn, isNotNull);
    expect(source.handles.first.priority, ChapterLayoutPriority.reading);
    expect(source.handles.last.priority, ChapterLayoutPriority.prefetch);
    expect(session.progress?.spineIndex, 0);
  });

  test('翻页接管同章预取并取消另一方向预取，旧结果不覆盖前台页', () async {
    final source = _ScheduledSource();
    final session = await _open(
      source,
      saved: const ReaderProgress(
        spineIndex: 5,
        pageIndex: 0,
        contentRevision: 'r1',
      ),
    );
    addTearDown(session.dispose);
    source.hold = true;
    final forward = session.prefetchTurnChapter(true);
    final backward = session.prefetchTurnChapter(false);
    final forwardHandle = source.handles[source.handles.length - 2];
    final backwardHandle = source.handles.last;
    final reading = session.preparePageTurn(true);
    final readingHandle = source.handles.last;
    expect(readingHandle.priority, ChapterLayoutPriority.reading);
    expect(readingHandle.spine, 6);
    expect(forwardHandle.cancelled, isFalse);
    expect(backwardHandle.cancelled, isTrue);
    forwardHandle.complete(pageCount: 1);
    await Future<void>.delayed(Duration.zero);
    readingHandle.complete(pageCount: 3);
    final turn = await reading;
    expect(turn, isNotNull);
    expect(await backward, isNull);
    expect(await forward, same(turn!.target.content));
    expect(session.commitPageTurn(turn), isTrue);
    expect(session.chapterPageCount, 3, reason: '前台发布结果应取代旧预取结果');
    await session.flushProgress();
  });

  test('取消预取后同一轮立即重新请求不会复用已取消的等待者', () async {
    final source = _ScheduledSource();
    final session = await _open(source);
    addTearDown(session.dispose);
    source.hold = true;
    final old = session.prefetchTurnChapter(true);
    final cancelled = source.handles.last;
    session.cancelTurnPrefetch();
    final next = session.prefetchTurnChapter(true);
    final replacement = source.handles.last;
    expect(cancelled.cancelled, isTrue);
    expect(replacement, isNot(same(cancelled)));
    replacement.complete();
    expect(await old, isNull);
    expect((await next)!.spineIndex, 1);
    expect(session.progress?.spineIndex, 0);
  });

  test('旋转与字号交错时保留最终尺寸输入，不提交过期字号版面', () async {
    final source = _ScheduledSource();
    final session = await _open(source);
    addTearDown(session.dispose);
    source.hold = true;
    final rotation = session.applyContentSize(width: 400, height: 400);
    final resizing = session.applyOverrides(
      const ReaderOverrides(fontSize: 30),
    );
    await Future<void>.delayed(Duration.zero);
    final finalLayout = source.handles.last;
    expect((finalLayout.font, finalLayout.height), (30, 400));
    finalLayout.complete();
    await Future.wait([rotation, resizing]);
    expect(session.contentHeight, 400);
    expect(session.page!.pageHeight, 400);
    expect(session.page!.slices.first.block.style!.fontSize, 30);
    expect(session.layoutFingerprint, contains('h=400.0'));
  });

  test('百分比异步准备后只允许最新跳转提交', () async {
    final source = _ScheduledSource();
    final session = await _open(source);
    addTearDown(session.dispose);
    final gate = Completer<String?>();
    source.percentGate = gate;
    final old = session.seekToReadingPercent(0.25);
    source.percentGate = null;
    expect(await session.seekToReadingPercent(0.75), isTrue);
    gate.complete(_cfi(250));
    expect(await old, isFalse);
    expect(session.progress?.spineIndex, 749);
    expect(source.percentRequests, [0.25, 0.75]);
  });

  test('新百分比跳转取消旧目录原文等待者，关闭取消新等待者', () async {
    final source = _ScheduledPositionSource();
    final session = await _open(source);
    final old = session.jumpToTocEntry(
      const TocEntry(title: '旧目录', spineIndex: 950),
    );
    final next = session.seekToReadingPercent(0.75);
    expect(source.anchors[950]!.cancelled, isTrue);
    expect(await old, isFalse);
    session.dispose();
    expect(source.percents[0.75]!.cancelled, isTrue);
    expect(await next, isFalse);
    expect(source.resolvedEntries, isEmpty);
    expect(source.handles.map((handle) => handle.spine), [0]);
  });

  test('位置准备成功提交后不再被后续导航取消', () async {
    final source = _ScheduledPositionSource();
    final session = await _open(source);
    addTearDown(session.dispose);
    final pending = session.seekToReadingPercent(0.75);
    final handle = source.percents[0.75]!;
    handle.completion.complete(_cfi(749));
    expect(await pending, isTrue);
    expect(handle.cancelled, isFalse);
    expect(session.progress?.spineIndex, 749);
  });

  test('目录项先异步准备目标章原文，再解析 fragment 并只排目标章', () async {
    final source = _AnchorTocSource();
    final session = await _open(source);
    addTearDown(session.dispose);
    final gate = source.anchorGates[950] = Completer<void>();
    final pending = session.jumpToTocEntry(
      const TocEntry(title: '第九百五十一章', spineIndex: 950, fragment: 'target'),
    );
    expect(source.anchorRequests, [950]);
    expect(source.resolvedEntries, isEmpty);
    expect(source.handles.map((handle) => handle.spine), [0]);
    expect(session.jumpLoadingTitle, '第九百五十一章');
    gate.complete();
    expect(await pending, isTrue);
    expect(source.resolvedEntries, [950]);
    expect(source.handles.map((handle) => handle.spine), [0, 950]);
    expect(session.progress?.cfi, _cfi(950, 6));
    expect(session.jumpLoadingTitle, isNull);
  });

  test('目录原文准备交错时只允许最新跳转读取 CFI 和提交分页', () async {
    final source = _AnchorTocSource();
    final session = await _open(source);
    addTearDown(session.dispose);
    final gate = source.anchorGates[950] = Completer<void>();
    final old = session.jumpToTocEntry(
      const TocEntry(title: '旧目录', spineIndex: 950),
    );
    expect(
      await session.jumpToTocEntry(
        const TocEntry(title: '新目录', spineIndex: 25),
      ),
      isTrue,
    );
    gate.complete();
    expect(await old, isFalse);
    expect(source.resolvedEntries, [25]);
    expect(source.handles.map((handle) => handle.spine), [0, 25]);
    expect(session.progress?.cfi, _cfi(25, 6));
    expect(session.jumpLoadingTitle, isNull);
  });

  test('目录原文准备期间关闭后不读取 CFI 或提交章节', () async {
    final source = _AnchorTocSource();
    final session = await _open(source);
    final gate = source.anchorGates[950] = Completer<void>();
    final pending = session.jumpToTocEntry(
      const TocEntry(title: '退出目录', spineIndex: 950),
    );
    session.dispose();
    gate.complete();
    expect(await pending, isFalse);
    expect(source.resolvedEntries, isEmpty);
    expect(source.handles.map((handle) => handle.spine), [0]);
  });

  test('目录原文准备取消时保留当前位置并清除跳转浮层', () async {
    final source = _AnchorTocSource();
    final session = await _open(source);
    addTearDown(session.dispose);
    final gate = source.anchorGates[950] = Completer<void>();
    final pending = session.jumpToTocEntry(
      const TocEntry(title: '取消目录', spineIndex: 950),
    );
    gate.completeError(const ChapterLoadCancelled());
    expect(await pending, isFalse);
    expect(session.progress?.spineIndex, 0);
    expect(source.resolvedEntries, isEmpty);
    expect(session.jumpLoadingTitle, isNull);
  });

  test('关闭取消当前等待者，旧任务不能通知或替换正文', () async {
    final source = _ScheduledSource();
    final session = await _open(source);
    source.hold = true;
    final pending = session.applyOverrides(const ReaderOverrides(fontSize: 25));
    await Future<void>.delayed(Duration.zero);
    final handle = source.handles.last;
    session.dispose();
    expect(handle.cancelled, isTrue);
    await pending;
    handle.complete();
  });
}
