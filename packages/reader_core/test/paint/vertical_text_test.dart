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

/// W22 竖排绘制：CJK 正立、拉丁/数字旋转 90°、sideways/upright、横排无回归。
///
/// 多列的像素口径依赖分页把整块列带放进同一页切片（当前分页只把首列放进
/// 切片，见 task-30 阻塞说明），所以两列用例先锁布局几何（`columnX` 顺序、
/// 列宽、块宽）。绘制侧按 `line.columnX` 定位，切片修好即像素一致。
const _width = 240;
const _height = 200;
const _font = 'VerticalPaintSerif';

ComputedStyle _style({
  String writingMode = 'vertical-rl',
  String textOrientation = 'mixed',
  double fontSize = 32,
}) => ComputedStyle(<String, String>{
  'font-size': '${fontSize}px',
  'line-height': '1',
  'font-family': _font,
  'color': '#000000',
  'writing-mode': writingMode,
  'text-orientation': textOrientation,
});

Future<({ByteData bytes, TextLayoutResult layout})> _render(
  ComputedStyle style,
  String text, {
  double maxWidth = 240,
}) async {
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
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(
    background: const Color(0xFFFFFFFF),
  ).paint(canvas, page, pageSize: Size(_width.toDouble(), _height.toDouble()));
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return (bytes: data!, layout: layout);
}

bool _ink(ByteData b, int x, int y) {
  final offset = (y * _width + x) * 4;
  return b.getUint8(offset) < 160 &&
      b.getUint8(offset + 1) < 160 &&
      b.getUint8(offset + 2) < 160;
}

