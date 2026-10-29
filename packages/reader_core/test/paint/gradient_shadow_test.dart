import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// 渐变背景与 box-shadow（blur/spread/inset）的绘制回归（W2）。
const _pageSize = Size(240, 200);
const _serif = 'GradShadowSerif';

Future<void> _loadFont() async {
  final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytes();
  await (FontLoader(
    _serif,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': _serif,
      'color': '#000000',
      ...overrides,
    });

Future<ByteData> _render(ComputedStyle style) async {
  final layout = TextLayoutEngine.layout(
    text: 'A',
    style: style,
    maxWidth: _pageSize.width,
  );
  final page = Paginator(pageHeight: 160)
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: layout,
            style: style,
            containingWidth: _pageSize.width,
          ),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, _pageSize.width, _pageSize.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  const PagePainter().paint(canvas, page, pageSize: _pageSize);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('linear-gradient 90deg：左右半区各取一色（色标停靠点生效）', () async {
    final data = await _render(
      _style(const {
        'background': 'linear-gradient(90deg, #ff0000 0 50%, #0000ff 50% 100%)',
      }),
    );
    final left = _pixel(data, 30, 8);
    final right = _pixel(data, 210, 8);
    expect(left.r, greaterThan(0.8), reason: '左半区取第一色');
    expect(left.b, lessThan(0.2));
    expect(right.b, greaterThan(0.8), reason: '右半区取第二色');
    expect(right.r, lessThan(0.2));
  });

  test('多背景层：后声明层铺底，首层按其尺寸盖在上方', () async {
    final data = await _render(
      _style(const {
        'height': '100px',
        'background-image':
            'linear-gradient(90deg, #ff0000, #ff0000), '
            'linear-gradient(90deg, #0000ff, #0000ff)',
        'background-repeat': 'no-repeat, no-repeat',
        'background-size': '50% 100%, 100% 100%',
        'background-position': 'left top, left top',
      }),
    );
    final topLeft = _pixel(data, 30, 20);
    final topRight = _pixel(data, 210, 20);
    expect(topLeft.r, greaterThan(0.8), reason: '首层红色只覆盖左半');
    expect(topRight.b, greaterThan(0.8), reason: '底层蓝色在右半透出');
  });

  test('linear-gradient 0deg：向上去 ⇒ 底部第一色、顶部第二色', () async {
    final data = await _render(
      _style(const {
        'background': 'linear-gradient(0deg, #ff0000, #0000ff)',
        'padding': '0',
        'font-size': '10px',
        'line-height': '1',
      }),
    );
    // 块高约 10px：取块内上下两行采样（页面顶部 margin 0）
    final bottom = _pixel(data, 120, 9);
    final top = _pixel(data, 120, 1);
    expect(bottom.r, greaterThan(top.r), reason: '底部更红');
    expect(top.b, greaterThan(bottom.b), reason: '顶部更蓝');
  });

  test('linear-gradient 未声明位置的色标在两色之间均分（中点混色）', () async {
    final data = await _render(
      _style(const {
        'background': 'linear-gradient(90deg, #ff0000, #0000ff)',
        'height': '40px',
      }),
    );
    final middle = _pixel(data, 120, 8);
    expect(middle.r, closeTo(0.5, 0.12), reason: '中点红绿蓝接近均分');
    expect(middle.b, closeTo(0.5, 0.12));
  });

  test('radial-gradient circle at 30% 30%：中心为第一色、远角为第二色', () async {
    // 块高 = 行高 1.5 × 16px ≈ 24px；中心在盒内 (30%, 30%)，最远角是右下角。
    final data = await _render(
      _style(const {
        'background': 'radial-gradient(circle at 30% 30%, #00ff00, #0000ff)',
        'color': '#ffffff',
      }),
    );
    final center = _pixel(data, 72, 7);
    final farCorner = _pixel(data, _pageSize.width.toInt() - 2, 22);
    expect(center.g, greaterThan(0.8), reason: '中心接近第一色');
    expect(farCorner.b, greaterThan(0.8), reason: '远角接近第二色');
  });

  test('radial-gradient ellipse：rx=dx√2、ry=dy√2（与 Chromium 一致）', () async {
    // 块高 = 24：椭圆 rx=120√2≈170、ry=12√2≈17；右缘中点归一距离 ≈0.70。
    final data = await _render(
      _style(const {
        'background': 'radial-gradient(ellipse at 50% 50%, #00ff00, #0000ff)',
        'color': '#ffffff',
      }),
    );
    final rightMiddle = _pixel(data, _pageSize.width.toInt() - 2, 12);
    expect(
      rightMiddle.g,
      closeTo(0.30, 0.15),
      reason: '椭圆右缘中点应处于渐变约 70% 处（浏览器实测 0.70）',
    );
    // 圆的同一位置归一距离 ≈0.99，明显更蓝：证明 ellipse 不是按圆处理。
    final circle = await _render(
      _style(const {
        'background': 'radial-gradient(circle at 50% 50%, #00ff00, #0000ff)',
        'color': '#ffffff',
      }),
    );
    final circleRight = _pixel(circle, _pageSize.width.toInt() - 2, 12);
    expect(circleRight.g, lessThan(rightMiddle.g));
  });

  test('box-shadow spread：阴影外扩 spread 像素', () async {
    final data = await _render(
      _style(const {
        'background': '#ffffff',
        'color': '#ffffff',
        // 块左缘留 30px：阴影向盒外扩 6px，可在页面空白处采样。
        'margin-left': '30px',
        'margin-right': '30px',
        'box-shadow': '0 0 0 6px #000000',
      }),
    );
    final inSpread = _pixel(data, 26, 6);
    final outsideSpread = _pixel(data, 18, 6);
    expect(inSpread.r, lessThan(0.5), reason: '盒外 spread 范围内是阴影色');
    expect(outsideSpread.r, greaterThan(0.9), reason: '超出 spread 之外回到页面底色');
  });

  test('box-shadow blur：边缘出现中间灰（有模糊过渡）', () async {
    final data = await _render(
      _style(const {
        'background': '#ffffff',
        'color': '#ffffff',
        'margin-left': '40px',
        'margin-right': '40px',
        'box-shadow': '0 0 8px 0 #000000',
      }),
    );
    // 盒子左缘（x=40）外侧 1~6px：模糊会形成灰阶过渡。
    var grays = 0;
    for (var x = 34; x < 40; x++) {
      final value = _pixel(data, x, 12).r;
      if (value > 0.05 && value < 0.95) grays++;
    }
    expect(grays, greaterThan(0), reason: '模糊边缘应有灰阶过渡');
  });

  test('box-shadow inset：阴影只在 padding-box 内侧（透明边框内不出现）', () async {
    // 大字号把块撑高，留出 10px 透明边框 + 足够的 padding-box 高度。
    final data = await _render(
      _style(const {
        'font-size': '60px',
        'background': '#ffffff',
        'color': '#ffffff',
        'border': '10px solid transparent',
        'box-shadow': 'inset 0 0 0 4px #000000',
      }),
    );
    // 透明边框区域（盒内 0~9px）不画阴影；padding-box 边缘 4px 内有阴影。
    final inBorder = _pixel(data, 5, 5);
    final inPaddingBox = _pixel(data, 12, 20);
    expect(inBorder.r, greaterThan(0.9), reason: '内阴影不进边框区域');
    expect(inPaddingBox.r, lessThan(0.5), reason: 'padding-box 边缘出现内阴影');
  });
}
