import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/punctuation_spacing.dart';
import 'package:reader_core/layout/spaced_paragraph.dart';
import 'package:reader_core/layout/text_spacing.dart';

List<Object> _metrics(LineMetrics metric) => [
  metric.hardBreak,
  metric.ascent,
  metric.descent,
  metric.unscaledAscent,
  metric.height,
  metric.width,
  metric.left,
  metric.baseline,
  metric.lineNumber,
];

PunctuationSpacing _spacing(TextSpan span) {
  final css = ComputedStyle({'text-spacing-trim': 'space-all'});
  return PunctuationSpacing(
    text: span.toPlainText(),
    styleAt: (_) =>
        (css: css, text: span.style ?? const TextStyle(), baselineShift: 0),
  );
}

ui.Paragraph _nativeParagraph(TextSpan span, double scale) {
  final scaler = TextScaler.linear(scale);
  final builder = ui.ParagraphBuilder(
    (span.style ?? const TextStyle()).getParagraphStyle(
      textAlign: TextAlign.start,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    ),
  );
  span.build(builder, textScaler: scaler);
  return builder.build()
    ..layout(const ui.ParagraphConstraints(width: double.infinity));
}

void _expectMeasurement(TextSpan source, double scale, int end) {
  final spacing = _spacing(source);
  final subject = SpacedParagraph(
    text: spacing.text,
    span: source,
    spacing: spacing,
    width: 81.5,
    scale: scale,
  );
  final line = subject.measure(0, end);
  final span = applyTextSpacing(
    end == 0
        ? TextSpan(text: '\u200b', style: spacing.styleAt(0).text)
        : sliceTextSpan(source, 0, end),
    line.spacing,
  );
  final painter = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  final native = _nativeParagraph(span, scale);
  try {
    expect(
      _metrics(line.metrics),
      _metrics(painter.computeLineMetrics().first),
    );
    expect(_metrics(native.getLineMetricsAt(0)!), _metrics(line.metrics));
    expect(native.maxIntrinsicWidth, painter.width);
  } finally {
    native.dispose();
    painter.dispose();
  }
}

Iterable<TextSpan> _sources(TextStyle? style) sync* {
  for (final text in ['', '\n', 'Aa\u0301👨‍👩‍👧‍👦 ffi AV，正文  ', '甲\n乙']) {
    yield TextSpan(text: text, style: style);
  }
  yield TextSpan(
    style: style,
    children: const [
      TextSpan(text: '甲 Aa\u0301'),
      TextSpan(
        text: '👨‍👩‍👧‍👦 ffi AV',
        style: TextStyle(
          fontSize: 31,
          height: 1.3,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
      TextSpan(
        text: '乙\n丙',
        style: TextStyle(
          fontSize: 12,
          height: 0.9,
          leadingDistribution: TextLeadingDistribution.proportional,
        ),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('单行公开原生度量与旧 TextPainter 的九字段和自然宽精确相等', () {
    final styles = <TextStyle?>[
      null,
      const TextStyle(),
      const TextStyle(fontFamily: 'Ahem'),
      const TextStyle(fontSize: 14),
      for (final height in [null, 1.0, 1.6])
        for (final leading in [null, ...TextLeadingDistribution.values])
          TextStyle(
            fontFamily: 'Ahem',
            fontSize: 21,
            height: height,
            leadingDistribution: leading,
            letterSpacing: 0.2,
          ),
    ];
    for (final style in styles) {
      for (final source in _sources(style)) {
        final text = source.toPlainText();
        for (final scale in [1.0, 1.25]) {
          for (final end in {
            0,
            text.length,
            if (text.contains('\n')) text.indexOf('\n'),
          }) {
            _expectMeasurement(source, scale, end);
          }
        }
      }
    }
  });
}
