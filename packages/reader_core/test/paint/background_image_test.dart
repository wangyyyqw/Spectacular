import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/background_image.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// 页面宽：200 是 4 的整数倍，平铺采样点可以按 4 的周期取。
const _pageWidth = 200;

/// 页面高。
const _pageHeight = 120;

/// 单行块高：16px 字号 × 1.5 行高，即块盒子高度（背景图裁剪边界）。
const _blockHeight = 24;

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _white = Color(0xFFFFFFFF);

/// 生成 4×4 的 2×2 棋盘图：左上红、右上绿、左下绿、右下红。
///
/// 像素全部程序化生成，不读磁盘、不读网络。
Future<ui.Image> _checkerImage() {
  const width = 4;
  const height = 4;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final isRed = (x < 2) == (y < 2);
      final offset = (y * width + x) * 4;
      pixels[offset] = isRed ? 255 : 0;
      pixels[offset + 1] = isRed ? 0 : 255;
      pixels[offset + 2] = 0;
      pixels[offset + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      // 文字设为透明：本文件只验证背景绘制，避免字形墨迹干扰像素采样点。
      'color': 'transparent',
      ...overrides,
    });

PageContent _page(ComputedStyle style) =>
    Paginator(pageHeight: _pageHeight.toDouble())
        .measureChapter(
          blocks: [
            PageBlock(
              layout: TextLayoutEngine.layout(
                text: 'aa',
                style: style,
                maxWidth: _pageWidth.toDouble(),
              ),
              style: style,
            ),
          ],
        )
        .pages
        .single;

