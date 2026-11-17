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

const _pageSize = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _noteText = '原书附带的文本来源说明。';
const _iconRule =
    '.duokan-footnote img {width:1.2em; '
    'vertical-align:duokan-top-line; text-decoration:none;}';

Future<ui.Image> _icon() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff008800), BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(512, 512);
  } finally {
    picture.dispose();
  }
}

Uint8List _book(Uint8List image, bool iconBeforeError) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">stylesheet-exception</dc:identifier>'
      '<dc:title>样式表异常恢复回归</dc:title></metadata><manifest>'
      '<item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="style.css" media-type="text/css"/>'
      '<item id="i" href="icon.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'chapter.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops"><head>'
      '<link rel="stylesheet" href="style.css"/></head><body>'
      '<p class="metadata"><b>制作：甲<br/><span>文本：未知'
      '<sup><a class="duokan-footnote" epub:type="noteref" '
      'id="reference" href="#note"><img src="icon.png"/></a></sup>'
      '</span></b></p><aside epub:type="footnote">'
      '<ol><li id="note"><a href="#reference"/>$_noteText</li></ol></aside>'
      '<p class="tail">图标后的正文。</p></body></html>',
  'style.css':
      '@import "palette.css" screen;'
      'body {margin:0;} p {text-indent:0;}'
      '.metadata {font-size:65%; text-align:center; margin:.5em 0;}'
      '.metadata span {font-size:1em;}'
      '${iconBeforeError ? _iconRule : ''}'
      'a {text-decoration:none; color:#;}'
      '${iconBeforeError ? '' : _iconRule}'
      '.tail {border-top:1px solid #224466;}',
  'palette.css': '.tail {color:#224466;}',
  'icon.png': image,
});

Future<PageContent> _page(ui.Image image, bool iconBeforeError) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  final source = await const EpubFormatOpener().openBytes(
    _book(bytes, iconBeforeError),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _insets.horizontal,
      contentHeight: _pageSize.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _insets.horizontal,
    height: _pageSize.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return (await source.loadChapter(0)).single;
}

Future<Rect> _paintedIcon(PageContent page, ui.Image icon) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => icon)
      .paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var bounds = Rect.zero;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (pixels.getUint32((y * image.width + x) * 4) != 0x008800ff) continue;
        final pixel = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
        bounds = bounds.isEmpty ? pixel : bounds.expandToInclude(pixel);
      }
    }
    expect(bounds.isEmpty, isFalse, reason: '注释图标必须实际绘制');
    return bounds.shift(-Offset(_insets.left, _insets.top));
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final before in [true, false]) {
    test('解析器异常${before ? '前' : '后'}的有效图标规则保留尺寸、同排正文与注释点击', () async {
      final image = await _icon();
      addTearDown(image.dispose);
      final page = await _page(image, before);
      final metadata = page.slices.first.block;
      final line = metadata.layout.lines.singleWhere(
        (line) => line.inlineBoxes.isNotEmpty,
      );
      final box = line.inlineBoxes.single;
      // 作者盒模型按原书 16px 根字号解算，sup 的 UA 字号为 .83em。
      const expectedSize = 16 * .65 * .83 * 1.2;
      expect(box.width, closeTo(expectedSize, .01));
      expect(box.height, closeTo(expectedSize, .01));
      expect(line.start, metadata.layout.text.indexOf('文本：未知'));
      expect(line.end, metadata.layout.text.length);
      final note = metadata.footnotes.single;
      expect(note.text, _noteText);
      final painted = await _paintedIcon(page, image);
      expect(painted.width, closeTo(expectedSize, 2));
      expect(painted.height, closeTo(expectedSize, 2));
      expect(TextHitTester.footnoteAt(page, painted.center), same(note));
      final tail = page.slices.last.block;
      expect(tail.layout.text, '图标后的正文。');
      expect(tail.style!.values['color'], '#224466');
      expect(tail.style!.borders.top.width, 1);
    });
  }
}
