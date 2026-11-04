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

/// W23 竖排绘画细节：着重号（列右侧）、装饰线（沿列方向的纵线）、列末省略号。
///
/// Chrome 实测口径（24px/1.6，见 W23 记录）：
/// - 着重号圆心 x ≈ 列右缘、y = 字符中心；
/// - 下划线 x = 列左缘 + 0.13×列宽；删除线 x = 列中线；线宽 = floor(字号/10)；
/// - 列末省略号旋转 90° 接在列尾。
const _width = 200;
const _height = 260;
const _font = 'VerticalDecoSerif';

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '32px',
      'line-height': '1',
      'font-family': _font,
      'color': '#000000',
      'writing-mode': 'vertical-rl',
      ...overrides,
    });

Future<({ByteData bytes, TextLayoutResult layout, double columnOffset})>
_render(ComputedStyle style, String text, {double maxWidth = 200}) async {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: maxWidth,
  );
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
  final columnOffset = page.slices.single.block.verticalColumnOffset;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(
    background: const Color(0xFFFFFFFF),
  ).paint(canvas, page, pageSize: Size(_width.toDouble(), _height.toDouble()));
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return (bytes: data!, layout: layout, columnOffset: columnOffset);
}

int _ch(ByteData b, int x, int y, int c) =>
    b.getUint8((y * _width + x) * 4 + c);

List<({int x, int y})> _pixels(
  ByteData b,
  bool Function(int r, int g, int bl) test,
) {
  final out = <({int x, int y})>[];
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      if (test(_ch(b, x, y, 0), _ch(b, x, y, 1), _ch(b, x, y, 2))) {
        out.add((x: x, y: y));
      }
    }
  }
  return out;
}

bool _isRed(int r, int g, int b) => r > 170 && g < 90 && b < 90;

