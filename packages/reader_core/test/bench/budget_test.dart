import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_layout_cache.dart';

const _contentWidth = 360.0;
const _contentHeight = 640.0;

/// 预算来自技术方案 §11.2：单页构建 <8ms、缓存命中 <4ms、首屏 <1s。
/// 阈值可用环境变量覆盖，便于验证脚本的失败路径。
double _budget(String name, double fallback) =>
    double.tryParse(
      Platform.environment['BUDGET_${name.toUpperCase()}_MS'] ?? '',
    ) ??
    fallback;

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.6',
  'font-family': 'Ahem',
  'text-align': 'justify',
});

const _source =
    '中文排版性能预算测试文本，包含常见标点与长短句。'
    '山中有雾，雾里有灯；灯下有人，人读旧书。';

String _paragraph(int seed) =>
    '${(_source * 6).substring(0, 100 - seed.toString().length)}$seed';

double _medianMs(int runs, void Function() action) {
  final samples = <double>[];
  for (var i = 0; i < runs; i++) {
    final stopwatch = Stopwatch()..start();
    action();
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds / 1000);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

/// 构建一页：20 个段落布局 + 分页。
double _buildOnePage(ComputedStyle style, List<String> paragraphs) {
  final blocks = <PageBlock>[];
  for (final text in paragraphs) {
    final layout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: _contentWidth,
    );
    blocks.add(
      PageBlock.styled(
        layout: layout,
        style: style,
        containingWidth: _contentWidth,
      ),
    );
  }
  final pages = Paginator(pageHeight: _contentHeight)
      .measureChapter(blocks: blocks)
      .pages;
  return pages.length.toDouble();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.environment['BUDGET_RUN'] == '1';
  // 预算断言在独立进程跑（tool/bench/budget_check.dart），避免与其它测试并发争抢 CPU。
  final skip = enabled
      ? null
      : '默认跳过（预算检查请运行 dart tool/bench/budget_check.dart）';

  test('性能预算：单页构建 / 缓存命中 / 首屏', () {
    final style = _style();
    final pageParagraphs = <String>[for (var i = 0; i < 20; i++) _paragraph(i)];
    final chapterParagraphs = <String>[
      for (var i = 0; i < 100; i++) _paragraph(i),
    ];

    // 预热，排除首次 JIT/字体加载。
    _buildOnePage(style, pageParagraphs);
    _buildOnePage(style, chapterParagraphs);

    final pageBuildMs = _medianMs(5, () {
      _buildOnePage(style, pageParagraphs);
    });

    final cache = TextLayoutCache();
    for (final text in pageParagraphs) {
      cache.layout(text: text, style: style, maxWidth: _contentWidth);
    }
    final cacheHitMs = _medianMs(20, () {
      cache.layout(
        text: pageParagraphs.first,
        style: style,
        maxWidth: _contentWidth,
      );
    });

    final firstPaintMs = _medianMs(3, () {
      _buildOnePage(style, chapterParagraphs);
    });

    final pageBudget = _budget('page_build', 8);
    final hitBudget = _budget('cache_hit', 4);
    final firstPaintBudget = _budget('first_paint', 1000);
    final pass =
        pageBuildMs < pageBudget &&
        cacheHitMs < hitBudget &&
        firstPaintMs < firstPaintBudget;

    // ignore: avoid_print
    print(
      'BUDGET page_build_ms=${pageBuildMs.toStringAsFixed(3)} '
      'cache_hit_ms=${cacheHitMs.toStringAsFixed(3)} '
      'first_paint_ms=${firstPaintMs.toStringAsFixed(3)} '
      'page_budget_ms=$pageBudget hit_budget_ms=$hitBudget '
      'first_paint_budget_ms=$firstPaintBudget pass=$pass',
    );

    expect(
      pageBuildMs,
      lessThan(pageBudget),
      reason: '单页构建应 <${pageBudget}ms，实际 ${pageBuildMs}ms',
    );
    expect(
      cacheHitMs,
      lessThan(hitBudget),
      reason: '缓存命中应 <${hitBudget}ms，实际 ${cacheHitMs}ms',
    );
    expect(
      firstPaintMs,
      lessThan(firstPaintBudget),
      reason: '首屏（首章构建）应 <${firstPaintBudget}ms，实际 ${firstPaintMs}ms',
    );
  }, skip: skip);
}
