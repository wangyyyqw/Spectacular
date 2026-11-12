import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

Future<PageContent> _page(String body) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile '
        'full-path="book.opf"/></rootfiles></container>',
    'book.opf':
        '<package version="3.0" unique-identifier="id" '
        'xmlns="http://www.idpf.org/2007/opf"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">nested-padding</dc:identifier>'
        '<dc:title>嵌套行内边距回归</dc:title><dc:language>zh</dc:language>'
        '</metadata><manifest><item id="c" href="c.xhtml" '
        'media-type="application/xhtml+xml"/>'
        '<item id="image" href="pic.svg" media-type="image/svg+xml"/></manifest>'
        '<spine><itemref idref="c"/></spine></package>',
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
        'p { margin:0; text-indent:0; font-family:Ahem; }'
        'span { padding:0 4px; } i { font-style:normal; }'
        '.inner { padding:0 2px; } img { width:10px; height:10px; padding:0 2px; }'
        '</style></head><body><p>$body</p></body></html>',
    'pic.svg':
        '<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2">'
        '<rect width="2" height="2" fill="red"/></svg>',
  });
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: const ReaderOpenOptions(
      contentWidth: 366.6666666666667,
      contentHeight: 806.9333333333333,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 17, lineHeight: 1.6),
  );
  return (await source.loadChapter(0)).single;
}

void _expectTextPositions(PageContent page, double width, List<double> lefts) {
  final line = TextHitTester.lineBoxes(page).single;
  expect(
    page.slices.single.block.layout.lines.single.width,
    closeTo(width, .01),
  );
  for (var index = 0; index < lefts.length; index++) {
    expect(
      TextHitTester.selectionRects(line, index, index + 1).single.left,
      closeTo(lefts[index], .01),
      reason: '字符 $index 的位置包含真实元素首尾内边距',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('子元素拆分外层样式时不重复添加内边距', () async {
    _expectTextPositions(await _page('<span>甲<i>乙</i>丙</span>'), 59, [
      4,
      21,
      38,
    ]);
  });
  test('外层首尾恰为子元素时仍保留父内边距', () async {
    _expectTextPositions(await _page('<span><i>甲</i>乙<i>丙</i></span>'), 59, [
      4,
      21,
      38,
    ]);
  });
  test('父子元素同边界时各自内边距只累加一次', () async {
    _expectTextPositions(
      await _page('<span><i class="inner">甲乙丙</i></span>'),
      63,
      [6, 23, 40],
    );
  });
  for (final imageFirst in [true, false]) {
    test('图片位于${imageFirst ? '首' : '尾'}时父内边距仅占宽一次', () async {
      final body = imageFirst
          ? '<img src="pic.svg"/>甲'
          : '甲<img src="pic.svg"/>';
      final plain = (await _page(body)).slices.single.block.layout.lines.single;
      final padded = (await _page('<span>$body</span>'))
          .slices
          .single
          .block
          .layout
          .lines
          .single;
      final plainImage = plain.inlineBoxes.singleWhere(
        (box) => box.spec.replacesPlaceholder,
      );
      final paddedImage = padded.inlineBoxes.singleWhere(
        (box) => box.spec.replacesPlaceholder,
      );
      expect(padded.width - plain.width, closeTo(8, .01));
      expect(paddedImage.left - plainImage.left, closeTo(4, .01));
      expect(paddedImage.width, plainImage.width, reason: '图片自身内边距不重复消费');
    });
  }
}
