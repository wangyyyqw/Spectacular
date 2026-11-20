import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

Future<PageContent> _page(String spacing) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="id">行内留白标点压缩回归</dc:identifier></metadata>'
          '<manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest>'
          '<spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html><head><style>'
          'body{margin:0;font-family:MarginPunctuation}'
          'p{margin:0;text-indent:2em;text-align:justify}'
          'span{font-size:.9em;color:purple;$spacing}'
          '</style></head><body><p>有鉴于此，<span>“他”</span>已经不记得自己的事情</p></body></html>',
    }),
    options: const ReaderOpenOptions(contentWidth: 366, contentHeight: 780),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return (await source.loadChapter(0)).single;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('MarginPunctuation')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '../../apps/reader_mobile/assets/fonts/SourceHanSerifCN-Regular.otf',
            ).readAsBytes(),
          ),
        ),
      );
    await loader.load();
  });

  for (final property in ['margin', 'padding']) {
    test('$property 留白不阻止标点自身压缩，也不跨留白应用相邻压缩', () async {
      final page = await _page('$property:0 1%');
      final layout = page.slices.single.block.layout;
      final line = layout.lines.single;
      final glyphs = line.spacing!.glyphs;
      expect(glyphs[4]?.reduction, closeTo(18 * .2, .01), reason: '逗号独立压缩 20%');
      expect(glyphs[5]?.reduction, closeTo(18 * .9 * .2, .01));
      expect(glyphs[7]?.reduction, closeTo(18 * .9 * .2, .01));
      final edgeWidth = line.inlineBoxes.fold<double>(
        0,
        (sum, box) => sum + box.width,
      );
      expect(edgeWidth, closeTo(366 * .02, .01), reason: '保留作者声明的留白宽度');
      final painter = TextPainter(
        text: buildLineSpan(
          layout: layout,
          line: line,
          baseStyle: TextLayoutEngine.textStyleFor(
            page.slices.single.block.style!,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(painter.width + edgeWidth, closeTo(line.advanceWidth, .05));
      painter.dispose();
      final box = TextHitTester.lineBoxes(page).single;
      final comma = TextHitTester.selectionRects(box, 4, 5).single;
      final quote = TextHitTester.selectionRects(box, 5, 6).single;
      expect(quote.left - comma.right, closeTo(366 * .01, .01));
    });
  }

  test('没有留白时逗号和引号仍按相邻标点各压缩 40%', () async {
    final page = await _page('');
    final glyphs = page.slices.single.block.layout.lines.single.spacing!.glyphs;
    expect(glyphs[4]?.reduction, closeTo(18 * .4, .01));
    expect(glyphs[5]?.reduction, closeTo(18 * .9 * .4, .01));
  });
}
