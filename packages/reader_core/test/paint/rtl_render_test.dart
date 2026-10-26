import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// RTL 绘制方向：行内字形顺序与布局一致（61-logical-properties）。
///
/// 用思源宋体（i / W 字形宽窄差异明显）验证视觉顺序：RTL 下逻辑文本 `iW`
/// 的视觉顺序应与 LTR 下逻辑文本 `Wi` 相同。
const _width = 240;
const _height = 120;
const _font = 'RtlPaintSerif';

Future<void> _loadFont() async {
  final bytes = await File(
    '../../test_fonts/SourceHanSerifSC-Regular.otf',
  ).readAsBytes();
  await (FontLoader(
    _font,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

ComputedStyle _style({
  String direction = 'ltr',
  String textAlign = 'left',
}) => ComputedStyle(<String, String>{
  'font-size': '32px',
  'line-height': '1.5',
  'font-family': _font,
  'color': '#000000',
  'direction': direction,
  'text-align': textAlign,
});

Future<({ByteData bytes, TextLayoutResult layout})> _render(
  ComputedStyle style,
  String text,
) async {
  final layout = TextLayoutEngine.layout(
    text: text,
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
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return (bytes: data!, layout: layout);
}

bool _ink(ByteData b, int x, int y) {
  final offset = (y * _width + x) * 4;
  return b.getUint8(offset) < 200 || b.getUint8(offset + 1) < 200;
}

int _inkCount(ByteData a) {
  var count = 0;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      if (_ink(a, x, y)) count++;
    }
  }
  return count;
}

int _diffPixels(ByteData a, ByteData b) {
  var diff = 0;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final pa = _ink(a, x, y);
      final pb = _ink(b, x, y);
      if (pa != pb) diff++;
    }
  }
  return diff;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('direction: rtl 的布局带 isRtl 标记', () {
    final rtl = TextLayoutEngine.layout(
      text: 'iW',
      style: _style(direction: 'rtl'),
      maxWidth: _width.toDouble(),
    );
    final ltr = TextLayoutEngine.layout(
      text: 'iW',
      style: _style(),
      maxWidth: _width.toDouble(),
    );
    expect(rtl.isRtl, isTrue);
    expect(ltr.isRtl, isFalse);
  });

  test('拉丁串在 RTL 段落里保持 LTR 字形顺序（bidi 口径，与 Chrome 一致）', () async {
    // Unicode bidi：拉丁字母是强 LTR 类，在 RTL 段落内单个拉丁 run 视觉顺序
    // 仍是 LTR，只有段落对齐变化。若绘制层把整行也当成 RTL 反向铺字，
    // 这里就会出现差异——正是本修复要防的「双重反向」。
    final rtl = await _render(_style(direction: 'rtl', textAlign: 'left'), 'iW');
    final ltr = await _render(_style(), 'iW');
    expect(rtl.layout.isRtl, isTrue);
    expect(
      _diffPixels(rtl.bytes, ltr.bytes),
      0,
      reason: 'physical left 对齐下，RTL 段落的拉丁 run 渲染应与 LTR 完全一致',
    );
  });

  test('RTL 的方向体现在对齐：start 靠右、left 仍靠左', () async {
    Future<({int left, int right})> inkExtent(
      String direction,
      String align,
    ) async {
      final result = await _render(
        _style(direction: direction, textAlign: align),
        'iW',
      );
      var left = _width;
      var right = -1;
      for (var y = 0; y < _height; y++) {
        for (var x = 0; x < _width; x++) {
          if (_ink(result.bytes, x, y)) {
            if (x < left) left = x;
            if (x > right) right = x;
          }
        }
      }
      return (left: left, right: right);
    }

    final rtlStart = await inkExtent('rtl', 'start');
    final ltrStart = await inkExtent('ltr', 'start');
    final rtlLeft = await inkExtent('rtl', 'left');
    expect(rtlStart.right, greaterThan(ltrStart.right + 40),
        reason: 'rtl + start 应靠右（段落方向折算）');
    expect(rtlLeft.left, lessThan(10), reason: 'rtl + left 是物理左对齐');
  });

  test('RTL 行 x 与布局一致：text-align: start 靠右出墨', () async {
    final rtl = await _render(
      _style(direction: 'rtl', textAlign: 'start'),
      'iW',
    );
    expect(rtl.layout.isRtl, isTrue);
    // 收集墨迹 x 范围。
    var inkLeft = _width;
    var inkRight = -1;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        if (_ink(rtl.bytes, x, y)) {
          if (x < inkLeft) inkLeft = x;
          if (x > inkRight) inkRight = x;
        }
      }
    }
    expect(inkRight, greaterThanOrEqualTo(0), reason: '应有墨迹');
    // 布局把 start 折算成右对齐：行右缘落在版心右缘附近。
    final line = rtl.layout.lines.first;
    final expectedRight = line.offsetX + line.width;
    expect(
      inkRight,
      closeTo(expectedRight, 8),
      reason: '出墨右缘应与布局行右缘（offsetX + width）一致',
    );
    expect(_inkCount(rtl.bytes), greaterThan(50), reason: '应画出字形');
  });

  test('RTL 命中反算：拉丁 run 的字符映射不因段落方向翻转（bidi 口径）', () async {
    PageContent buildPage(String direction) {
      final style = _style(direction: direction, textAlign: 'start');
      final layout = TextLayoutEngine.layout(
        text: 'iW',
        style: style,
        maxWidth: _width.toDouble(),
      );
      return Paginator(pageHeight: _height.toDouble())
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
    }

    final rtlPage = buildPage('rtl');
    final ltrPage = buildPage('ltr');
    final rtlLine = rtlPage.slices.first.block.layout.lines.first;
    final ltrLine = ltrPage.slices.first.block.layout.lines.first;
    // 拉丁字母是强 LTR 类：RTL 段落里这段 run 仍按 LTR 排，字符映射与 LTR
    // 段落一致；命中层用了同一 baseDirection，不应出现反向。各页用各自行
    // 的 offsetX（RTL start 靠右，绝对 x 并不相同）。
    for (final fraction in <double>[0.1, 0.5, 0.9]) {
      final rtlHit = TextHitTester.hitTest(
        rtlPage,
        Offset(rtlLine.offsetX + rtlLine.width * fraction, rtlLine.height / 2),
      );
      final ltrHit = TextHitTester.hitTest(
        ltrPage,
        Offset(ltrLine.offsetX + ltrLine.width * fraction, ltrLine.height / 2),
      );
      expect(rtlHit, isNotNull);
      expect(ltrHit, isNotNull);
      expect(
        rtlHit!.charOffset,
        ltrHit!.charOffset,
        reason: 'fraction=$fraction 时 RTL/LTR 同一视觉位置应命中同一字符',
      );
    }
  });
}