/// 渲染一页并取回 RGBA 字节。
Future<ByteData> _render(
  ComputedStyle style, {
  ui.Image? Function(String url)? imageLookup,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(imageLookup: imageLookup).paint(
    canvas,
    _page(style),
    pageSize: Size(_pageWidth.toDouble(), _pageHeight.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_pageWidth, _pageHeight);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

Color _pixel(ByteData bytes, int x, int y) {
  final offset = (y * _pageWidth + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

bool _isWhite(Color color) =>
    color.r > 0.99 && color.g > 0.99 && color.b > 0.99;

bool _isRed(Color color) => color.r > 0.9 && color.g < 0.1 && color.b < 0.1;

bool _isGreen(Color color) => color.g > 0.9 && color.r < 0.1 && color.b < 0.1;

bool _isBlue(Color color) => color.b > 0.9 && color.r < 0.1 && color.g < 0.1;

/// 区域内是否全是页面背景色（即该区域没有画出任何背景图）。
bool _allWhite(ByteData bytes, int y0, int y1) {
  for (var y = y0; y < y1; y++) {
    for (var x = 0; x < _pageWidth; x++) {
      if (!_isWhite(_pixel(bytes, x, y))) {
        return false;
      }
    }
  }
  return true;
}

/// 块盒子区域内某种颜色的像素个数。
int _countInBlock(ByteData bytes, bool Function(Color) test) {
  var count = 0;
  for (var y = 0; y < _blockHeight; y++) {
    for (var x = 0; x < _pageWidth; x++) {
      if (test(_pixel(bytes, x, y))) {
        count += 1;
      }
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image tile;

  setUpAll(() async {
    tile = await _checkerImage();
  });

  tearDownAll(() {
    tile.dispose();
  });

  test('块盒子高 24：背景图裁剪边界与页面参数一致', () {
    final page = _page(_style(const {'background-image': 'url(tile.png)'}));

    expect(page.slices, hasLength(1));
    expect(page.slices.single.height, _blockHeight);
    expect(page.topPadding, 0);
  });

  test('平铺：原生尺寸重复，周期 4，棋盘规律成立', () async {
    final bytes = await _render(
      _style(const {'background-image': 'url(tile.png)'}),
      imageLookup: (url) => url == 'tile.png' ? tile : null,
    );

    // 水平方向每 4px 重复一张图：同一局部坐标的像素颜色相同。
    expect(_pixel(bytes, 0, 0), _red, reason: '左上角是图片局部 (0,0)');
    expect(_pixel(bytes, 4, 0), _red, reason: '第 2 张图同一局部坐标仍是红');
    expect(_pixel(bytes, 2, 0), _green, reason: '图片右半为绿');
    expect(_pixel(bytes, 6, 0), _green, reason: '第 2 张图右半仍是绿');
    expect(
      _pixel(bytes, 0, 0),
      isNot(_pixel(bytes, 2, 0)),
      reason: '同一张图内红绿棋盘要有对比',
    );

    // 垂直方向同样重复：局部 (2,2) 落在右下象限（红），(0,2) 落在左下（绿）。
    expect(_pixel(bytes, 2, 2), _red);
    expect(_pixel(bytes, 6, 2), _red, reason: '局部坐标 (2,2) 与上一个瓦片一致');
    expect(_pixel(bytes, 0, 2), _green);
    expect(_pixel(bytes, 4, 2), _green, reason: '局部坐标 (0,2) 与上一个瓦片一致');
    // 纵向周期同样是 4：y 方向到 4 时回到首行象限。
    expect(_pixel(bytes, 0, 4), _pixel(bytes, 0, 0));
  });

  test('裁剪：块盒子以下不再铺图', () async {
    final bytes = await _render(
      _style(const {'background-image': 'url(tile.png)'}),
      imageLookup: (_) => tile,
    );

    expect(
      _isWhite(_pixel(bytes, 0, _blockHeight - 1)),
      isFalse,
      reason: '块末行有图',
    );
    expect(
      _allWhite(bytes, _blockHeight, _pageHeight),
      isTrue,
      reason: '块外仍是页面背景',
    );
  });

  test('无 lookup / lookup 返回 null / 无 background-image 都不出图', () async {
    final noLookup = await _render(
      _style(const {'background-image': 'url(tile.png)'}),
    );
    final nullImage = await _render(
      _style(const {'background-image': 'url(tile.png)'}),
      imageLookup: (_) => null,
    );
    final noBackgroundImage = await _render(
      _style(const {'background-color': 'transparent'}),
      imageLookup: (_) => tile,
    );

    expect(_allWhite(noLookup, 0, _blockHeight), isTrue, reason: '没有取图回调时不画图');
    expect(_allWhite(nullImage, 0, _blockHeight), isTrue, reason: '取图为空时不画图');
    expect(
      _allWhite(noBackgroundImage, 0, _blockHeight),
      isTrue,
      reason: '未声明 background-image 时不画图',
    );
  });

  test('圆角裁剪：角部不露图，内部仍有图', () async {
    final bytes = await _render(
      _style(const {
        'background-image': 'url(tile.png)',
        'border-radius': '12px',
      }),
      imageLookup: (_) => tile,
    );

    expect(_isWhite(_pixel(bytes, 1, 1)), isTrue, reason: '圆角外露页面背景');
    expect(
      _isWhite(_pixel(bytes, 1, _blockHeight - 2)),
      isTrue,
      reason: '左下圆角外不露图',
    );
    expect(
      _isWhite(_pixel(bytes, _pageWidth - 2, 1)),
      isTrue,
      reason: '右上圆角外不露图',
    );
    // (20, 10) 对应图片局部坐标 (0, 2)，棋盘里是绿色；该点远离圆角，不会被裁。
    expect(_isGreen(_pixel(bytes, 20, 10)), isTrue, reason: '圆角内正常铺图');
  });

  test('先色后图：背景图覆盖背景色', () async {
    final bytes = await _render(
      _style(const {
        'background-color': '#0000FF',
        'background-image': 'url(tile.png)',
      }),
      imageLookup: (_) => tile,
    );

    expect(_countInBlock(bytes, _isBlue), 0, reason: '块内被完整覆盖，不残留背景色');
    expect(_countInBlock(bytes, _isRed), greaterThan(0));
    expect(_countInBlock(bytes, _isGreen), greaterThan(0));
  });

  test('paintTiledBackgroundImage 从 bounds 左上角起铺并裁剪到 bounds', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _pageWidth.toDouble(), _pageHeight.toDouble()),
      Paint()..color = _white,
    );
    paintTiledBackgroundImage(
      canvas,
      tile,
      const Rect.fromLTWH(10, 10, 20, 12),
    );
    final image = await recorder.endRecording().toImage(
      _pageWidth,
      _pageHeight,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final bytes = data!;

    expect(_isWhite(_pixel(bytes, 9, 10)), isTrue, reason: 'bounds 左侧不铺图');
    expect(_isRed(_pixel(bytes, 10, 10)), isTrue, reason: '从 bounds 左上角起铺');
    expect(_isGreen(_pixel(bytes, 12, 10)), isTrue, reason: '仍按图片原生尺寸平铺');
    expect(_isWhite(_pixel(bytes, 30, 11)), isTrue, reason: 'bounds 右侧不铺图');
    expect(_isWhite(_pixel(bytes, 10, 22)), isTrue, reason: 'bounds 下侧不铺图');
  });
}
