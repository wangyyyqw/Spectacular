import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// W6：filter 合成 / 重复渐变 / effectiveOpacity / 列表标记图片 / td 竖直居中。
const _pageSize = Size(240, 220);
const _font = 'W6Serif';

Future<void> _loadFont() async {
  final bytes = await File(
    '../../test_fonts/SourceHanSerifSC-Regular.otf',
  ).readAsBytes();
  await (FontLoader(
    _font,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

ComputedStyle _style([
  Map<String, String> overrides = const {},
  ComputedStyle? parent,
]) => ComputedStyle(<String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': _font,
  'color': '#000000',
  ...overrides,
}, parent: parent);

PageBlock _block({
  required String text,
  ComputedStyle? style,
  String? listMarker,
  TableRenderSpec? table,
  double effectiveOpacity = 1,
}) {
  final computed = style ?? _style(const {'font-size': '16px'});
  final layout = TextLayoutEngine.layout(
    text: text,
    style: computed,
    maxWidth: _pageSize.width,
  );
  return PageBlock.styled(
    layout: layout,
    style: computed,
    containingWidth: _pageSize.width,
    listMarker: listMarker,
    table: table,
    effectiveOpacity: effectiveOpacity,
  );
}

Future<ByteData> _render(
  PageBlock block, {
  ui.Image? Function(String url)? imageLookup,
  String? Function(PageBlock block)? listMarkerImageOf,
}) async {
  final page = Paginator(
    pageHeight: _pageSize.height,
  ).measureChapter(blocks: [block]).pages.single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, _pageSize.width, _pageSize.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  PagePainter(
    imageLookup: imageLookup,
    listMarkerImageOf: listMarkerImageOf,
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

Future<ui.Image> _solidImage(int size, int r, int g, int b) {
  final pixels = Uint8List(4 * size * size);
  for (var i = 0; i < size * size; i++) {
    pixels[i * 4] = r;
    pixels[i * 4 + 1] = g;
    pixels[i * 4 + 2] = b;
    pixels[i * 4 + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    size,
    size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('filter grayscale(1)：彩色块变灰（三通道相等）', () async {
    final data = await _render(
      _block(
        text: '去色',
        style: _style(const {
          'background': '#ff0000',
          'color': '#ffffff',
          'filter': 'grayscale(100%)',
        }),
      ),
    );
    final pixel = _pixel(data, 200, 6);
    expect((pixel.r - pixel.g).abs(), lessThan(0.02), reason: '红通道约等于绿');
    expect((pixel.g - pixel.b).abs(), lessThan(0.02), reason: '绿通道约等于蓝');
    expect(pixel.r, closeTo(0.21, 0.06), reason: '纯红灰度按 0.2126 亮度');
  });

  test('filter sepia(0.6)：红块偏褐（蓝通道低于绿）', () async {
    final data = await _render(
      _block(
        text: '怀旧',
        style: _style(const {
          'background': '#ff0000',
          'color': '#ffffff',
          'filter': 'sepia(0.6)',
        }),
      ),
    );
    final pixel = _pixel(data, 200, 6);
    expect(pixel.b, lessThan(pixel.g), reason: 'sepia 后蓝最低');
    expect(pixel.r, greaterThan(pixel.g));
  });

  test('filter 按声明顺序合成：brightness→invert 与 invert→brightness 不同', () async {
    final forward = await _render(
      _block(
        text: '顺序',
        style: _style(const {
          'background': '#808080',
          'filter': 'brightness(0.5) invert(100%)',
        }),
      ),
    );
    final reverse = await _render(
      _block(
        text: '顺序',
        style: _style(const {
          'background': '#808080',
          'filter': 'invert(100%) brightness(0.5)',
        }),
      ),
    );
    final forwardPixel = _pixel(forward, 200, 6);
    final reversePixel = _pixel(reverse, 200, 6);
    expect(
      (forwardPixel.r - reversePixel.r).abs(),
      greaterThan(0.2),
      reason: '先亮度再反相 ≠ 先反相再亮度',
    );
  });

  test('filter blur(2px)：边缘出现灰阶过渡（σ≈2）', () async {
    final data = await _render(
      _block(
        text: '模糊',
        style: _style(const {
          'font-size': '40px',
          'background': '#000000',
          'color': '#ffffff',
          'margin-left': '40px',
          'margin-right': '40px',
          'filter': 'blur(2px)',
        }),
      ),
    );
    var grays = 0;
    for (var y = 1; y < 12; y++) {
      final value = _pixel(data, 120, y).r;
      if (value > 0.05 && value < 0.95) grays++;
    }
    expect(grays, greaterThan(2), reason: '块上缘外侧应有模糊过渡带');
  });

  test('effectiveOpacity：父 0.5 × 子 0.4 ⇒ 合成 0.2', () async {
    final parent = _style(const {'opacity': '0.5'});
    final child = _style(const {
      'background': '#ff0000',
      'opacity': '0.4',
    }, parent);
    expect(child.effectiveOpacity, closeTo(0.2, 1e-9), reason: '样式层已累计');
    final data = await _render(_block(text: '半透明', style: child));
    // 0.2 红 + 0.8 白 ⇒ (1.0, 0.8, 0.8)
    final pixel = _pixel(data, 200, 6);
    expect(pixel.r, closeTo(1.0, 0.03));
    expect(pixel.g, closeTo(0.8, 0.04));
    expect(pixel.b, closeTo(0.8, 0.04));
  });

  test('PageBlock.effectiveOpacity 优先于样式自身值（章节源累计通路）', () async {
    final style = _style(const {
      'font-size': '40px',
      'background': '#ff0000',
    });
    final data = await _render(
      _block(text: '块级', style: style, effectiveOpacity: 0.2),
    );
    final pixel = _pixel(data, 200, 6);
    expect(pixel.g, closeTo(0.8, 0.05), reason: '块级 0.2 覆盖样式 1.0');
  });

  test('repeating-linear-gradient：4px 黑/白条纹周期重复', () async {
    final data = await _render(
      _block(
        text: '条纹',
        style: _style(const {
          'font-size': '40px',
          'color': '#ffffff',
          // 0deg + 单色标像素位置：一个周期 8px（区间写法 `0 4px` 需样式层
          // 展开成两个色标，当前未支持，见 W6 报告）。
          'background':
              'repeating-linear-gradient(0deg, #000000 0, #ffffff 8px)',
        }),
      ),
    );
    // 0deg 向上：从块底往上，色标从 0 起算 ⇒ 底部 0-4px 黑、4-8px 白。
    final colors = <double>[
      for (var y = 2; y < 40; y += 2) _pixel(data, 200, y).r,
    ];
    var transitions = 0;
    for (var i = 1; i < colors.length; i++) {
      if ((colors[i] - colors[i - 1]).abs() > 0.5) transitions++;
    }
    expect(transitions, greaterThan(3), reason: '60px 内应出现多条 8px 条纹');
  });

  test('list-style-image：标记区域画图片（右缘贴正文左缘）', () async {
    final markerImage = await _solidImage(8, 255, 0, 0);
    final data = await _render(
      _block(text: '条目文字', listMarker: '•'),
      imageLookup: (url) => url == 'marker.png' ? markerImage : null,
      listMarkerImageOf: (block) => 'marker.png',
    );
    markerImage.dispose();
    // 正文左缘约在 x=20；1em 图宽 16 ⇒ 标记区域 x≈4..20、首行行盒内居中。
    var red = 0;
    for (var x = 2; x < 20; x++) {
      for (var y = 0; y < 24; y++) {
        final pixel = _pixel(data, x, y);
        if (pixel.r > 0.9 && pixel.g < 0.1) red++;
      }
    }
    expect(red, greaterThan(30), reason: '标记位置应出现图片像素');
  });

  test('无标记图片时回退几何标记（disc）', () async {
    final data = await _render(
      _block(text: '条目文字', listMarker: '•'),
      listMarkerImageOf: (block) => null,
    );
    var dark = 0;
    for (var x = 2; x < 20; x++) {
      for (var y = 0; y < 24; y++) {
        if (_pixel(data, x, y).r < 0.2) dark++;
      }
    }
    expect(dark, greaterThan(10), reason: '回退后应画出黑色圆点');
  });

  test('表格 td vertical-align: middle 时文字在单元格内垂直居中', () async {
    ComputedStyle cellStyle(String align) => _style({
      'font-size': '16px',
      'line-height': '1.5',
      'vertical-align': align,
    });
    PageBlock tableBlock(String align) {
      final style = cellStyle(align);
      final cellLayout = TextLayoutEngine.layout(
        text: '格',
        style: style,
        maxWidth: 100,
      );
      // 与章节源一致：表格块的 layout 只提供一个「高度 = 切片行高」的行盒。
      return PageBlock.styled(
        layout: TextLayoutResult(
          text: '',
          lines: const <LineBox>[
            LineBox(start: 0, end: 0, top: 0, height: 80, baseline: 80, width: 100),
          ],
          width: 100,
          height: 80,
          maxWidth: 100,
          runs: const <StyledRun>[],
        ),
        style: style,
        containingWidth: _pageSize.width,
        table: TableRenderSpec(
          cells: <TableCellRender>[
            TableCellRender(
              row: 0,
              rect: const Rect.fromLTWH(0, 0, 100, 80),
              layout: cellLayout,
              style: style,
            ),
          ],
          columnXs: const <double>[0, 100],
          rowYs: const <double>[0, 80],
          tableWidth: 100,
        ),
      );
    }

    int firstInkRow(ByteData bytes) {
      for (var y = 0; y < _pageSize.height.toInt(); y++) {
        for (var x = 0; x < 100; x++) {
          if (_pixel(bytes, x, y).r < 0.2) return y;
        }
      }
      return -1;
    }

    final top = firstInkRow(await _render(tableBlock('top')));
    final middle = firstInkRow(await _render(tableBlock('middle')));
    expect(top, greaterThanOrEqualTo(0));
    expect(middle, greaterThanOrEqualTo(0));
    // 单元格 80 高、一行文字 24 高 ⇒ middle 比 top 下移约 (80-24)/2 = 28。
    expect(
      middle - top,
      closeTo(28, 4),
      reason: 'middle 分支应把单行文字在 80px 单元格内垂直居中',
    );
  });
}
