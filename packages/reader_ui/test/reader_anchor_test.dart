import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

/// 可重排 + 可改尺寸的假章节源：8 个带 CFI 的段落，页面高度较小，
/// 使翻页后经常从块中间开始（覆盖行级锚点）。
class _AnchoredSource
    implements RestylableChapterSource, ResizableChapterSource {
  _AnchoredSource({this.overrideGate});

  final Completer<void>? overrideGate;
  double fontSize = 16;
  double width = 120;
  double height = 200;
  int loadCount = 0;
  Completer<void>? loadGate;
  final loadedHeights = <double>[];
  bool failNextLoad = false;

  @override
  int get chapterCount => 1;

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    final gate = overrideGate;
    if (gate != null) {
      await gate.future;
    }
    final size = overrides.fontSize;
    if (size != null) {
      fontSize = size;
    }
  }

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
  }) async {
    if (this.width == width && this.height == height) {
      return false;
    }
    this.width = width;
    this.height = height;
    return true;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loadCount += 1;
    loadedHeights.add(height);
    await loadGate?.future;
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('测试分页失败');
    }
    final style = ComputedStyle(<String, String>{
      'font-size': '${fontSize}px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final blocks = <PageBlock>[];
    for (var i = 0; i < 8; i++) {
      final layout = TextLayoutEngine.layout(
        text: 'para$i ${'word ' * 20}',
        style: style,
        maxWidth: width,
      );
      blocks.add(
        PageBlock.styled(
          layout: layout,
          style: style,
          containingWidth: width,
          startCfi: 'epubcfi(/6/2!/4/${i * 2 + 2}/1:0)',
        ),
      );
    }
    return Paginator(pageHeight: height)
        .measureChapter(blocks: blocks, spineIndex: spineIndex)
        .pages;
  }
}

/// 取页的锚点：首行起点（优先本页起始的块）。
ReaderAnchor _anchorOf(PageContent page) {
  for (final slice in page.slices) {
    if (slice.startLine != 0) {
      continue;
    }
    final cfi = slice.block.startCfi;
    if (cfi != null) {
      return ReaderAnchor(
        cfi: cfi,
        charOffset: slice.block.layout.lines[slice.startLine].start,
      );
    }
  }
  for (final slice in page.slices) {
    final cfi = slice.block.startCfi;
    if (cfi != null) {
      return ReaderAnchor(
        cfi: cfi,
        charOffset: slice.block.layout.lines[slice.startLine].start,
      );
    }
  }
  return const ReaderAnchor();
}

/// 页内是否包含锚点（块 CFI + 近似行）。
bool _contains(PageContent page, ReaderAnchor anchor) {
  for (final slice in page.slices) {
    if (slice.block.startCfi != anchor.cfi) {
      continue;
    }
    final layout = slice.block.layout;
    for (var i = slice.startLine; i < slice.endLine; i++) {
      final line = layout.lines[i];
      if (anchor.charOffset >= line.start && anchor.charOffset <= line.end) {
        return true;
      }
    }
  }
  return false;
}

Future<ReaderSession> _openSession(_AnchoredSource source) async {
  final session = ReaderSession(
    source: source,
    store: MemoryReaderProgressStore(),
    bookId: 'book',
  );
  await session.open(contentWidth: source.width, contentHeight: source.height);
  return session;
}

