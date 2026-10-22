import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 一个竖排字形的布局结果。
class VerticalGlyph {
  /// 创建字形布局。
  const VerticalGlyph({
    required this.char,
    required this.column,
    required this.indexInColumn,
    required this.dx,
    required this.dy,
    required this.rotated,
  });

  /// 字符。
  final String char;

  /// 列号（0 为最右列）。
  final int column;

  /// 列内序号。
  final int indexInColumn;

  /// 绘制位置 x。
  final double dx;

  /// 绘制位置 y。
  final double dy;

  /// 是否旋转 90°（竖排标点）。
  final bool rotated;
}

/// 竖排布局原型：右起列、自上而下、逐字定位。
///
/// 只实现 P0-19 需要的几何与标点标记，不含真实字体度量；P5-08 起替换为
/// 基于 TextPainter 的逐字 advance。
class VerticalLayout {
  /// 创建布局器。
  VerticalLayout({
    required this.text,
    this.fontSize = 16,
    this.pageWidth = 320,
    this.pageHeight = 160,
  }) : assert(fontSize > 0),
       assert(pageWidth > 0),
       assert(pageHeight > 0);

  /// 文本。
  final String text;

  /// 字号，同时作为字距与列宽基准。
  final double fontSize;

  /// 可用宽。
  final double pageWidth;

  /// 可用高。
  final double pageHeight;

  /// 每列可容纳的字数。
  int get rowsPerColumn => (pageHeight / fontSize).floor();

  /// 列宽。
  double get columnWidth => fontSize * 1.2;

  /// 可容纳的列数。
  int get columns => (pageWidth / columnWidth).floor();

  /// 竖排需要旋转的标点（§32.3 的子集）。
  static const Set<String> rotatedPunctuation = <String>{
    '。',
    '，',
    '、',
    '；',
    '：',
    '！',
    '？',
    '「',
    '」',
    '『',
    '』',
    '（',
    '）',
    '［',
    '］',
    '【',
    '】',
  };

  /// 计算全部字形位置；超出页面容量时抛 [StateError]。
  List<VerticalGlyph> layout() {
    final chars = text.characters.toList(growable: false);
    if (rowsPerColumn <= 0) {
      throw StateError('页高小于字号');
    }
    final maxChars = rowsPerColumn * columns;
    if (chars.length > maxChars) {
      throw StateError('文本超出原型容量：${chars.length} > $maxChars');
    }

    final glyphs = <VerticalGlyph>[];
    for (var i = 0; i < chars.length; i++) {
      final column = i ~/ rowsPerColumn;
      final indexInColumn = i % rowsPerColumn;
      final columnLeft = pageWidth - (column + 1) * columnWidth;
      final offsetInColumn = (columnWidth - fontSize) / 2;
      glyphs.add(
        VerticalGlyph(
          char: chars[i],
          column: column,
          indexInColumn: indexInColumn,
          dx: columnLeft + offsetInColumn,
          dy: indexInColumn * fontSize,
          rotated: rotatedPunctuation.contains(chars[i]),
        ),
      );
    }
    return glyphs;
  }

  /// 阅读顺序（列从右到左，列内从上到下）。
  String readingText() => layout().map((glyph) => glyph.char).join();
}

/// 竖排原型页面。
class VerticalDemoPage extends StatelessWidget {
  /// 创建页面。
  const VerticalDemoPage({super.key, this.text = '「山中何所有，岭上多白云。」不堪持赠君也'});

  /// 演示文本。
  final String text;

  @override
  Widget build(BuildContext context) {
    final layout = VerticalLayout(text: text, pageWidth: 320, pageHeight: 320);
    return Scaffold(
      appBar: AppBar(title: const Text('竖排原型（P0-19）')),
      body: Center(
        child: SizedBox(
          width: 320,
          height: 320,
          child: CustomPaint(painter: _VerticalPainter(layout)),
        ),
      ),
    );
  }
}

class _VerticalPainter extends CustomPainter {
  _VerticalPainter(this.layout);

  final VerticalLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    for (final glyph in layout.layout()) {
      painter
        ..text = TextSpan(
          text: glyph.char,
          style: TextStyle(fontSize: layout.fontSize, color: Colors.black),
        )
        ..layout();
      canvas.save();
      final centerX = glyph.dx + layout.fontSize / 2;
      final centerY = glyph.dy + layout.fontSize / 2;
      canvas.translate(centerX, centerY);
      if (glyph.rotated) {
        canvas.rotate(math.pi / 2);
      }
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalPainter oldDelegate) =>
      oldDelegate.layout.text != layout.text;
}
