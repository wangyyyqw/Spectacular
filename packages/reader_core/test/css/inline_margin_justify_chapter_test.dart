import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _width = 366.0;
const _height = 780.0;

Future<PageContent> _page(String body, {String align = 'justify'}) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="id">行内外边距两端对齐回归</dc:identifier></metadata>'
          '<manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest>'
          '<spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body{margin:0;font-family:Ahem;color:black}'
          'p{margin:0;text-indent:2em;text-align:$align}'
          'span{margin:0 1%;font-size:.9em;color:purple}'
          '</style></head><body>$body</body></html>',
    }),
    options: const ReaderOpenOptions(
      contentWidth: _width,
      contentHeight: _height,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return (await source.loadChapter(0)).first;
}

Future<ByteData> _pixels(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: const Size(_width, _height),
  );
  final image = await recorder.endRecording().toImage(400, 780);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _inkRight(ByteData pixels, PageLineBox box) {
  var right = -1;
  for (var y = box.rect.top.ceil(); y < box.rect.bottom.floor(); y++) {
    for (var x = 0; x < 400; x++) {
      final offset = (y * 400 + x) * 4;
      if (pixels.getUint8(offset + 3) > 128 &&
          pixels.getUint8(offset) < 200 &&
          pixels.getUint8(offset + 1) < 200 &&
          pixels.getUint8(offset + 2) < 200) {
        if (x > right) right = x;
      }
    }
  }
  return right + 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('含百分比外边距和混合字号的行内元素参与换行与两端对齐', () async {
    final page = await _page(
      '<p>如果<span>“他”</span>决定接受的话为了不让前世的眷恋影响到新的人生'
      '也为了不让前世的技术与知识过分深入异世界不保留那些记忆算是一种很干脆的做法</p>',
    );
    final boxes = TextHitTester.lineBoxes(page);
    final pixels = await _pixels(page);
    for (final box in boxes.take(boxes.length - 1)) {
      // 测试字体的墨迹较 advance 右缘内缩约 2px；7.32px 的外边距偏差不可接受。
      expect(_inkRight(pixels, box), closeTo(366, 2.1), reason: box.text);
    }
    expect(_inkRight(pixels, boxes.last), lessThan(365));
  });

  for (final align in ['left', 'center', 'right']) {
    test('行内外边距在 $align 对齐下只占宽一次，文字和命中位置一致', () async {
      final page = await _page('<p>甲<span>乙</span>丙</p>', align: align);
      final box = TextHitTester.lineBoxes(page).single;
      expect(
        box.slice.block.layout.lines.single.width,
        closeTo(18 + 16.2 + 18 + 7.32, .01),
      );
      final selected = TextHitTester.selectionRects(box, 2, 3).single;
      final pixels = await _pixels(page);
      expect(
        _inkRight(pixels, box),
        closeTo(box.rect.left + selected.right, 2.1),
      );
    });
  }

  test('嵌套行内元素跨行时各层外边距仅在真实首尾占宽一次', () async {
    final text = List.filled(60, '甲').join();
    final page = await _page(
      '<p><span><span>$text</span></span></p>',
      align: 'left',
    );
    final boxes = TextHitTester.lineBoxes(page);
    expect(boxes.length, greaterThan(2));
    final layout = boxes.first.slice.block.layout;
    expect(
      layout.lines.fold<double>(0, (sum, line) => sum + line.width),
      closeTo(60 * 18 * .9 * .9 + 4 * 3.66, .01),
    );
    expect(
      TextHitTester.selectionRects(boxes.first, 0, 1).single.left,
      closeTo(7.32, .01),
    );
    expect(
      TextHitTester.selectionRects(boxes[1], 0, 1).single.left,
      closeTo(0, .01),
    );
  });
}