void main() {
  test('翻到块中间后用行级锚点恢复（偏差 0 行）', () async {
    final source = _AnchoredSource();
    final session = await _openSession(source);

    var page = session.page!;
    for (var i = 0; i < 5 && page.slices.first.startLine == 0; i++) {
      await session.next();
      page = session.page!;
    }
    expect(
      page.slices.first.startLine,
      greaterThan(0),
      reason: '需要落在块中间的页才能覆盖行级锚点',
    );
    final anchor = _anchorOf(page);

    await session.applyOverrides(const ReaderOverrides(fontSize: 22));
    expect(session.error, isNull);
    expect(_contains(session.page!, anchor), isTrue, reason: '应恢复到原段落原近似行');
    session.dispose();
  });

  test('旋转/改尺寸后位置偏差 ≤1 页', () async {
    final source = _AnchoredSource();
    final session = await _openSession(source);
    await session.next();
    final pageBefore = session.page!;
    final anchor = _anchorOf(pageBefore);

    await session.applyContentSize(width: 100, height: 160);
    expect(session.error, isNull);
    final pageAfter = session.page!;
    expect(pageAfter.pageHeight, 160, reason: '应使用新尺寸重排');
    expect(_contains(pageAfter, anchor), isTrue, reason: '尺寸变化后仍在原段落近似行');
    session.dispose();
  });

  test('尺寸未变化不重排', () async {
    final source = _AnchoredSource();
    final session = await _openSession(source);
    final loads = source.loadCount;
    await session.applyContentSize(width: 120, height: 200);
    expect(source.loadCount, loads);
    session.dispose();
  });

  test('重排过程中保留旧页，不闪空白', () async {
    final gate = Completer<void>();
    final source = _AnchoredSource(overrideGate: gate);
    final session = await _openSession(source);
    final oldPage = session.page;
    expect(oldPage, isNotNull);

    final future = session.applyOverrides(const ReaderOverrides(fontSize: 24));
    expect(session.page, isNotNull, reason: '重排期间不应清空当前页');
    expect(identical(session.page, oldPage), isTrue);
    expect(session.loading, isTrue);

    gate.complete();
    await future;
    expect(session.page, isNotNull);
    expect(session.loading, isFalse);
    expect(session.error, isNull);
    session.dispose();
  });

  test('预览反复重排固定原锚点，取消恢复原页且不保存临时页码', () async {
    final source = _AnchoredSource();
    final session = await _openSession(source);
    addTearDown(session.dispose);
    await session.next();
    await session.next();
    await session.flushProgress();
    final before = session.progress;
    final anchor = _anchorOf(session.page!);
    for (final height in [120.0, 180.0, 140.0]) {
      await session.applyContentSize(width: 120, height: height, preview: true);
      expect(session.page!.pageHeight, height);
      expect(_contains(session.page!, anchor), isTrue);
      await session.flushProgress();
      expect(await session.store.load('book'), before);
    }
    await session.applyContentSize(width: 120, height: 200);
    expect(session.progress, before);
    expect(session.page!.pageHeight, 200);
  });

  test('保存已完成的预览不重复分页，退出未保存预览仍保留原进度', () async {
    final source = _AnchoredSource();
    final session = await _openSession(source);
    await session.next();
    await session.applyContentSize(width: 120, height: 120, preview: true);
    final loads = source.loadCount;
    final previewProgress = session.progress;
    await session.applyContentSize(width: 120, height: 120);
    expect(source.loadCount, loads);
    await session.flushProgress();
    expect(await session.store.load('book'), previewProgress);
    await session.applyContentSize(width: 120, height: 80, preview: true);
    session.dispose();
    expect(await session.store.load('book'), previewProgress);
  });

  test('慢分页期间合并中间请求，取消恢复尺寸不会被旧预览覆盖', () async {
    final source = _AnchoredSource();
    final session = await _openSession(source);
    addTearDown(session.dispose);
    await session.applyContentSize(width: 120, height: 200);
    await session.next();
    final before = session.progress;
    source.loadedHeights.clear();
    source.loadGate = Completer<void>();
    final first = session.applyContentSize(
      width: 120,
      height: 180,
      preview: true,
    );
    await Future<void>.delayed(Duration.zero);
    final middle = session.applyContentSize(
      width: 120,
      height: 160,
      preview: true,
    );
    final cancel = session.applyContentSize(width: 120, height: 200);
    expect(source.height, 180, reason: '在途分页完成前不改变共享章节源尺寸');
    source.loadGate!.complete();
    await Future.wait([first, middle, cancel]);
    expect(source.loadedHeights, [180, 200]);
    expect(session.page!.pageHeight, 200);
    expect(session.contentHeight, 200);
    expect(session.progress, before);
  });

  test('预览分页失败后取消，章节源尺寸和当前页都恢复', () async {
    final source = _AnchoredSource();
    final session = await _openSession(source);
    addTearDown(session.dispose);
    await session.next();
    final before = session.progress;
    source.failNextLoad = true;
    await session.applyContentSize(width: 120, height: 120, preview: true);
    expect(session.error, isA<StateError>());
    expect(session.page!.pageHeight, 200, reason: '失败期间保留旧页');
    await session.applyContentSize(width: 120, height: 200);
    expect(session.error, isNull);
    expect(source.height, 200);
    expect(session.page!.pageHeight, 200);
    expect(session.progress, before);
  });

  test('预览尚未完成就保存，等待同次分页完成后提交最终进度', () async {
    final source = _AnchoredSource();
    final session = await _openSession(source);
    addTearDown(session.dispose);
    await session.next();
    source.loadedHeights.clear();
    source.loadGate = Completer<void>();
    final preview = session.applyContentSize(
      width: 120,
      height: 120,
      preview: true,
    );
    await Future<void>.delayed(Duration.zero);
    final save = session.applyContentSize(width: 120, height: 120);
    source.loadGate!.complete();
    await Future.wait([preview, save]);
    expect(source.loadedHeights, [120]);
    expect(session.page!.pageHeight, 120);
    await session.flushProgress();
    expect(await session.store.load('book'), session.progress);
  });
}
