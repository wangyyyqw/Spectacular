import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333334);
const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);

Future<PageContent> _page(String declaration, {String? body}) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile full-path="book.opf"/>'
        '</rootfiles></container>',
    'book.opf':
        '<package version="3.0" unique-identifier="id" '
        'xmlns="http://www.idpf.org/2007/opf"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">emphasis-shapes</dc:identifier>'
        '<dc:title>着重号形状回归</dc:title></metadata><manifest>'
        '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="c"/></spine></package>',
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
        'body { margin:0; } p { margin:0; text-indent:0; '
        'font-family:EmphasisShapesSerif; color:#000; } '
        '.mark { text-emphasis-color:#cc0000; text-emphasis-position:under; '
        'text-emphasis-style:$declaration; } '
        '</style></head><body>'
        '${body ?? '<p>前<span class="mark">甲乙</span>后</p>'}'
        '</body></html>',
  });
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _pageInsets.horizontal,
      contentHeight: _pageSize.height - _pageInsets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _pageSize,
    pageInsets: _pageInsets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _redPixels(ByteData data) {
  var count = 0;
  for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
    final red = data.getUint8(offset);
    if (data.getUint8(offset + 3) > 100 &&
        red > 100 &&
        red > data.getUint8(offset + 1) + 20 &&
        red > data.getUint8(offset + 2) + 20) {
      count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes = await File(
      '../../apps/reader_mobile/assets/fonts/MoyuSerif-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'EmphasisShapesSerif',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  test('正式EPUB入口保留同心圆和三角形，并在行内指定位置产生墨迹', () async {
    final cases = {
      'filled double-circle': CssTextEmphasisStyle.doubleCircle,
      'open double-circle': CssTextEmphasisStyle.openDoubleCircle,
      'filled triangle': CssTextEmphasisStyle.triangle,
      'open triangle': CssTextEmphasisStyle.openTriangle,
    };
    final images = <String, Uint8List>{};
    for (final entry in cases.entries) {
      final page = await _page(entry.key);
      final block = page.slices.single.block;
      expect(block.layout.text, '前甲乙后');
      final mark = block.layout.runs.singleWhere((run) => run.start == 1).style;
      expect(mark.textEmphasisStyle, entry.value);
      expect(mark.textEmphasisPosition, CssTextEmphasisPosition.under);
      final pixels = await _render(page);
      expect(_redPixels(pixels), greaterThan(8), reason: entry.key);
      images[entry.key] = pixels.buffer.asUint8List();
    }
    expect(images['filled double-circle'], isNot(images['open double-circle']));
    expect(images['filled triangle'], isNot(images['open triangle']));
    expect(images['filled double-circle'], isNot(images['filled triangle']));
  });

  test('自定义字符串保留大小写并只绘制首个完整字素簇', () async {
    final upper = await _render(await _page('"O"'));
    final lower = await _render(await _page('"o"'));
    final multiple = await _render(await _page('"O X"'));
    final combined = await _render(await _page('"e\u0301"'));
    final combinedMultiple = await _render(await _page('"e\u0301X"'));
    expect(_redPixels(upper), greaterThan(8));
    expect(upper.buffer.asUint8List(), isNot(lower.buffer.asUint8List()));
    expect(upper.buffer.asUint8List(), multiple.buffer.asUint8List());
    expect(
      combined.buffer.asUint8List(),
      combinedMultiple.buffer.asUint8List(),
    );
  });

  test('同章不同自定义字符串不被样式去重合并', () async {
    final page = await _page(
      '"O"',
      body:
          '<p><span class="mark">甲</span>'
          '<span class="mark" style="text-emphasis-style:\'A\'">乙</span></p>',
    );
    final runs = page.slices.single.block.layout.runs;
    expect(runs.map((run) => run.style.textEmphasisString), ['O', 'A']);
    expect(_redPixels(await _render(page)), greaterThan(8));
  });

  test('空字符串有效但不产生着重号或额外块高度', () async {
    final none = await _page('none');
    final empty = await _page('""');
    expect(empty.usedHeight, none.usedHeight);
    expect(_redPixels(await _render(empty)), 0);
    expect(
      (await _render(empty)).buffer.asUint8List(),
      (await _render(none)).buffer.asUint8List(),
    );
  });
}