bool _isBlue(int r, int g, int b) => b > 150 && r < 100 && g < 120;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytes();
    await (FontLoader(
      _font,
    )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
  });

  test('竖排着重号：画在列右侧、y 取字符中心', () async {
    final style = _style(const {
      'text-emphasis': 'filled dot',
      'text-emphasis-color': '#ff0000',
    });
    final result = await _render(style, '一二');
    final column = result.layout.lines.first;
    final columnLeft = result.columnOffset + (column.columnX ?? 0);
    final columnWidth = column.width;
    final dots = _pixels(result.bytes, _isRed);
    expect(dots, isNotEmpty, reason: '应画出着重号');
    // 每字一个点：两个纵向分开的红色像素团。
    final ys = dots.map((p) => p.y).toList()..sort();
    final groups = <List<int>>[];
    for (final y in ys) {
      if (groups.isEmpty || y - groups.last.last > 6) {
        groups.add(<int>[y]);
      } else {
        groups.last.add(y);
      }
    }
    expect(groups.length, 2, reason: '两个字各一个着重号');
    expect(
      groups[0].first,
      closeTo(columnWidth / 2, 8),
      reason: '首字中心 y ≈ 半个字高',
    );
    expect(
      groups[1].first,
      closeTo(columnWidth * 1.5, 8),
      reason: '次字中心 y ≈ 1.5 字高',
    );
    // 列右侧：点圆心 ≈ 列右缘。
    for (final dot in dots) {
      expect(
        dot.x,
        greaterThan(columnLeft + columnWidth * 0.6),
        reason: '着重号应在列右侧',
      );
      expect(
        dot.x,
        lessThan(columnLeft + columnWidth + 2),
        reason: '着重号不应越出列右缘太多',
      );
    }
  });

  test('竖排着重号：over left 改到列左侧', () async {
    final style = _style(const {
      'text-emphasis': 'filled dot',
      'text-emphasis-position': 'over left',
      'text-emphasis-color': '#ff0000',
    });
    final result = await _render(style, '一二');
    final columnLeft =
        result.columnOffset + (result.layout.lines.first.columnX ?? 0);
    final columnWidth = result.layout.lines.first.width;
    final dots = _pixels(result.bytes, _isRed);
    expect(dots, isNotEmpty, reason: '应画出着重号');
    for (final dot in dots) {
      expect(
        dot.x,
        lessThan(columnLeft + columnWidth * 0.4),
        reason: 'left 应把着重号放到列左缘',
      );
    }
  });

  test('竖排下划线：沿列方向的纵线（x 固定、y 跨多字）', () async {
    final style = _style(const {
      'text-decoration': 'underline',
      'text-decoration-color': '#0000ff',
    });
    final result = await _render(style, '甲乙丙');
    final columnLeft =
        result.columnOffset + (result.layout.lines.first.columnX ?? 0);
    final columnWidth = result.layout.lines.first.width;
    final blue = _pixels(result.bytes, _isBlue);
    expect(blue, isNotEmpty, reason: '应画出下划线');
    final xs = blue.map((p) => p.x).toSet();
    final ys = blue.map((p) => p.y).toList()..sort();
    expect(xs.length, lessThanOrEqualTo(4), reason: '竖排下划线是 x 固定的纵线（含线宽抗锯齿）');
    final x = xs.first;
    expect(
      x,
      closeTo(columnLeft + columnWidth * 0.13, 3),
      reason: '下划线位于列左缘内 0.13 列宽处',
    );
    expect(
      ys.last - ys.first,
      greaterThan(columnWidth * 2),
      reason: '下划线应跨越多个字符的高度',
    );
  });

  test('竖排删除线：画在列中线上', () async {
    final style = _style(const {
      'text-decoration': 'line-through',
      'text-decoration-color': '#00aa00',
    });
    final result = await _render(style, '丁戊');
    final columnLeft =
        result.columnOffset + (result.layout.lines.first.columnX ?? 0);
    final columnWidth = result.layout.lines.first.width;
    final green = _pixels(
      result.bytes,
      (r, g, b) => g > 110 && r < 110 && b < 110,
    );
    expect(green, isNotEmpty, reason: '应画出删除线');
    final x = green.map((p) => p.x).reduce((a, b) => a + b) / green.length;
    expect(x, closeTo(columnLeft + columnWidth / 2, 3), reason: '删除线应落在列中线');
  });

  test('竖排声明宽保留整块裁剪区，列带文字不被按单列宽裁掉', () async {
    final style = _style(const {
      'font-size': '24px',
      'width': '54px',
      'height': '150px',
      'white-space': 'nowrap',
      'overflow': 'hidden',
      'text-overflow': 'ellipsis',
    });
    final result = await _render(style, '甲乙丙丁', maxWidth: 54);

    expect(result.layout.width, lessThan(54), reason: '实际列带窄于声明宽');
    final columnLeft =
        result.columnOffset + (result.layout.lines.first.columnX ?? 0);
    expect(
      columnLeft,
      greaterThan(result.layout.width),
      reason: '列带从声明内容盒右缘起排',
    );

    final ink = _pixels(
      result.bytes,
      (r, g, b) => r < 100 && g < 100 && b < 100,
    );
    expect(
      ink.where((pixel) => pixel.x >= 28),
      isNotEmpty,
      reason: '声明宽 54px 时，列左缘附近的文字不能被裁到单列宽 24px',
    );
  });

  test('横排无回归：下划线仍是横向线（y 固定）', () async {
    final style = ComputedStyle(<String, String>{
      'font-size': '32px',
      // 行高 1.6：行高 1 时下划线落在行盒外会被切片裁掉（引擎口径）。
      'line-height': '1.6',
      'font-family': _font,
      'color': '#000000',
      'text-decoration': 'underline',
      'text-decoration-color': '#0000ff',
    });
    final result = await _render(style, '甲乙丙');
    expect(result.layout.isVertical, isFalse);
    final blue = _pixels(result.bytes, _isBlue);
    expect(blue, isNotEmpty, reason: '横排应画出下划线');
    final ys = blue.map((p) => p.y).toSet();
    expect(ys.length, lessThanOrEqualTo(3), reason: '横排下划线是 y 固定（含线宽）的横线');
    final xs = blue.map((p) => p.x).toList()..sort();
    expect(xs.last - xs.first, greaterThan(50), reason: '横排下划线应横向铺开');
  });

  // 注音文本用 CJK：测试字体 SourceHanSerifSC 不含假名，用假名会画不出字形
  // （引擎行为正确，属字体子集问题）。
  test('竖排注音：注音落在列右侧（与无注音渲染对比）', () async {
    Future<ByteData> render({required bool withRuby}) async {
      final style = _style(const {});
      final layout = TextLayoutEngine.layout(
        text: '漢文',
        style: style,
        maxWidth: _width.toDouble(),
      );
      final page = Paginator(pageHeight: _height.toDouble())
          .measureChapter(
            blocks: [
              PageBlock.styled(
                layout: layout,
                style: style,
                containingWidth: _width.toDouble(),
                rubies: withRuby
                    ? const [RubyAnnotation(start: 0, end: 1, text: '注音')]
                    : null,
              ),
            ],
          )
          .pages
          .single;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      PagePainter(background: const Color(0xFFFFFFFF)).paint(
        canvas,
        page,
        pageSize: Size(_width.toDouble(), _height.toDouble()),
      );
      final image = await recorder.endRecording().toImage(_width, _height);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      image.dispose();
      return data;
    }

    final style = _style(const {});
    final layout = TextLayoutEngine.layout(
      text: '漢文',
      style: style,
      maxWidth: _width.toDouble(),
    );
    final columnLeft =
        _width - layout.width + (layout.lines.first.columnX ?? 0);
    final columnWidth = layout.lines.first.width;
    final withRuby = await render(withRuby: true);
    final plain = await render(withRuby: false);
    // vertical-rl 最后一列贴右缘时，右侧仍有半列注音可见；与无注音渲染
    // 比较该条带内的额外墨迹即可确认注音画在列右侧。
    int inkRight(ByteData b) {
      var count = 0;
      final rubyStart = columnLeft + columnWidth - style.fontSize * 0.25;
      for (var y = 0; y < 120; y++) {
        for (var x = rubyStart.toInt(); x < _width; x++) {
          // 任意通道明显偏离白底即算墨迹（注音/文字可能是彩色）。
          if (_ch(b, x, y, 0) < 220 ||
              _ch(b, x, y, 1) < 220 ||
              _ch(b, x, y, 2) < 220) {
            count++;
          }
        }
      }
      return count;
    }

    final rubyInk = inkRight(withRuby);
    final plainInk = inkRight(plain);
    expect(
      rubyInk,
      greaterThan(plainInk + 3),
      reason: '注音应画在列右侧（注音 $rubyInk vs 无注音 $plainInk）',
    );
  });
}
