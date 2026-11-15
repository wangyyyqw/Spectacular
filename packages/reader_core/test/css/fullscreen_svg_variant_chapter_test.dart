import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _originalPath = 'OEBPS/Images/cover.png';
const _slimPath = 'OEBPS/Images/cover~slim.png';
const _originalColor = Color(0xFF386641);
const _slimColor = Color(0xFF7353A5);
late ui.Image _original;
late ui.Image _slim;
late Uint8List _originalBytes;
late Uint8List _slimBytes;

Future<ui.Image> _image(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<void> _prepareImages() async {
  _original = await _image(1042, 1498, _originalColor);
  _slim = await _image(1042, 2293, _slimColor);
  _originalBytes = (await _original.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  _slimBytes = (await _slim.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
}

Uint8List _bookBytes(String properties, bool withSlim) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/>'
      '</rootfiles></container>',
  'OEBPS/book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">fullscreen-svg-variant</dc:identifier>'
      '<dc:title>全屏 SVG 封面回归</dc:title></metadata><manifest>'
      '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="pic" href="Images/cover.png" media-type="image/png"/>'
      '${withSlim ? '<item id="slim" href="Images/cover~slim.png" media-type="image/png"/>' : ''}'
      '</manifest><spine><itemref idref="c" properties="$properties"/>'
      '</spine></package>',
  'OEBPS/Text/c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
      '<div style="text-align:center;padding:0pt;margin:0pt">'
      '<svg xmlns="http://www.w3.org/2000/svg" height="100%" width="100%" '
      'xmlns:xlink="http://www.w3.org/1999/xlink" '
      'viewBox="0 0 1042 1498" preserveAspectRatio="xMidYMid meet">'
      '<image width="1042" height="1498" '
      'xlink:href="../Images/cover.png"/></svg></div></body></html>',
  _originalPath: _originalBytes,
  if (withSlim) _slimPath: _slimBytes,
});

Future<PageContent> _coverPage(String properties, bool withSlim) async {
  final source = await const EpubFormatOpener().openBytes(
    _bookBytes(properties, withSlim),
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

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    imageLookup: (url) => switch (url) {
      _originalPath => _original,
      _slimPath => _slim,
      _ => null,
    },
  ).paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _pageInsets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _pixel(ByteData pixels, int x, int y) =>
    pixels.getUint32((y * 384 + x) * 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_prepareImages);
  tearDownAll(() {
    _original.dispose();
    _slim.dispose();
  });

  for (final (name, properties, withSlim, expected, mode) in [
    (
      '全屏 SVG meet 的窄版比例略有差异时仍裁切铺满',
      'duokan-page-fullscreen',
      true,
      _slimPath,
      CssBackgroundSizeMode.cover,
    ),
    (
      '全屏 SVG meet 缺少窄版时裁切原图铺满',
      'duokan-page-fullscreen',
      false,
      _originalPath,
      CssBackgroundSizeMode.cover,
    ),
    (
      '窗口适配完整显示原图',
      'duokan-page-fitwindow',
      true,
      _originalPath,
      CssBackgroundSizeMode.contain,
    ),
    (
      '窗口适配优先于全屏图片选择',
      'duokan-page-fullscreen duokan-page-fitwindow',
      true,
      _originalPath,
      CssBackgroundSizeMode.contain,
    ),
  ]) {
    test(name, () async {
      final page = await _coverPage(properties, withSlim);
      final block = page.slices.single.block;
      expect(block.style!.backgroundImage, expected);
      expect(block.style!.backgroundSize.mode, mode);
      expect(block.startCfi, 'epubcfi(/6/2!/4/2/2/2)');
      final pixels = await _paint(page);
      final imageColor = expected == _slimPath ? 0x7353A5FF : 0x386641FF;
      final edgeColor = mode == CssBackgroundSizeMode.cover
          ? imageColor
          : 0xFFFFFFFF;
      for (final (x, y) in [(4, 4), (379, 4), (4, 849), (379, 849)]) {
        expect(_pixel(pixels, x, y), edgeColor, reason: '封面四边的实际绘制结果');
      }
      expect(_pixel(pixels, 192, 426), imageColor);
    });
  }
}
