import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// 行尾字形：断词连字符 `-`（`hyphens: auto`，布局层只计宽不画字）。
///
/// 字体用 Ahem（每个可打印字符都是 1em 方块），行宽/占位可精确推算。
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

bool _isInk(ByteData b, int x, int y) {
  final offset = (y * _width + x) * 4;
  return b.getUint8(offset + 3) > 0 &&
      (b.getUint8(offset) < 200 ||
          b.getUint8(offset + 1) < 200 ||
          b.getUint8(offset + 2) < 200);
}

Future<ByteData> _render(ComputedStyle style, String text, double maxWidth) async {
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
  PagePainter(background: const Color(0xFFFFFFFF)).paint(
    canvas,
    page,
    pageSize: Size(_width.toDouble(), _height.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hyphens: auto 断词行：行宽含连字符 advance 且带标记', () {
    final layout = TextLayoutEngine.layout(
      text: 'hyphenation demonstration',
      style: _style(const {'hyphens': 'auto'}),
      maxWidth: 96,
    );
    final hyphenated = layout.lines.where((line) => line.hyphenated).toList();
    expect(hyphenated, isNotEmpty, reason: '窄栏 + hyphens:auto 应产生断词行');
    for (final line in hyphenated) {
      expect(line.hyphenWidth, greaterThan(0), reason: '断词行需预留连字符宽');
      expect(
        line.width,
        lessThanOrEqualTo(96),
        reason: '行宽已含连字符，不应超内容宽',
      );
    }
  });

  test('断词行行尾有 `-` 墨迹（布局不改文本、绘制层补画）', () async {
    final style = _style(const {'hyphens': 'auto'});
    const text = 'hyphenation demonstration';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 96,
    );
    final lineIndex =
        layout.lines.indexWhere((line) => line.hyphenated);
    expect(lineIndex, greaterThanOrEqualTo(0));
    final line = layout.lines[lineIndex];
    expect(layout.text, text, reason: '原文不改写（CFI/选区按原文）');

    final data = await _render(style, text, 96);
    // 行 y：前面各行高度累加（行高 24）。
    var lineY = 0.0;
    for (var i = 0; i < lineIndex; i++) {
      lineY += layout.lines[i].height;
    }
    final lineTop = lineY.round();
    final lineBottom = (lineY + line.height).round();
    // 连字符占位区间 = [行宽 − 连字符宽, 行宽)；Ahem 的 `-` 是实心块。
    final hyphenStart = (line.offsetX + line.width - line.hyphenWidth).round();
    final hyphenEnd = (line.offsetX + line.width).round();
    var inkInHyphenSlot = 0;
    for (var y = lineTop; y < lineBottom && y < _height; y++) {
      for (var x = hyphenStart; x < hyphenEnd && x < _width; x++) {
        if (_isInk(data, x, y)) inkInHyphenSlot++;
      }
    }
    expect(
      inkInHyphenSlot,
      greaterThan(0),
      reason: '连字符占位区 [$hyphenStart,$hyphenEnd) 内应有`-`墨迹',
    );

    // 连字符不越出行宽。
    var inkBeyond = 0;
    for (var y = lineTop; y < lineBottom && y < _height; y++) {
      for (var x = hyphenEnd + 1; x < _width; x++) {
        if (_isInk(data, x, y)) inkBeyond++;
      }
    }
    expect(inkBeyond, 0, reason: '行尾字形不应越出行宽');
  });

  test('hyphens: manual：同文本不产生断词行（无行尾连字符）', () {
    final layout = TextLayoutEngine.layout(
      text: 'hyphenation demonstration',
      style: _style(const {'hyphens': 'manual'}),
      maxWidth: 96,
    );
    expect(
      layout.lines.any((line) => line.hyphenated),
      isFalse,
      reason: 'manual 只在显式 &shy; 处断词，本例没有软连字符',
    );
  });
}
