import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _serif = 'MatrixSerif';
const _ahem = 'Ahem';
const _size = Size(240, 160);

Future<void> _loadFonts() async {
  final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytes();
  final bold = await File('../../test_fonts/SourceHanSerifSC-Bold.otf')
      .readAsBytes();
  await (FontLoader(_serif)
        ..addFont(Future.value(ByteData.sublistView(bytes)))
        ..addFont(Future.value(ByteData.sublistView(bold))))
      .load();
}

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': _ahem,
      ...overrides,
    });

Future<ByteData> _render(ComputedStyle style, String text) async {
  final page = Paginator(pageHeight: _size.height)
      .measureChapter(
        blocks: [
          PageBlock(
            layout: TextLayoutEngine.layout(
              text: text,
              style: style,
              maxWidth: 180,
            ),
            style: style,
          ),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const PagePainter().paint(canvas, page, pageSize: _size);
  final image = await recorder.endRecording().toImage(
    _size.width.round(),
    _size.height.round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

Rect? _inkBounds(ByteData bytes) {
  final width = _size.width.round();
  final height = _size.height.round();
  var left = width, top = height, right = -1, bottom = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (bytes.getUint32((y * width + x) * 4) != 0xFFFFFFFF) {
        left = left < x ? left : x;
        right = right > x ? right : x;
        top = top < y ? top : y;
        bottom = bottom > y ? bottom : y;
      }
    }
  }
  if (right < 0) {
    return null;
  }
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    (right + 1).toDouble(),
    (bottom + 1).toDouble(),
  );
}

int _inkDiff(ByteData a, ByteData b) {
  var diff = 0;
  for (var i = 0; i < a.lengthInBytes; i += 4) {
    if (a.getUint32(i) != b.getUint32(i)) {
      diff += 1;
    }
  }
  return diff;
}

/// 第一个墨迹像素的颜色。
Color? _firstInkColor(ByteData bytes) {
  final width = _size.width.round();
  for (var y = 0; y < _size.height.round(); y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      if (bytes.getUint32(offset) != 0xFFFFFFFF) {
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  group('P0 字体与文本属性矩阵', () {
    test('font-size 改变字号与行高', () async {
      final small = await _render(_style(const {}), 'aa');
      final large = await _render(_style(const {'font-size': '32px'}), 'aa');
      final smallInk = _inkBounds(small)!;
      final largeInk = _inkBounds(large)!;
      expect(largeInk.height, greaterThan(smallInk.height));
      expect(largeInk.width, greaterThan(smallInk.width));
    });

    test('font-weight 选到粗体字面', () async {
      final style = _style({'font-family': _serif});
      final normal = await _render(style, '中文');
      final bold = await _render(
        _style({'font-family': _serif, 'font-weight': '700'}),
        '中文',
      );
      expect(_inkDiff(normal, bold), greaterThan(0), reason: '粗体绘制结果应不同');
    });

    test('font-style 映射为 FontStyle.italic', () {
      final italic = TextLayoutEngine.textStyleFor(
        _style(const {'font-style': 'italic'}),
      );
      final normal = TextLayoutEngine.textStyleFor(_style(const {}));
      expect(italic.fontStyle, FontStyle.italic);
      expect(normal.fontStyle, FontStyle.normal);
    });

    test('font-family 切换字族改变行宽', () async {
      final ahem = await _render(_style(const {}), 'aa');
      final serif = await _render(_style(const {'font-family': _serif}), 'aa');
      final ahemWidth = _inkBounds(ahem)!.width;
      final serifWidth = _inkBounds(serif)!.width;
      expect(ahemWidth, isNot(closeTo(serifWidth, 0.5)));
    });

    test('font-family fallback 链生效', () async {
      final fallback = await _render(
        _style(const {'font-family': 'NoSuchFamily, Ahem'}),
        'aa',
      );
      final ahem = await _render(_style(const {}), 'aa');
      final fallbackWidth = _inkBounds(fallback)!.width;
      expect(
        fallbackWidth,
        closeTo(_inkBounds(ahem)!.width, 0.5),
        reason: '未知字族应回落到 Ahem',
      );
      final declared = _style(const {'font-family': 'NoSuchFamily, Ahem'});
      expect(declared.fontFamily, 'NoSuchFamily');
      expect(declared.fontFamilyFallback, ['Ahem']);
    });

    test('line-height 改变行间距', () async {
      final tight = TextLayoutEngine.layout(
        text: 'a\nb',
        style: _style(const {}),
        maxWidth: 180,
      );
      final loose = TextLayoutEngine.layout(
        text: 'a\nb',
        style: _style(const {'line-height': '2.5'}),
        maxWidth: 180,
      );
      expect(tight.lines.first.height, closeTo(24, 0.01));
      expect(loose.lines.first.height, closeTo(40, 0.01));
      expect(
        loose.lines[1].top - tight.lines[1].top,
        closeTo(16, 0.01),
        reason: '行间距差 = 16 × (2.5 - 1.5)',
      );
    });

    test('color 改变绘制颜色', () async {
      final red = await _render(_style(const {'color': '#FF0000'}), 'aa');
      final blue = await _render(_style(const {'color': '#0000FF'}), 'aa');
      final redColor = _firstInkColor(red)!;
      final blueColor = _firstInkColor(blue)!;
      expect(redColor.r, greaterThan(0.8));
      expect(redColor.g, lessThan(0.2));
      expect(blueColor.b, greaterThan(0.8));
      expect(blueColor.r, lessThan(0.2));
    });

    test('text-align 与 text-indent 改变水平位置', () async {
      final left = await _render(_style(const {}), 'aa');
      final centered = await _render(
        _style(const {'text-align': 'center'}),
        'aa',
      );
      final indented = await _render(
        _style(const {'text-indent': '32px'}),
        'aa',
      );
      final leftInk = _inkBounds(left)!;
      final centeredInk = _inkBounds(centered)!;
      final indentedInk = _inkBounds(indented)!;

      expect(centeredInk.left, greaterThan(leftInk.left));
      expect(
        indentedInk.left - leftInk.left,
        closeTo(32, 1),
        reason: '首行缩进 32px',
      );
    });
  });
}
