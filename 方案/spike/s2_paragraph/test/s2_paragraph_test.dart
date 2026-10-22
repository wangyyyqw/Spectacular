import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const double _pageWidth = 360;
const double _fontSize = 16;
const int _charsPerParagraph = 100;

final String _baseText = '中文排版测试段落，用于测量段落构建与缓存命中的耗时。'
    '每一行尽量接近真实书籍的正文长度与标点分布，避免测试文本过于理想化。';
final String _paragraphText = List<String>.generate(
  (_charsPerParagraph / _baseText.length).ceil(),
  (_) => _baseText,
).join().substring(0, _charsPerParagraph);

ui.ParagraphStyle get _paragraphStyle => ui.ParagraphStyle(
  fontSize: _fontSize,
  height: 1.6,
  textAlign: ui.TextAlign.justify,
  maxLines: null,
);

ui.TextStyle get _textStyle => ui.TextStyle(
  color: const ui.Color(0xFF000000),
  fontSize: _fontSize,
  height: 1.6,
);

ui.Paragraph _buildParagraph() {
  final builder = ui.ParagraphBuilder(_paragraphStyle)
    ..pushStyle(_textStyle)
    ..addText(_paragraphText);
  final paragraph = builder.build();
  paragraph.layout(const ui.ParagraphConstraints(width: _pageWidth));
  return paragraph;
}

/// 返回 [runs] 次测量的中位数（微秒）。
int _medianMicros(int runs, void Function() action) {
  final samples = <int>[];
  for (var i = 0; i < runs; i++) {
    final stopwatch = Stopwatch()..start();
    action();
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final count in <int>[30, 60, 90]) {
    test('S2 $count 段的构建与缓存复用耗时', () {
      final paragraphs = <ui.Paragraph>[];

      final coldMicros = _medianMicros(3, () {
        paragraphs
          ..clear()
          ..addAll(List<ui.Paragraph>.generate(count, (_) => _buildParagraph()));
      });

      // 预热一次，避免首次分配影响后续测量。
      for (final paragraph in paragraphs) {
        paragraph.layout(const ui.ParagraphConstraints(width: _pageWidth));
      }

      final warmMicros = _medianMicros(3, () {
        for (final paragraph in paragraphs) {
          // 模拟缓存命中后的重新布局检查（不重新构建 ParagraphBuilder）。
          paragraph.layout(const ui.ParagraphConstraints(width: _pageWidth));
        }
      });

      // ignore: avoid_print
      print(
        'S2 paragraphs=$count cold_ms=${(coldMicros / 1000).toStringAsFixed(2)} '
        'warm_ms=${(warmMicros / 1000).toStringAsFixed(2)} '
        'height=${paragraphs.first.height.toStringAsFixed(1)}',
      );

      expect(paragraphs.length, count);
      expect(coldMicros, greaterThan(0));
      expect(warmMicros, greaterThanOrEqualTo(0));
    });
  }
}
