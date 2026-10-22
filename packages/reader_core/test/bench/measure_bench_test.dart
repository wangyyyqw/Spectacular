import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const double _pageWidth = 360;
const double _contentHeight = 640;
const double _fontSize = 16;
const int _paragraphLength = 100;
const int _chapterChars = 10000;

final String _paragraphText = List<String>.filled(
  (_paragraphLength / 24).ceil(),
  '中文排版性能基线测试文本，包含常见标点与长短句。',
).join().substring(0, _paragraphLength);

final int _paragraphCount = _chapterChars ~/ _paragraphLength;

ui.Paragraph _buildParagraph() {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontSize: _fontSize,
            height: 1.6,
            textAlign: ui.TextAlign.justify,
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFF000000),
            fontSize: _fontSize,
            height: 1.6,
          ),
        )
        ..addText(_paragraphText);
  final paragraph = builder.build();
  paragraph.layout(const ui.ParagraphConstraints(width: _pageWidth));
  return paragraph;
}

/// 模拟分页：按段落高度累计，满页换页；返回页数。
int _simulatePagination(List<ui.Paragraph> paragraphs) {
  var pages = 1;
  var used = 0.0;
  for (final paragraph in paragraphs) {
    final height = paragraph.height;
    if (used + height > _contentHeight && used > 0) {
      pages++;
      used = 0;
    }
    used += height;
  }
  return pages;
}

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

  test('P0-14 一万字章节的首次分页基线', () {
    final cold = _medianMicros(3, () {
      final paragraphs = List<ui.Paragraph>.generate(
        _paragraphCount,
        (_) => _buildParagraph(),
      );
      _simulatePagination(paragraphs);
    });

    // 缓存复用：段落只构建一次，重复走分页统计。
    final paragraphs = List<ui.Paragraph>.generate(
      _paragraphCount,
      (_) => _buildParagraph(),
    );
    final pages = _simulatePagination(paragraphs);
    final warm = _medianMicros(3, () {
      _simulatePagination(paragraphs);
    });

    final coldMs = cold / 1000;
    final warmMs = warm / 1000;
    // ignore: avoid_print
    print(
      'P0-14 chars=$_chapterChars paragraphs=$_paragraphCount pages=$pages '
      'cold_ms=${coldMs.toStringAsFixed(1)} warm_ms=${warmMs.toStringAsFixed(2)} '
      'per_page_cold_ms=${(coldMs / pages).toStringAsFixed(2)}',
    );

    expect(pages, greaterThan(1));
    expect(coldMs, greaterThan(0));
    expect(coldMs, lessThan(10000), reason: '防止环境异常导致的超长耗时');
  });
}
