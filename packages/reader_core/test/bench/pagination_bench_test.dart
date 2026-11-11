import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/layout/line_breaker.dart';

const _contentWidth = 360.0;
const _contentHeight = 640.0;
const _chapterChars = 10000;
const _paragraphChars = 100;

const _paragraphSource =
    '中文排版性能基线测试文本，包含常见标点与长短句。'
    '山中有雾，雾里有灯；灯下有人，人读旧书。';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.6',
  'font-family': 'Ahem',
  'text-align': 'justify',
});

List<String> _paragraphs() => <String>[
  for (var i = 0; i < _chapterChars ~/ _paragraphChars; i++)
    '${(_paragraphSource * 6).substring(0, _paragraphChars)}$i',
];

List<PageContent> _paginate(
  List<String> paragraphs,
  ComputedStyle style,
  TextLayoutCache? cache,
) {
  final blocks = <PageBlock>[];
  for (final text in paragraphs) {
    final layout = cache == null
        ? TextLayoutEngine.layout(
            text: text,
            style: style,
            maxWidth: _contentWidth,
          )
        : cache.layout(text: text, style: style, maxWidth: _contentWidth);
    blocks.add(
      PageBlock.styled(
        layout: layout,
        style: style,
        containingWidth: _contentWidth,
      ),
    );
  }
  return Paginator(pageHeight: _contentHeight)
      .measureChapter(blocks: blocks)
      .pages;
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

  test('1 万字章节首次分页 <2s，缓存复用明显更快', () {
    final style = _style();
    final paragraphs = _paragraphs();
    expect(paragraphs.length, _chapterChars ~/ _paragraphChars);

    final coldMicros = _medianMicros(
      3,
      () => _paginate(paragraphs, style, null),
    );
    final cache = TextLayoutCache();
    _paginate(paragraphs, style, cache); // 预热
    final warmMicros = _medianMicros(
      3,
      () => _paginate(paragraphs, style, cache),
    );

    // ignore: avoid_print
    print(
      'BENCH chapter_chars=$_chapterChars cold_ms='
      '${(coldMicros / 1000).toStringAsFixed(2)} warm_ms='
      '${(warmMicros / 1000).toStringAsFixed(2)} '
      'hitRate=${(cache.hitRate * 100).toStringAsFixed(1)}%',
    );

    expect(
      coldMicros,
      lessThan(2000 * 1000),
      reason: '1 万字章节首次分页应 <2s，实际 ${coldMicros / 1000} ms',
    );
    expect(
      warmMicros,
      lessThan(coldMicros),
      reason: '命中段落缓存后应更快（cold=$coldMicros, warm=$warmMicros）',
    );
    expect(cache.hitRate, greaterThan(0.5));
  });

  test('翻页命中 <4ms（缓存页读取）', () {
    final style = _style();
    final cache = TextLayoutCache();
    final pages = _paginate(_paragraphs(), style, cache);
    expect(pages, isNotEmpty);
    final byIndex = <int, PageContent>{
      for (final page in pages) page.pageIndex: page,
    };

    final lookups = <int>[];
    for (var i = 0; i < 100; i++) {
      lookups.add(i % pages.length);
    }
    final stopwatch = Stopwatch()..start();
    var found = 0;
    for (final index in lookups) {
      if (byIndex[index] != null) {
        found += 1;
      }
    }
    stopwatch.stop();
    final averageMicros = stopwatch.elapsedMicroseconds / lookups.length;
    // ignore: avoid_print
    print(
      'BENCH page_hit_avg_us=${averageMicros.toStringAsFixed(2)} '
      'pages=${pages.length}',
    );
    expect(found, lookups.length);
    expect(
      averageMicros,
      lessThan(4000),
      reason: '翻页命中应 <4ms，实际 ${averageMicros / 1000} ms',
    );
  });
}
