import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _width = 240;
const _height = 120;

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'color': '#000000',
      ...overrides,
    });

TextLayoutResult _layout(String text, ComputedStyle style) =>
    TextLayoutEngine.layout(text: text, style: style, maxWidth: 200);

Future<ByteData> _render(String text, ComputedStyle style) async {
  final layout = _layout(text, style);
  final page = Paginator(pageHeight: _height.toDouble())
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: layout,
            style: style,
            containingWidth: _width.toDouble(),
          ),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const PagePainter().paint(
    canvas,
    page,
    pageSize: Size(_width.toDouble(), _height.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

Color _pixel(ByteData bytes, int x, int y) {
  final offset = (y * _width + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

/// 指定区域内首个墨迹像素的矩形；无墨迹返回 null。
Rect? _inkBounds(ByteData bytes, {int x0 = 0, int x1 = _width}) {
  var left = x1, top = _height, right = -1, bottom = -1;
  for (var y = 0; y < _height; y++) {
    for (var x = x0; x < x1; x++) {
      if (bytes.getUint32((y * _width + x) * 4) != 0xFFFFFFFF) {
        left = min(left, x);
        right = max(right, x);
        top = min(top, y);
        bottom = max(bottom, y);
      }
    }
  }
  return right < 0
      ? null
      : Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          (right + 1).toDouble(),
          (bottom + 1).toDouble(),
        );
}

/// 指定行上首个满足条件的像素列；没有返回 -1。
int _firstColumnWhere(
  ByteData bytes,
  int y,
  bool Function(Color) test, {
  int x0 = 0,
  int x1 = _width,
}) {
  for (var x = x0; x < x1; x++) {
    if (test(_pixel(bytes, x, y))) {
      return x;
    }
  }
  return -1;
}

/// 首个满足条件的像素行；没有返回 -1。
int _firstRowWhere(ByteData bytes, bool Function(Color) test) {
  for (var y = 0; y < _height; y++) {
    if (_firstColumnWhere(bytes, y, test) >= 0) {
      return y;
    }
  }
  return -1;
}

/// 某一行上黑色像素的连续段数。
int _inkRuns(ByteData bytes, int y) {
  var runs = 0;
  var inInk = false;
  for (var x = 0; x < _width; x++) {
    final ink = bytes.getUint32((y * _width + x) * 4) != 0xFFFFFFFF;
    if (ink && !inInk) {
      runs += 1;
    }
    inInk = ink;
  }
  return runs;
}

bool _isWhite(Color color) =>
    color.r > 0.99 && color.g > 0.99 && color.b > 0.99;

bool _isBlack(Color color) =>
    color.r < 0.05 && color.g < 0.05 && color.b < 0.05;

bool _isRed(Color color) => color.r > 0.9 && color.g < 0.1 && color.b < 0.1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无边框无背景样本不绘制装饰', () async {
    final plain = await _render('aa', _style(const {}));
    final none = await _render(
      'aa',
      _style(const {'border': 'none', 'background-color': 'transparent'}),
    );

    expect(_isWhite(_pixel(plain, 0, 0)), isTrue);
    expect(_isWhite(_pixel(plain, 200, 60)), isTrue);
    expect(_inkBounds(none), _inkBounds(plain), reason: '无边框不应多出任何墨迹');
  });

  test('圆角样本：角部裁掉、内部填充、四边描边', () async {
    final style = _style(const {
      'background-color': '#FF0000',
      'border': '2px solid #000000',
      'border-radius': '12px',
    });
    final bytes = await _render('aa\nbb', style);

    expect(_isWhite(_pixel(bytes, 1, 1)), isTrue, reason: '圆角外应露出页面背景');
    expect(_isRed(_pixel(bytes, 20, 24)), isTrue, reason: '圆角内填充背景色');
    expect(_isBlack(_pixel(bytes, 120, 0)), isTrue, reason: '上边框');
    // 切片高度 = 上内缩 2 + 两行 48 + 下内缩 2 = 52，下边框落在 50..52。
    expect(_isBlack(_pixel(bytes, 120, 51)), isTrue, reason: '下边框');
    expect(_isBlack(_pixel(bytes, 1, 24)), isTrue, reason: '左边框');
    expect(_isBlack(_pixel(bytes, 238, 24)), isTrue, reason: '右边框');
  });

  test('虚线样本：顶边分段，实线连续', () async {
    final dashed = await _render(
      'aa',
      _style(const {'border-top': '3px dashed #000000'}),
    );
    final solid = await _render(
      'aa',
      _style(const {'border-top': '3px solid #000000'}),
    );

    expect(_inkRuns(dashed, 1), greaterThanOrEqualTo(3), reason: '虚线应有多个段');
    expect(_inkRuns(solid, 1), 1, reason: '实线应连续');
  });

  test('边框不侵占行布局', () async {
    final plainStyle = _style(const {});
    final borderedStyle = _style(const {
      'border': '6px solid #000000',
      'background-color': '#FF0000',
    });

    final plain = _layout('aa\nbb', plainStyle);
    final bordered = _layout('aa\nbb', borderedStyle);
    expect(bordered.lineCount, plain.lineCount);
    for (var i = 0; i < plain.lineCount; i++) {
      expect(bordered.lines[i].top, plain.lines[i].top);
      expect(bordered.lines[i].height, plain.lines[i].height);
      expect(bordered.lines[i].start, plain.lines[i].start);
      expect(bordered.lines[i].end, plain.lines[i].end);
    }

    // 文本缩进 20px、左右边框各 6px：行布局不变，但文字墨迹让开左边框右移 6px。
    final indented = _style(const {
      'text-indent': '20px',
      'border-left': '6px solid #000000',
      'border-right': '6px solid #000000',
    });
    final indentedPlain = _style(const {'text-indent': '20px'});
    final borderedInk = _inkBounds(
      await _render('aa', indented),
      x0: 10,
      x1: 230,
    );
    final plainInk = _inkBounds(
      await _render('aa', indentedPlain),
      x0: 10,
      x1: 230,
    );
    expect(borderedInk!.left, plainInk!.left + 6, reason: '文字让开左边框内缩 6px');
    expect(borderedInk.top, plainInk.top, reason: '左右边框不影响行高与行位');
    expect(borderedInk.right, plainInk.right + 6, reason: '整行墨迹随内容区内缩平移');
  });

  test('背景色铺满块区域且不越出内容区', () async {
    final bytes = await _render(
      'aa',
      _style(const {'background-color': '#00FF00'}),
    );
    final green = _pixel(bytes, 220, 10);
    expect(green.g, greaterThan(0.9));
    expect(_isWhite(_pixel(bytes, 220, 100)), isTrue, reason: '块外仍是页面背景');
  });

  test('边框内缩：文字不再压在边框上', () async {
    // 红色边框与黑色文字分开统计，便于定位文字墨迹的真实左边界。
    final bytes = await _render(
      'aa',
      _style(const {'border': '6px solid #FF0000'}),
    );

    expect(_isRed(_pixel(bytes, 0, 15)), isTrue, reason: '左边框占据 0..6');
    expect(_isRed(_pixel(bytes, 5, 15)), isTrue, reason: '左边框内沿');
    expect(_isRed(_pixel(bytes, 120, 3)), isTrue, reason: '上边框占据 0..6');
    final textLeft = _firstColumnWhere(bytes, 15, _isBlack);
    expect(
      textLeft,
      greaterThanOrEqualTo(6),
      reason: '文字左边界应让开 6px 边框，不再压住首字符',
    );
    final textTop = _firstRowWhere(bytes, _isBlack);
    expect(textTop, greaterThanOrEqualTo(6), reason: '首行墨迹应让开上边框 6px');
  });

  test('内边距内缩：文字避开 8px 内边距且背景铺满全宽', () async {
    final bytes = await _render(
      'aa',
      _style(const {'padding': '8px', 'background-color': '#00FF00'}),
    );

    // 背景仍铺满边框盒：内边距区域也填色，始终覆盖整行宽。
    expect(_pixel(bytes, 1, 1).g, greaterThan(0.9), reason: '左内边距区域有背景色');
    expect(
      _pixel(bytes, _width - 2, 1).g,
      greaterThan(0.9),
      reason: '右内边距区域有背景色',
    );
    final textLeft = _firstColumnWhere(bytes, 15, _isBlack);
    expect(textLeft, greaterThanOrEqualTo(8), reason: '文字左边界应让开 8px 内边距');
    final textTop = _firstRowWhere(bytes, _isBlack);
    expect(textTop, greaterThanOrEqualTo(8), reason: '首行墨迹应让开上内边距 8px');
  });

  test('边框与内边距叠加：文字左边界与首行顶部各让开 8px', () async {
    final bytes = await _render(
      'aa',
      _style(const {'border': '4px solid #FF0000', 'padding': '4px'}),
    );

    expect(_isRed(_pixel(bytes, 2, 15)), isTrue, reason: '左边框占据 0..4');
    final textLeft = _firstColumnWhere(bytes, 15, _isBlack);
    expect(
      textLeft,
      greaterThanOrEqualTo(8),
      reason: '4px 边框 + 4px 内边距后文字左边界让开 8px',
    );
    final textTop = _firstRowWhere(bytes, _isBlack);
    expect(
      textTop,
      greaterThanOrEqualTo(8),
      reason: '4px 边框 + 4px 内边距后首行墨迹让开 8px',
    );
  });

  test('无 padding/边框：文字位置与无样式基线一致', () async {
    final baseline = await _render('aa', _style(const {}));
    final explicitZero = await _render(
      'aa',
      _style(const {
        'padding': '0px',
        'border': 'none',
        'box-sizing': 'content-box',
      }),
    );

    expect(
      _inkBounds(explicitZero),
      _inkBounds(baseline),
      reason: '零内缩不应改变文字像素位置',
    );
    expect(_inkBounds(baseline)!.left, 0, reason: '无内缩时文字从行首起笔');
  });
}
