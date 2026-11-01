import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';

const _family = 'ProseBenchmarkSerif';
const _source =
    '（《中文旧书》）。「甲乙」，（丙丁）」这是普通正文排版，'
    '混排 EPUB reader 保持英文单词完整；混合字体与注音也应保持原样。';
final _paragraphs = [
  for (var i = 0; i < 20; i++)
    '${(_source * 6).substring(0, 100 - i.toString().length)}$i',
];

Future<void> _loadFonts() async {
  final loader = FontLoader(_family);
  for (final weight in ['Regular', 'Bold']) {
    final bytes = await File(
      '../../apps/reader_mobile/assets/fonts/SourceHanSerifCN-$weight.otf',
    ).readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

List<PageContent> _build(ComputedStyle style) {
  final blocks = [
    for (final text in _paragraphs)
      PageBlock.styled(
        layout: TextLayoutEngine.layout(
          text: text,
          style: style,
          maxWidth: 344,
        ),
        style: style,
        containingWidth: 344,
      ),
  ];
  return Paginator(pageHeight: 700).measureChapter(blocks: blocks).pages;
}

String _geometry(List<PageContent> pages) {
  final buffer = StringBuffer();
  for (final page in pages) {
    for (final slice in page.slices) {
      for (var i = slice.startLine; i < slice.endLine; i++) {
        final line = slice.block.layout.lines[i];
        buffer.write(
          '${page.pageIndex}:${line.start}:${line.end}:'
          '${line.width}:${line.justifyExtra}:${line.spacing?.fingerprint}|',
        );
      }
    }
  }
  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  final enabled = Platform.environment['PROSE_BENCH'] == '1';
  for (final trim in ['trim-adjacent', 'trim-both']) {
    for (final indent in [0, 34]) {
      test('思源宋体 20 段布局与分页：$trim，缩进 $indent', () {
        final style = ComputedStyle({
          'font-family': _family,
          'font-size': '17px',
          'line-height': '1.6',
          'text-align': 'justify',
          'text-spacing-trim': trim,
          'text-indent': '${indent}px',
        });
        for (var i = 0; i < 5; i++) {
          _build(style);
        }
        final samples = <int>[];
        for (var i = 0; i < 11; i++) {
          final watch = Stopwatch()..start();
          _build(style);
          samples.add(watch.elapsedMicroseconds);
        }
        samples.sort();
        final pages = _build(style);
        expect(pages, isNotEmpty);
        expect(_geometry(_build(style)), _geometry(pages));
        // 性能单独采样，不用受机器负载影响的耗时替代正确性断言或原有 8ms 门槛。
        // ignore: avoid_print
        print(
          'PROSE_BENCH trim=$trim indent=$indent '
          'median_ms=${samples[samples.length ~/ 2] / 1000} '
          'pages=${pages.length}',
        );
      }, skip: enabled ? null : '设置 PROSE_BENCH=1 单独运行真实字体性能基准');
    }
  }
}