({int left, int top, int right, int bottom}) _inkBox(ByteData b) {
  var left = _width, top = _height, right = -1, bottom = -1;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      if (!_ink(b, x, y)) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return (left: left, top: top, right: right, bottom: bottom);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytes();
    await (FontLoader(
      _font,
    )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
  });

  test('竖排单列 5 字：字符自上而下排列、x 范围一致', () async {
    final style = _style();
    final result = await _render(style, '一二三四五');
    final layout = result.layout;
    expect(layout.isVertical, isTrue);
    expect(layout.lineCount, 1, reason: '内容放得下一列');
    final columnLength = layout.lines.first.height;
    expect(columnLength, closeTo(5 * 32, 1.5), reason: '列长 = 5 字 × 1em');
    final columnLeft = (_width - layout.width).round();
    // 每字占 1em 的纵向窗口：窗口内应有墨迹。
    for (var i = 0; i < 5; i++) {
      var ink = 0;
      for (var y = i * 32; y < (i + 1) * 32; y++) {
        for (var x = columnLeft; x < _width; x++) {
          if (_ink(result.bytes, x, y)) ink++;
        }
      }
      expect(ink, greaterThan(0), reason: '第 ${i + 1} 个字的窗口内应有墨迹');
    }
    // 列内容之外没有墨迹；字符自顶部起排。
    var inkBeyond = 0;
    for (var y = columnLength.round() + 2; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        if (_ink(result.bytes, x, y)) inkBeyond++;
      }
    }
    expect(inkBeyond, 0, reason: '列内容之外不应有墨迹');
    final box = _inkBox(result.bytes);
    expect(box.top, lessThan(32), reason: '第一字应落在首字窗口内');
    expect(box.right - box.left, lessThan(40), reason: '单列墨迹宽度 ≈ 列宽');
  });

  test('vertical-rl 短段落绘制在内容盒右侧，不再贴左缘', () async {
    final result = await _render(_style(), '一二');
    final box = _inkBox(result.bytes);
    expect(box.right, greaterThan(_width - 24), reason: '列带右缘应贴近正文区右侧');
    expect(box.left, greaterThan(_width - 48), reason: '左侧应留出列带外的空白');
  });

  test('vertical-rl 两列：两列都画出来，且第二列 x 更小', () async {
    final style = _style();
    final result = await _render(style, '一二三四五六', maxWidth: 100);
    final layout = result.layout;
    expect(layout.isVertical, isTrue);
    expect(layout.lineCount, 2, reason: '应排成 2 列');
    expect(layout.width, closeTo(64, 1), reason: '块宽 = 2 列 × 列宽');

    // 逐列找墨迹 x 带：rl 时逻辑首列（第 0 列）在右侧。
    final bands = <({int left, int right})>[];
    var x = 0;
    while (x < _width) {
      var hasInk = false;
      for (var y = 0; y < _height && !hasInk; y++) {
        for (var xx = x; xx < x + 1 && xx < _width; xx++) {
          if (_ink(result.bytes, xx, y)) hasInk = true;
        }
      }
      if (!hasInk) {
        x++;
        continue;
      }
      final left = x;
      while (x < _width) {
        var ink = false;
        for (var y = 0; y < _height && !ink; y++) {
          if (_ink(result.bytes, x, y)) ink = true;
        }
        if (!ink) break;
        x++;
      }
      bands.add((left: left, right: x - 1));
    }
    expect(bands.length, 2, reason: '两列应有两条竖向墨迹带');
    expect(bands[0].right, lessThan(bands[1].left), reason: '两列不重叠');
    // 右侧那列是逻辑首列（rl 从右往左推进）。
    expect(
      layout.lines[0].columnX,
      greaterThan(layout.lines[1].columnX ?? 0),
      reason: 'rl 首列在最右',
    );
  });

  test('vertical-rl / vertical-lr：列序与列宽（布局几何，绘制按 columnX 定位）', () {
    final rl = TextLayoutEngine.layout(
      text: '一二三四五六',
      style: _style(),
      maxWidth: 100,
    );
    expect(rl.isVertical, isTrue);
    expect(rl.lineCount, 2, reason: '应排成 2 列');
    expect(
      rl.lines[0].columnX,
      greaterThan(rl.lines[1].columnX ?? 0),
      reason: 'rl 首列在最右',
    );
    expect(rl.lines[0].width, closeTo(32, 0.5), reason: '列宽 = 行高');
    expect(rl.width, closeTo(64, 1), reason: '块宽 = 列数 × 列宽');

    final lr = TextLayoutEngine.layout(
      text: '一二三四五六',
      style: _style(writingMode: 'vertical-lr'),
      maxWidth: 100,
    );
    expect(
      lr.lines[1].columnX,
      greaterThan(lr.lines[0].columnX ?? 0),
      reason: 'lr 列从左往右推进',
    );
  });

  test('拉丁 mixed：旋转 90° 后墨迹 bbox 宽高互换', () async {
    const text = 'ii';
    final vertical = await _render(_style(), text);
    final verticalBox = _inkBox(vertical.bytes);
    final verticalWidth = verticalBox.right - verticalBox.left;
    final verticalHeight = verticalBox.bottom - verticalBox.top;

    final horizontalStyle = ComputedStyle(<String, String>{
      'font-size': '32px',
      'line-height': '1',
      'font-family': _font,
      'color': '#000000',
    });
    final horizontal = await _render(horizontalStyle, text);
    final horizontalBox = _inkBox(horizontal.bytes);
    final horizontalWidth = horizontalBox.right - horizontalBox.left;
    final horizontalHeight = horizontalBox.bottom - horizontalBox.top;

    expect(horizontalWidth, lessThan(horizontalHeight), reason: '横排 bbox 窄高');
    expect(verticalWidth, greaterThan(verticalHeight), reason: '旋转 90° 后宽矮');
    expect(
      verticalWidth,
      closeTo(horizontalHeight.toDouble(), horizontalHeight * 0.8),
      reason: '旋转后宽 ≈ 横排高（列宽）',
    );
    expect(
      verticalHeight,
      closeTo(horizontalWidth.toDouble(), horizontalWidth * 0.6),
      reason: '旋转后高 ≈ 横排宽（两字 advance 之和）',
    );
  });

  test('text-orientation: sideways 全旋、upright 全正立（同一拉丁文本对比）', () async {
    // 拉丁 i 是窄字形：旋转 90° → bbox 宽 > 高；正立 → bbox 高 > 宽。
    final sideways = await _render(_style(textOrientation: 'sideways'), 'ii');
    final sidewaysBox = _inkBox(sideways.bytes);
    expect(
      sidewaysBox.right - sidewaysBox.left,
      greaterThan(sidewaysBox.bottom - sidewaysBox.top),
      reason: 'sideways 时拉丁仍旋转，bbox 宽 > 高',
    );

    final upright = await _render(_style(textOrientation: 'upright'), 'ii');
    final uprightBox = _inkBox(upright.bytes);
    expect(
      uprightBox.bottom - uprightBox.top,
      greaterThan(uprightBox.right - uprightBox.left),
      reason: 'upright 时拉丁也正立，bbox 高 > 宽（与 sideways 相反）',
    );
  });

  test('横排不受影响：horizontal-tb 仍是单行横排', () async {
    final style = ComputedStyle(<String, String>{
      'font-size': '32px',
      'line-height': '1',
      'font-family': _font,
      'color': '#000000',
    });
    final result = await _render(style, '一二三四五');
    expect(result.layout.isVertical, isFalse);
    final box = _inkBox(result.bytes);
    expect(box.right - box.left, greaterThan(100), reason: '横排向右铺开');
    expect(box.bottom - box.top, lessThan(50), reason: '横排单行高度');
  });
}
