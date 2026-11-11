import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(120, 80);

const _red = Color(0xFFFF0000);
const _white = Color(0xFFFFFFFF);

/// 2×2 纯红图，程序化生成（不读磁盘/网络）。
Future<ui.Image> _redImage() {
  final pixels = Uint8List(2 * 2 * 4);
  for (var i = 0; i < 4; i++) {
    pixels[i * 4] = 255;
    pixels[i * 4 + 1] = 0;
    pixels[i * 4 + 2] = 0;
    pixels[i * 4 + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    2,
    2,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

ComputedStyle _style({String color = '#000000', bool explicitColor = false}) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'color': color,
    }, hasExplicitTextColor: explicitColor);

PageContent _page(ComputedStyle style, {PageBackground? background}) {
  final layout = TextLayoutEngine.layout(
    text: 'aa',
    style: style,
    maxWidth: 100,
  );
  final page = Paginator(pageHeight: _pageSize.height)
      .measureChapter(
        blocks: <PageBlock>[
          PageBlock.styled(
            layout: layout,
            style: style,
            containingWidth: _pageSize.width,
          ),
        ],
      )
      .pages
      .single;
  return background == null ? page : page.withBackground(background);
}

Future<ByteData> _render(
  PageContent page, {
  ui.Image? Function(String url)? imageLookup,
  Color background = _white,
  Color? textColor,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(
    background: background,
    imageLookup: imageLookup,
    textColor: textColor,
  ).paint(canvas, page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(
    _pageSize.width.toInt(),
    _pageSize.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

Color _pixel(ByteData bytes, int x, int y) {
  final offset = (y * _pageSize.width.toInt() + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

/// 统计偏红墨迹像素（含抗锯齿）。
int _redishPixels(ByteData bytes) {
  var count = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    final r = bytes.getUint8(i);
    final g = bytes.getUint8(i + 1);
    if (r > 180 && g < 90) {
      count += 1;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('整页背景图铺满页面（P9-04）', () async {
    final image = await _redImage();
    final page = _page(
      _style(color: '#000000ff'),
      background: const PageBackground(
        imageUrl: 'OEBPS/bg.png',
        size: CssBackgroundSize.keyword(CssBackgroundSizeMode.cover),
        repeat: CssBackgroundRepeat.noRepeat,
      ),
    );
    final data = await _render(
      page,
      imageLookup: (url) => url == 'OEBPS/bg.png' ? image : null,
    );
    expect(_pixel(data, 60, 40), _red, reason: '封面模式应铺满整页');
  });

  test('没有解码图时整页背景不绘制，保持主题底色', () async {
    final page = _page(
      _style(),
      background: const PageBackground(imageUrl: 'OEBPS/bg.png'),
    );
    final data = await _render(page);
    expect(_pixel(data, 60, 40), _white);
  });

  test('没有背景图时整页背景色仍覆盖主题底色', () async {
    final page = _page(
      _style(),
      background: const PageBackground(backgroundColor: Color(0xFF000000)),
    );
    final data = await _render(page);
    expect(_pixel(data, 115, 75), const Color(0xFF000000));
  });

  test('背景图缺失时书籍背景色仍然保留', () async {
    final page = _page(
      _style(),
      background: const PageBackground(
        imageUrl: 'OEBPS/missing.png',
        backgroundColor: Color(0xFF123456),
      ),
    );
    final data = await _render(page);
    expect(_pixel(data, 115, 75), const Color(0xFF123456));
  });

  test('浅色页：可辨认的书籍显式颜色照书，不被主题色刷掉（P9-02）', () async {
    final page = _page(_style(color: '#94a3b8', explicitColor: true));
    final data = await _render(page, textColor: _red);
    expect(_redishPixels(data), 0, reason: '显式灰色应保留，不变成主题红');
  });

  test('浅色页：显式浅字保持作者颜色，不换成主题色', () async {
    final page = _page(_style(color: '#ffffff', explicitColor: true));
    final data = await _render(page, textColor: _red);
    expect(_redishPixels(data), 0, reason: '作者显式白色不应被主题色替换');
  });

  test('透明显式文字保持透明', () async {
    final page = _page(
      _style(color: 'rgba(255,255,255,0)', explicitColor: true),
    );
    final data = await _render(page, textColor: _red);
    expect(_redishPixels(data), 0, reason: '封面隐藏文字不能被主题色画出来');
  });

  test('作者显式色在日间和夜间都保持不变', () async {
    final page = _page(_style(color: '#ff0000', explicitColor: true));
    final day = await _render(page, textColor: _white);
    final night = await _render(
      page,
      background: const Color(0xFF2B2B2B),
      textColor: _white,
    );
    expect(_redishPixels(day), greaterThan(0), reason: '日间应保留作者红色');
    expect(_redishPixels(night), greaterThan(0), reason: '夜间应保留作者红色');
  });

  test('父级作者色继承到子元素后，日间和夜间都不被主题色替换', () async {
    final parent = _style(color: '#ff0000', explicitColor: true);
    final child = ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    }, parent: parent);
    expect(child.color, const Color(0xFFFF0000));
    expect(child.hasExplicitTextColor, isTrue);

    final page = _page(child);
    final day = await _render(page, textColor: _white);
    final night = await _render(
      page,
      background: const Color(0xFF2B2B2B),
      textColor: _white,
    );
    expect(_redishPixels(day), greaterThan(0), reason: '日间应保留继承的红色');
    expect(_redishPixels(night), greaterThan(0), reason: '夜间应保留继承的红色');
  });

  test('浅色页：未声明的默认黑字跟随主题色', () async {
    final page = _page(_style());
    final data = await _render(page, textColor: _red);
    expect(_redishPixels(data), greaterThan(0), reason: '默认黑字应取主题色');
  });

  test('深色页：显式深色与浅色文字都保持作者颜色', () async {
    final darkPage = _page(_style(color: '#000000', explicitColor: true));
    final darkData = await _render(
      darkPage,
      background: const Color(0xFF101010),
      textColor: _white,
    );
    var whiteInk = 0;
    for (var i = 0; i < darkData.lengthInBytes; i += 4) {
      if (darkData.getUint8(i) > 200 &&
          darkData.getUint8(i + 1) > 200 &&
          darkData.getUint8(i + 2) > 200) {
        whiteInk += 1;
      }
    }
    expect(whiteInk, 0, reason: '作者显式黑色不应被主题色替换');

    final lightPage = _page(_style(color: '#ffe08a', explicitColor: true));
    final lightData = await _render(
      lightPage,
      background: const Color(0xFF101010),
      textColor: _white,
    );
    var yellowInk = 0;
    for (var i = 0; i < lightData.lengthInBytes; i += 4) {
      if (lightData.getUint8(i) > 200 && lightData.getUint8(i + 2) < 160) {
        yellowInk += 1;
      }
    }
    expect(yellowInk, greaterThan(0), reason: '浅色字在黑底上应保留原色');
  });
}
