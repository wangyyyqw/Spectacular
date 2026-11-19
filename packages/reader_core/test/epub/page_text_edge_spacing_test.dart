import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _width = 366.6666666666667;
const _height = 773.1694444444444;

Uint8List _epub(String body) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">页首尾段距回归</dc:identifier></metadata>'
      '<manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="dot" href="dot.png" media-type="image/png"/></manifest>'
      '<spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body{margin:0;padding:0;font-family:Ahem}p{margin:1em 0;line-height:1.8em}'
      '.lead{margin:0}img{width:14px;height:14px}'
      '</style></head><body>$body</body></html>',
  'dot.png': base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a8ioAAAAASUVORK5CYII=',
  ),
});

Future<EpubChapterSource> _open(String body, {bool trim = true}) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(body),
    options: ReaderOpenOptions(
      contentWidth: _width,
      contentHeight: _height,
      trimTextEdges: trim,
    ),
  );
  addTearDown(() async {
    source.close();
    await source.preparationsStopped;
  });
  await source.applyContentSize(
    width: _width,
    height: _height,
    topInset: 56.07500000000001,
    sideInsets: (left: 8.8, right: 8.53333333333336),
  );
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('每页首尾回收段距与行高留白，页内段距仍取设置值', () async {
    final source = await _open('<p>首段</p><p>中段</p><p>末段</p>');
    final page = (await source.loadChapter(0)).single;
    final first = page.slices.first;
    final last = page.slices.last;

    expect(first.block.spaceBefore, 10, reason: '保留来源块的段距');
    expect(last.block.spaceAfter, 10);
    expect(first.textTopTrim, greaterThan(0));
    expect(last.textBottomTrim, greaterThan(0));
    expect(first.leadingExtent, closeTo(-first.textTopTrim, 0.001));
    expect(last.trailingExtent, closeTo(-last.textBottomTrim, 0.001));
    expect(page.slices[1].leadingExtent, 10);
    expect(last.leadingExtent, 10);
    final boxes = TextHitTester.lineBoxes(page);
    expect(boxes.first.rect.top, closeTo(0, 0.001));
    expect(boxes.last.rect.bottom, closeTo(page.usedHeight, 0.001));
  });

  test('自然换页后新段首行不带入上段距，渐进分页与重排一致', () async {
    final lead = List.filled(26, '上一段').join('<br/>');
    final source = await _open('<p class="lead">$lead</p><p>新段落开头</p>');
    final pages = await source.loadChapter(0);
    expect(pages, hasLength(2));
    final first = pages.last.slices.first;
    expect(first.block.layout.text, '新段落开头');
    expect(first.startLine, 0);
    expect(first.leadingExtent, closeTo(-first.textTopTrim, 0.001));

    source.clearPaginationCache();
    final handle = source.scheduleProgressiveChapter(0);
    await handle.firstPages;
    final replayed = await handle.result;
    expect(replayed, hasLength(pages.length));
    for (var index = 0; index < pages.length; index++) {
      expect(
        replayed[index].usedHeight,
        closeTo(pages[index].usedHeight, 1e-8),
      );
      expect(
        replayed[index].slices.first.block.startCfi,
        pages[index].slices.first.block.startCfi,
      );
    }
    expect(
      replayed.last.slices.first.leadingExtent,
      closeTo(first.leadingExtent, 1e-8),
    );
  });

  test('段内脚注图片不影响普通首尾行，小图所在行仍可回收额外行高', () async {
    final source = await _open(
      '<p>页首正文<br/>脚注<img src="dot.png"/><br/>页尾正文</p>',
    );
    final page = (await source.loadChapter(0)).single;
    final slice = page.slices.single;
    expect(slice.block.inlineImages, hasLength(1));
    expect(slice.textTopTrim, greaterThan(0));
    expect(slice.textBottomTrim, greaterThan(0));
    expect(slice.leadingExtent, closeTo(-slice.textTopTrim, 0.001));
    expect(slice.trailingExtent, closeTo(-slice.textBottomTrim, 0.001));
    expect(slice.block.textEdgesAt(1).top, greaterThan(0));
    expect(slice.block.textEdgesAt(1).bottom, greaterThan(0));
  });

  for (final height in [14, 40]) {
    test('首尾行有 $height px 图片时只回收盒外留白，图片仍完整', () async {
      final image = '<img src="dot.png" style="height:${height}px"/>';
      final source = await _open('<p>页首$image<br/>中间行<br/>页尾$image</p>');
      final slice = (await source.loadChapter(0)).single.slices.single;
      final first = slice.lines.first;
      final last = slice.lines.last;
      final firstBox = first.inlineBoxes.single;
      final lastBox = last.inlineBoxes.single;
      expect(slice.leadingExtent, closeTo(-slice.textTopTrim, 0.001));
      expect(slice.trailingExtent, closeTo(-slice.textBottomTrim, 0.001));
      expect(
        firstBox.topIn(first.baseline - first.top),
        greaterThanOrEqualTo(slice.textTopTrim),
      );
      expect(
        last.height - (last.baseline - last.top) - lastBox.descent,
        greaterThanOrEqualTo(slice.textBottomTrim),
      );
      expect(slice.textTopTrim, height == 14 ? greaterThan(0) : 0);
      expect(slice.textBottomTrim, greaterThan(0));
    });
  }

  test('关闭阅读裁边时保留 CSS 完整段距与行盒', () async {
    final source = await _open('<p>首段</p><p>末段</p>', trim: false);
    final page = (await source.loadChapter(0)).single;
    expect(page.slices.first.leadingExtent, 10);
    expect(page.slices.last.trailingExtent, 10);
    expect(page.slices.first.textTopTrim, 0);
    expect(page.slices.last.textBottomTrim, 0);
  });
}
