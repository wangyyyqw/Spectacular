import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _scale = 1.875;
const _width = 720;
const _height = 1600;
const _imageColor = Color(0xFF2E7D32);
const _titleColor = 0xC0392BFF;
const _borderColor = 0x1D5A6CFF;
const _css = '''
body { margin:0; padding:0; font-family:Ahem; }
.banner { text-align:center; duokan-bleed:lefttopright;
  margin:-30% -30% 0; }
.banner img { width:100%; }
h2 { padding:6px 4px; margin:1em auto 2.5em; font-size:1.2em;
  line-height:130%; color:#c0392b; text-align:left;
  border-top:1px solid #c0392b; border-bottom:1px solid #c0392b; }
.quote { margin:2em .5em; padding:.8em .5em; border-radius:19px;
  border:1px dotted #1d5a6c; color:#02439b; }
.quote p { margin:0; text-indent:2em; line-height:130%; }
''';
late ui.Image _banner;
late Uint8List _bannerBytes;

Future<void> _prepareBanner() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(_imageColor, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    _banner = await picture.toImage(1080, 750);
    _bannerBytes = (await _banner.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    picture.dispose();
  }
}

Uint8List _book(String body, String extraCss) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">banner-quote-style</dc:identifier>'
      '<dc:title>头图与引用框样式回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="i" href="banner.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<style>$_css $extraCss</style></head><body>$body</body></html>',
  'banner.png': _bannerBytes,
});

Future<List<PageContent>> _pages(String body, {String extraCss = ''}) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(body, extraCss),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _insets.horizontal,
      contentHeight: _pageSize.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _insets.horizontal,
    height: _pageSize.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source.loadChapter(0);
}

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => _banner).paint(
    Canvas(recorder)..scale(_scale),
    page,
    pageSize: _pageSize,
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_width, _height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _pixel(ByteData pixels, int x, int y) =>
    pixels.getUint32((y * _width + x) * 4);

Rect _bounds(ByteData pixels, int color) {
  var left = _width, top = _height, right = -1, bottom = -1;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      if (_pixel(pixels, x, y) != color) continue;
      if (x < left) left = x;
      if (y < top) top = y;
      if (x > right) right = x;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '目标颜色必须实际绘制');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

int _borderPixels(ByteData pixels, Rect region) {
  var count = 0;
  for (var y = region.top.ceil(); y < region.bottom.floor(); y++) {
    for (var x = region.left.ceil(); x < region.right.floor(); x++) {
      final offset = (y * _width + x) * 4;
      final red = pixels.getUint8(offset);
      final green = pixels.getUint8(offset + 1);
      final blue = pixels.getUint8(offset + 2);
      // 曲线点线会抗锯齿混入白底，按色差识别边框并排除蓝色正文。
      if (green - red > 12 &&
          blue >= green &&
          (blue - green) * 2 < green - red) {
        count++;
      }
    }
  }
  return count;
}

void _expectRoundedCorners(ByteData pixels, Rect box, {bool bottom = false}) {
  final y = bottom ? box.bottom - 8 : box.top;
  for (final x in [box.left, box.right - 8]) {
    expect(
      _borderPixels(pixels, Rect.fromLTWH(x, y, 8, 8)),
      0,
      reason: '19px 圆角外不能留下直角点线',
    );
  }
  final arcY = bottom ? box.bottom - 27 : box.top + 7;
  expect(
    _borderPixels(pixels, Rect.fromLTWH(box.left + 7, arcY, 20, 20)),
    greaterThan(0),
    reason: '点线必须沿圆角曲线绘制',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_prepareBanner);
  tearDownAll(() => _banner.dispose());

  for (final margin in ['-30%', '0', '40px']) {
    test('章首贴顶头图的 $margin 上边距不使标题与插图重叠或多留空白', () async {
      final page = (await _pages(
        '<div class="banner"><img src="banner.png"/></div>'
        '<h2>TITLE</h2><p>相邻正文</p>',
        extraCss: '.banner { margin-top:$margin; }',
      )).single;
      final pixels = await _paint(page);
      final image = _bounds(pixels, 0x2E7D32FF);
      final title = _bounds(pixels, _titleColor);
      expect(image.top, 0);
      expect(image.width, _width);
      expect(image.bottom, closeTo(500, 1));
      expect(
        (title.top - image.bottom) / _scale,
        closeTo(21 * 1.2, 1),
        reason: '标题上边框与图片之间只保留作者声明的 1em 间距',
      );
    });
  }

  test('普通图片仍按作者的负上边距定位', () async {
    final page = (await _pages(
      '<div class="banner"><img src="banner.png"/></div><h2>TITLE</h2>',
      extraCss: '.banner { duokan-bleed:none; margin:-20px 0 0; }',
    )).single;
    final image = _bounds(await _paint(page), 0x2E7D32FF);
    expect(image.top / _scale, closeTo(_insets.top - 20, 1));
  });

  for (final pattern in ['dotted', 'dashed']) {
    test('$pattern 引用框保留 19px 圆角和曲线上的点线', () async {
      final page = (await _pages(
        '<div class="quote"><p>引用内容</p><p>引用落款</p></div>',
        extraCss: '.quote { border-style:$pattern; }',
      )).single;
      final pixels = await _paint(page);
      final box = _bounds(pixels, _borderColor);
      _expectRoundedCorners(pixels, box);
      _expectRoundedCorners(pixels, box, bottom: true);
    });
  }

  test('横排引用框默认续页闭合并保留圆角', () async {
    final pages = await _pages(
      '<div class="quote">'
      '${List.filled(50, '<p>引用内容</p>').join()}</div>',
    );
    expect(pages.length, greaterThanOrEqualTo(3));
    final middle = await _paint(pages[1]);
    final box = _bounds(middle, _borderColor);
    _expectRoundedCorners(middle, box);
    _expectRoundedCorners(middle, box, bottom: true);
  });

  test('作者声明 slice 时，跨页引用框仅在真实首尾绘制圆角', () async {
    final pages = await _pages(
      '<div class="quote">'
      '${List.filled(50, '<p>引用内容</p>').join()}</div>',
      extraCss: '.quote { box-decoration-break:slice; }',
    );
    expect(pages.length, greaterThanOrEqualTo(3));
    final first = await _paint(pages.first);
    final last = await _paint(pages.last);
    _expectRoundedCorners(first, _bounds(first, _borderColor));
    _expectRoundedCorners(last, _bounds(last, _borderColor), bottom: true);
    final middle = await _paint(pages[1]);
    expect(
      _borderPixels(
        middle,
        Rect.fromLTWH(100, _insets.top * _scale, _width - 200, 4),
      ),
      0,
      reason: '续页顶端不能出现封口边框',
    );
    expect(
      _borderPixels(middle, _bounds(middle, _borderColor)),
      greaterThan(0),
    );
  });
}
