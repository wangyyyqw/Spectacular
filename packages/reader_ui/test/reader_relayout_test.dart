import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

const _pageHeight = 200.0;
const _contentWidth = 200.0;

/// 可按设置重排的假章节源：12 个带 CFI 的段落，字号变化改变行高与页数。
class _FakeRestylableSource implements RestylableChapterSource {
  _FakeRestylableSource();

  double fontSize = 16;
  int loadCount = 0;
  Completer<void>? gate;

  @override
  int get chapterCount => 1;

  @override
  Future<void> applyOverrides(ReaderOverrides overrides) async {
    final size = overrides.fontSize;
    if (size != null) {
      fontSize = size;
    }
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loadCount += 1;
    final sizeAtLoad = fontSize;
    await gate?.future;
    final style = ComputedStyle(<String, String>{
      'font-size': '${sizeAtLoad}px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final blocks = <PageBlock>[];
    for (var i = 0; i < 12; i++) {
      final text = 'para$i ${'word ' * 12}';
      final layout = TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: _contentWidth,
      );
      blocks.add(
        PageBlock.styled(
          layout: layout,
          style: style,
          containingWidth: _contentWidth,
          startCfi: 'epubcfi(/6/2!/4/${i * 2 + 2}/1:0)',
        ),
      );
    }
    return Paginator(pageHeight: _pageHeight)
        .measureChapter(blocks: blocks, spineIndex: spineIndex)
        .pages;
  }
}

String? _firstCfi(PageContent? page) {
  if (page == null) {
    return null;
  }
  // 与 ReaderSession 一致：优先取在本页起始的块，纯续页再退化。
  for (final slice in page.slices) {
    if (slice.startLine != 0) {
      continue;
    }
    final cfi = slice.block.startCfi;
    if (cfi != null) {
      return cfi;
    }
  }
  for (final slice in page.slices) {
    final cfi = slice.block.startCfi;
    if (cfi != null) {
      return cfi;
    }
  }
  return null;
}

bool _pageContainsCfi(PageContent? page, String? cfi) {
  if (page == null || cfi == null) {
    return false;
  }
  return page.slices.any((slice) => slice.block.startCfi == cfi);
}

void main() {
  test('字号变化触发布局指纹变化并重排', () async {
    final source = _FakeRestylableSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'book',
    );
    await session.open();
    final pagesBefore = source.loadCount;
    expect(session.page, isNotNull);

    await session.applyOverrides(const ReaderOverrides(fontSize: 24));
    expect(source.loadCount, greaterThan(pagesBefore), reason: '设置变化触发重新加载');
    expect(
      session.layoutFingerprint,
      contains(const ReaderOverrides(fontSize: 24).fingerprint),
    );
    expect(session.error, isNull);
    session.dispose();
  });

  test('改字号后按 CFI 恢复位置，内容不漂移', () async {
    final source = _FakeRestylableSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'book',
    );
    await session.open();
    // 翻到第 2 页，记录该页起始 CFI。
    await session.next();
    final targetCfi = _firstCfi(session.page);
    expect(targetCfi, isNotNull);

    await session.applyOverrides(const ReaderOverrides(fontSize: 26));
    expect(session.error, isNull);
    expect(
      _pageContainsCfi(session.page, targetCfi),
      isTrue,
      reason: '重排后仍停在同一 CFI 所在页（误差 0 页）',
    );
    session.dispose();
  });

  test('连续快速改 5 次字号无错位、无崩溃', () async {
    final source = _FakeRestylableSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'book',
    );
    await session.open();
    await session.next();
    final targetCfi = _firstCfi(session.page);

    for (final size in [17.0, 19.0, 21.0, 23.0, 25.0]) {
      await session.applyOverrides(ReaderOverrides(fontSize: size));
      expect(session.error, isNull);
      expect(session.page, isNotNull);
      expect(
        _pageContainsCfi(session.page, targetCfi),
        isTrue,
        reason: '字号 $size 时位置漂移',
      );
    }
    session.dispose();
  });

  test('在途重排合并：连续设置只完成一次旧排版和一次最新排版', () async {
    final source = _FakeRestylableSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'coalesce',
    );
    await session.open();
    final initialLoads = source.loadCount;
    source.gate = Completer<void>();

    final first = session.applyOverrides(const ReaderOverrides(fontSize: 18));
    await Future<void>.delayed(Duration.zero);
    final second = session.applyOverrides(const ReaderOverrides(fontSize: 20));
    final third = session.applyOverrides(const ReaderOverrides(fontSize: 22));
    expect(source.loadCount, initialLoads + 1, reason: '最多一个旧排版在途');

    source.gate!.complete();
    await Future.wait(<Future<void>>[first, second, third]);

    expect(source.loadCount, initialLoads + 2, reason: '中间 20 号设置不再启动整章排版');
    expect(
      session.layoutFingerprint,
      contains(const ReaderOverrides(fontSize: 22).fingerprint),
    );
    expect(session.error, isNull);
    session.dispose();
  });

  test('相同设置重复应用不触发重排', () async {
    final source = _FakeRestylableSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'book',
    );
    await session.open();
    await session.applyOverrides(const ReaderOverrides(fontSize: 24));
    final loads = source.loadCount;
    await session.applyOverrides(const ReaderOverrides(fontSize: 24));
    expect(source.loadCount, loads, reason: '指纹未变不应重排');
    session.dispose();
  });

  test('不支持重排的来源只记录设置', () async {
    final session = ReaderSession(
      source: _PlainSource(),
      store: MemoryReaderProgressStore(),
      bookId: 'book',
    );
    await session.open();
    await session.applyOverrides(const ReaderOverrides(fontSize: 20));
    expect(session.overrides.fontSize, 20);
    expect(session.error, isNull);
    session.dispose();
  });
}

class _PlainSource implements ReaderChapterSource {
  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: 'hello',
      style: style,
      maxWidth: _contentWidth,
    );
    return [
      PageContent(
        spineIndex: spineIndex,
        pageIndex: 0,
        slices: [
          PageBlockSlice(
            block: PageBlock.styled(
              layout: layout,
              style: style,
              containingWidth: _contentWidth,
              startCfi: 'epubcfi(/6/2!/4/2/1:0)',
            ),
            startLine: 0,
            endLine: layout.lineCount,
            height: layout.height,
          ),
        ],
        usedHeight: layout.height,
        pageHeight: _pageHeight,
        topPadding: 0,
      ),
    ];
  }
}
