import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/scroll_layout.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageBlock _block(String text) => PageBlock(
  layout: TextLayoutEngine.layout(text: text, style: _style(), maxWidth: 500),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实阅读参数下，滚动跨页接缝恢复完整行高且不改分页裁边', () async {
    final source = await const EpubFormatOpener().openBytes(
      auditZip({
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml':
            '<container><rootfiles><rootfile full-path="book.opf"/>'
            '</rootfiles></container>',
        'book.opf':
            '<package version="3.0" unique-identifier="id" '
            'xmlns="http://www.idpf.org/2007/opf"><metadata '
            'xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="id">scroll-line-height</dc:identifier>'
            '<dc:title>滚动行高回归</dc:title></metadata><manifest>'
            '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest><spine><itemref idref="c"/></spine></package>',
        'c.xhtml':
            '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
            'body { margin:0; } p { font-family:Ahem; text-indent:2em; '
            'margin:1em 0; line-height:1.8em; }'
            '</style></head><body><p>'
            '${List.filled(70, '甲乙丙丁').join('<br/>')}'
            '</p></body></html>',
      }),
      options: const ReaderOpenOptions(
        contentWidth: 366.6666666666667,
        contentHeight: 773.1694444444445,
      ),
    );
    addTearDown(source.close);
    await source.applyOverrides(
      const ReaderOverrides(
        fontSize: 18,
        lineHeight: 1.6,
        paragraphSpacing: 10,
      ),
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(2));
    final before = [
      for (final page in pages)
        for (final slice in page.slices)
          (slice.height, slice.leadingExtent, slice.trailingExtent),
    ];
    final scroll = ScrollChapterLayout.fromPages(0, pages);
    var top = 0.0;
    double? previous;
    var lineCount = 0;
    for (final segment in scroll.segments) {
      for (final box in TextHitTester.lineBoxes(segment.content)) {
        final line = box.slice.block.layout.lines[box.lineIndex];
        final baseline = top + box.textTop! + line.baseline - line.top;
        if (previous != null) {
          expect(baseline - previous, closeTo(28.8, .001));
        }
        previous = baseline;
        lineCount++;
      }
      top += segment.extent;
    }
    expect(lineCount, 70);
    expect(
      scroll.segments.first.content.slices.first.textTopTrim,
      pages.first.slices.first.textTopTrim,
    );
    expect(
      scroll.segments.last.content.slices.last.textBottomTrim,
      pages.last.slices.last.textBottomTrim,
    );
    expect(
      [
        for (final page in pages)
          for (final slice in page.slices)
            (slice.height, slice.leadingExtent, slice.trailingExtent),
      ],
      before,
      reason: '滚动适配不得修改分页模式的切片',
    );
  });

  test('连续滚动压缩页间空白并保留原切片', () {
    final pages = Paginator(
      pageHeight: 72,
      topPadding: 10,
    ).measureChapter(blocks: [_block('a'), _block('b'), _block('c')]).pages;
    expect(pages, hasLength(2));
    expect(pages.first.usedHeight, 48);
    expect(pages.last.usedHeight, 24);

    final layout = ScrollChapterLayout.fromPages(2, pages);
    expect(layout.segments, hasLength(2));
    expect(layout.segments.first.extent, 58);
    expect(layout.segments.last.extent, 24);
    expect(layout.segments.last.content.topPadding, 0);
    expect(layout.extent, 82);
    expect(layout.offsetOfPage(1), 58);
    expect(layout.pageAtOffset(57), 0);
    expect(layout.pageAtOffset(58), 1);
    expect(
      identical(layout.segments.first.content.slices, pages.first.slices),
      isTrue,
      reason: '滚动模式复用已测量的行切片，不重新断行',
    );
  });

  test('空页不进入滚动流', () {
    final page = Paginator(pageHeight: 72)
        .measureChapter(blocks: [_block('a')])
        .pages
        .single;
    final empty = PageContent(
      spineIndex: 0,
      pageIndex: 1,
      slices: const [],
      usedHeight: 0,
      pageHeight: 72,
      topPadding: 0,
    );

    final layout = ScrollChapterLayout.fromPages(7, [page, empty]);
    expect(layout.spineIndex, 7);
    expect(layout.segments, hasLength(1));
    expect(layout.segments.single.pageIndex, 0);
  });
}
