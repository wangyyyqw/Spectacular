import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_core/source/format_opener.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/annotation_layer.dart';
import 'package:reader_ui/annotations/decorations.dart';
import 'package:reader_ui/annotations/thought_marker.dart';
import 'package:reader_ui/decorations/decoration_geometry.dart';
import 'package:reader_ui/decorations/decoration_rule_engine.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/decoration_style.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/selection/selection.dart';
import 'package:reader_ui/selection/selection_support.dart';
import 'package:reader_ui/selection/text_range_geometry.dart';

import '../../reader_core/test/audit/audit_epub_fixture.dart';

String _cfi(String steps, int offset) => 'epubcfi(/6/2!/4$steps:$offset)';

Future<EpubChapterSource> _source(
  String body, {
  String css = '',
  double width = 80,
}) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
    'book.opf':
        '<package version="3.0" unique-identifier="id" '
        'xmlns="http://www.idpf.org/2007/opf"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">cfi-ui</dc:identifier><dc:title>字符块交互</dc:title>'
        '</metadata><manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="c"/></spine></package>',
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
        'body,p{margin:0;padding:0}p{word-break:break-all}$css'
        '</style></head><body>$body</body></html>',
  });
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: ReaderOpenOptions(
      contentWidth: width,
      contentHeight: 120,
      trimTextEdges: false,
      style: ComputedStyle(const {
        'font-family': 'Ahem',
        'font-size': '16px',
        'line-height': '1.5',
      }),
    ),
  );
  addTearDown(source.close);
  return source;
}

Future<ReaderSession> _session(
  EpubChapterSource source,
  MemoryReaderProgressStore store,
) async {
  final session = ReaderSession(
    source: source,
    store: store,
    bookId: 'cfi-interaction',
    contentRevision: 'cfi-text-3',
  );
  addTearDown(session.dispose);
  await session.open();
  return session;
}

TextHit _hit(PageLineBox line, int offset) => TextHit(
  lineBox: line,
  charOffset: offset,
  textOffset: line.textOffset + offset,
  atLineStart: offset == 0,
  atLineEnd: offset == line.text.length,
);

ReaderAnnotation _annotation(String start, String end) => ReaderAnnotation(
  id: 'source-thought',
  type: ReaderAnnotationType.thought,
  startCfi: start,
  endCfi: end,
  quote: 'ABtail',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

String _lineText(Iterable<ReaderRangeLine> lines) =>
    lines.map((line) => line.line.text.substring(line.start, line.end)).join();

/// 控件交接正式 EPUB 的页面与原文锚点，假时钟内不启动解析或资源 IO。
class _AnchorPagesSource implements AnchorChapterSource {
  _AnchorPagesSource(this.pages, this.chapter);
  final List<PageContent> pages;
  final AnchorChapter chapter;
  Future<AnchorChapter>? pendingAnchor;
  int anchorRequests = 0;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) =>
      SynchronousFuture(pages);

  @override
  Future<AnchorChapter> loadAnchorChapter(int spineIndex) {
    anchorRequests += 1;
    return pendingAnchor ?? SynchronousFuture(chapter);
  }
}

Future<_AnchorPagesSource> _prepareSearchSource(
  WidgetTester tester, {
  bool multipage = false,
}) async {
  return (await tester.runAsync(() async {
    final source = await _source(
      '<p id="p">lead<b id="b">A</b><i id="i">B</i>'
      '${'tail' * (multipage ? 11 : 1)}</p>',
      css: 'p{width:64px}',
    );
    return _AnchorPagesSource(
      await source.loadChapter(0),
      await source.loadAnchorChapter(0),
    );
  }))!;
}

Future<ReaderSession> _showSearchReader(
  WidgetTester tester,
  _AnchorPagesSource source,
) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          bookId: 'cfi-search',
          padding: const EdgeInsets.all(40),
          overrides: const ReaderOverrides(),
          showPageFooter: false,
          onSessionReady: (value) => session = value,
          onSearch: (_) async => [
            SearchPanelResult(
              spineIndex: 0,
              charOffset: 4,
              chapterTitle: '章节',
              context: 'ABtail',
              matchLength: 6,
              cfi: _cfi('/2[p]/2[b]/1', 0),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _clickSearchResult(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-entry-toc')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('drawer-tab-search')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('search-input')), 'ABtail');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ListTile));
  await tester.pumpAndSettle();
}

bool _hasSearchHighlight(WidgetTester tester) => tester
    .widgetList<AnnotationLayer>(find.byType(AnnotationLayer))
    .any((layer) => layer.annotations.any((item) => item.id == 'search-hit'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('正式 EPUB 翻页、页内滚动、CFI 跳转及重排恢复使用来源坐标', () async {
    final source = await _source(
      '<p id="p">lead<b id="b">A</b><i id="i">B</i>${'tail' * 11}</p>',
      css: 'p{width:64px}',
    );
    final store = MemoryReaderProgressStore();
    final session = await _session(source, store);
    expect(await session.next(), isTrue);
    expect(session.page!.pageIndex, 1);
    expect(session.currentCfi, _cfi('/2[p]/5', 14));
    expect(session.cfiAtPageOffset(session.page!, 24), _cfi('/2[p]/5', 18));

    final target = _cfi('/2[p]/5', 34);
    await session.jumpToCfi(target);
    expect(session.page!.pageIndex, 2);
    expect(session.readingCfi, target);
    await session.applyOverrides(const ReaderOverrides(fontSize: 12));
    expect(session.page!.pageIndex, 1);
    expect(session.readingCfi, target);
    expect(
      ReaderTextRangeGeometry.containsPoint(session.page!, target),
      isTrue,
    );
    await session.flushProgress();
    expect((await store.load('cfi-interaction'))!.cfi, target);
    final restored = await _session(source, store);
    expect(restored.readingCfi, target);
    expect(restored.page!.pageIndex, 1);
  });

  test('分页切片末尾不重复命中下一页的书签位置，原段末尾仍可定位', () async {
    final source = await _source(
      '<p class="float">F</p><p id="p">${'boundary' * 10}</p>',
      css: '.float{float:left;width:16px;height:24px}',
    );
    final session = await _session(source, MemoryReaderProgressStore());
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    for (var index = 1; index < pages.length; index++) {
      final cfi = session.cfiAtPageOffset(pages[index], null)!;
      expect(ReaderTextRangeGeometry.containsPoint(pages[index], cfi), isTrue);
      expect(
        ReaderTextRangeGeometry.containsPoint(pages[index - 1], cfi),
        isFalse,
        reason: '下一页页首不能被上一页的文本切片末尾命中',
      );
    }
    expect(
      ReaderTextRangeGeometry.containsPoint(pages.last, _cfi('/4[p]/1', 80)),
      isTrue,
      reason: '原段真实末尾仍支持尾部留白处的定位',
    );
  });

  test('同段跨元素选区和批注装饰均映射到各自来源字符块', () async {
    final source = await _source(
      '<p id="p">lead<b id="b">A</b><i id="i">B</i>tail</p>',
      css: 'p{width:64px}',
    );
    final page = (await source.loadChapter(0)).single;
    final lines = TextHitTester.lineBoxes(page);
    final selection = ReaderSelection.normalized(
      _hit(lines[1], 0),
      _hit(lines.last, 2),
    );
    final supported = ReaderSelectionSupport.capture([page], selection)!;
    final start = _cfi('/2[p]/2[b]/1', 0);
    final end = _cfi('/2[p]/5', 4);
    expect(supported.startCfi, start);
    expect(supported.endCfi, end);
    expect(supported.quote, 'ABtail');
    final geometry = ReaderTextRangeGeometry.linesFor(
      page,
      startCfi: start,
      endCfi: end,
    );
    expect(_lineText(geometry), 'ABtail');
    final annotation = AnnotationDecorations.linesFor(page, [
      _annotation(start, end),
    ]);
    expect(
      annotation
          .map(
            (line) =>
                line.line.text.substring(line.startOffset, line.endOffset),
          )
          .join(),
      'ABtail',
    );
    expect(ThoughtMarkerGeometry.markersFor(page, annotation), hasLength(1));
    final decoration = ReaderDecorationGeometry.boxesFor(page, [
      ReaderDecorationRange(
        startCfi: start,
        endCfi: end,
        style: const ReaderDecorationStyle(color: 0xFFFF0000),
      ),
    ]);
    expect(_lineText(decoration.map((box) => box.range)), 'ABtail');
  });

  test('正式多列跨页切片复原同一段文字，选区与规则不丢偏移', () async {
    final text = 'leadAB${'tail' * 40}';
    final source = await _source(
      '<p id="p">lead<b id="b">A</b><i id="i">B</i>${'tail' * 40}</p>',
      css: 'p{column-count:2;column-gap:16px}',
      width: 200,
    );
    final chapter = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    var consumed = 0;
    for (final slice in pages.expand((page) => page.slices)) {
      expect(slice.block.cfiAt(0), chapter.cfiAt(consumed));
      consumed += slice.block.layout.text.length;
      expect(
        slice.block.cfiAt(slice.block.layout.text.length, end: true),
        chapter.cfiAt(consumed, end: true),
      );
    }
    expect(consumed, text.length);
    final first = TextHitTester.lineBoxes(pages.first).first;
    final last = TextHitTester.lineBoxes(pages.last).last;
    final selection = ReaderSelection.spanning(
      start: _hit(first, 0),
      startPageIndex: pages.first.pageIndex,
      end: _hit(last, last.text.length),
      endPageIndex: pages.last.pageIndex,
    );
    expect(ReaderSelectionSupport.capture(pages, selection)!.quote, text);
    final engine = ReaderDecorationRuleEngine();
    addTearDown(engine.dispose);
    final matches = await engine.matchChapter(
      pages: pages,
      groups: const [ReaderDecorationRuleGroup(id: 'g', name: '规则')],
      rules: const [
        ReaderDecorationRule(
          id: 'r',
          groupId: 'g',
          pattern: 'ABtail',
          style: ReaderDecorationRuleStyle(color: 0xFFFF0000),
        ),
      ],
      bookId: 'cfi-interaction',
    );
    expect(matches, hasLength(1));
    expect(matches.single.startCfi, _cfi('/2[p]/2[b]/1', 0));
    expect(matches.single.endCfi, _cfi('/2[p]/5', 4));
  });

  test('表格和行内原子盒的后代 CFI 跳转命中真实载荷所在页', () async {
    final source = await _source(
      '<p>${'before' * 4}</p><table><tr><td id="cell"><p id="p">'
      'lead<b id="b">A</b><i id="i">B</i>tail</p></td></tr></table>'
      '<p id="last">lead<span id="s" style="display:inline-block">inside<b id="x">x</b></span>tail</p>',
    );
    final session = await _session(source, MemoryReaderProgressStore());
    final target = _cfi('/4/2/2[cell]/2[p]/5', 2);
    await session.jumpToCfi(target);
    expect(
      session.page!.slices.any(
        (slice) =>
            slice.block.table?.cells.any(
              (cell) => cell.offsetForCfi(target) != null,
            ) ??
            false,
      ),
      isTrue,
    );
    expect(session.page!.pageIndex, greaterThan(0));
    final inner = _cfi('/6[last]/2[s]/2[x]/1', 0);
    await session.jumpToCfi(inner, continuous: true);
    expect(session.readingCfi, inner);
    expect(session.progress!.scrollOffset, isNotNull);
  });

  testWidgets('正式搜索点击跨元素命中时高亮端点落到 tail 的规范 CFI', (tester) async {
    final source = await _prepareSearchSource(tester);
    final start = _cfi('/2[p]/2[b]/1', 0);
    await _showSearchReader(tester, source);
    await _clickSearchResult(tester);
    final layer = tester.widget<AnnotationLayer>(find.byType(AnnotationLayer));
    final highlight = layer.annotations.firstWhere(
      (item) => item.id == 'search-hit',
    );
    expect(highlight.startCfi, start);
    expect(highlight.endCfi, _cfi('/2[p]/5', 4));
    expect(
      AnnotationDecorations.linesFor(layer.page, [highlight])
          .map(
            (line) =>
                line.line.text.substring(line.startOffset, line.endOffset),
          )
          .join(),
      'ABtail',
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('正式搜索端点补算期间翻页，晚到原文不覆盖新导航或补旧高亮', (tester) async {
    final source = await _prepareSearchSource(tester, multipage: true);
    final session = await _showSearchReader(tester, source);
    final pending = Completer<AnchorChapter>();
    source.pendingAnchor = pending.future;
    await _clickSearchResult(tester);
    expect(source.anchorRequests, greaterThan(0));
    expect(_hasSearchHighlight(tester), isFalse);

    expect(await session.next(), isTrue);
    final target = session.readingCfi;
    pending.complete(source.chapter);
    await tester.pumpAndSettle();
    expect(session.readingCfi, target);
    expect(session.page!.pageIndex, 1);
    expect(_hasSearchHighlight(tester), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final error in [const ChapterLoadCancelled(), StateError('原文读取失败')]) {
    testWidgets('正式搜索端点补算失败只跳过高亮，不抛未处理异常：$error', (tester) async {
      final source = await _prepareSearchSource(tester);
      final session = await _showSearchReader(tester, source);
      final pending = Completer<AnchorChapter>();
      source.pendingAnchor = pending.future;
      await _clickSearchResult(tester);
      expect(source.anchorRequests, greaterThan(0));
      final target = session.readingCfi;

      pending.completeError(error);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(session.readingCfi, target);
      expect(_hasSearchHighlight(tester), isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
