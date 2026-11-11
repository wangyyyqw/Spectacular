import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_ui/page_cache.dart';

PageContent _page(int index, {int spine = 0}) => PageContent(
  spineIndex: spine,
  pageIndex: index,
  slices: const <PageBlockSlice>[],
  usedHeight: 0,
  pageHeight: 100,
  topPadding: 0,
);

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageContent _pageWithText(int index) {
  final layout = TextLayoutEngine.layout(
    text: 'page$index',
    style: _style(),
    maxWidth: 300,
  );
  final block = PageBlock(layout: layout, style: _style());
  return PageContent(
    spineIndex: 0,
    pageIndex: index,
    slices: <PageBlockSlice>[
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: 1,
        height: layout.height,
      ),
    ],
    usedHeight: layout.height,
    pageHeight: 100,
    topPadding: 0,
  );
}

void main() {
  test('连续翻 10 页，第二次经过命中率 100%', () async {
    var calls = 0;
    final cache = PageCache(
      loader: (spine, page) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return _pageWithText(page);
      },
      capacity: 16,
    );

    final first = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      await cache.get(0, i);
    }
    first.stop();
    expect(calls, 10);

    final hitsBefore = cache.hits;
    final second = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      final page = await cache.get(0, i);
      expect(page.pageIndex, i);
    }
    second.stop();

    expect(cache.hits - hitsBefore, 10);
    expect(calls, 10);
    // 命中路径应当明显快于首次加载。
    expect(second.elapsed, lessThan(first.elapsed));
    expect(
      second.elapsedMicroseconds,
      lessThan(first.elapsedMicroseconds * 0.5),
    );
  });

  test('相邻页预取 ±2 页', () async {
    var calls = 0;
    final cache = PageCache(
      loader: (spine, page) async {
        calls += 1;
        return _page(page);
      },
      prefetchRadius: 2,
    );
    await cache.prefetchAround(spineIndex: 0, pageIndex: 5, pageCount: 10);
    expect(calls, 4);
    expect(cache.contains(0, 3), isTrue);
    expect(cache.contains(0, 4), isTrue);
    expect(cache.contains(0, 6), isTrue);
    expect(cache.contains(0, 7), isTrue);
    expect(cache.contains(0, 5), isFalse);
    expect(cache.contains(0, 2), isFalse);
    expect(cache.contains(0, 8), isFalse);
  });

  test('并发取同一页只加载一次', () async {
    var calls = 0;
    final cache = PageCache(
      loader: (spine, page) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return _page(page);
      },
    );
    final results = await Future.wait([
      cache.get(0, 0),
      cache.get(0, 0),
      cache.get(0, 0),
    ]);
    expect(calls, 1);
    expect(results.every((page) => page.pageIndex == 0), isTrue);
  });

  test('LRU 容量淘汰最久未使用页', () async {
    var calls = 0;
    final cache = PageCache(
      loader: (spine, page) async {
        calls += 1;
        return _page(page);
      },
      capacity: 2,
    );
    await cache.get(0, 0);
    await cache.get(0, 1);
    await cache.get(0, 2);
    expect(cache.contains(0, 0), isFalse);
    expect(cache.contains(0, 1), isTrue);
    expect(cache.contains(0, 2), isTrue);
    await cache.get(0, 0);
    expect(calls, 4);
  });

  test('evictExcept 与 clear', () async {
    final cache = PageCache(loader: (spine, page) async => _page(page));
    await cache.get(0, 0);
    await cache.get(0, 1);
    await cache.get(0, 2);
    cache.evictExcept(<PageKey>{const PageKey(0, 1)});
    expect(cache.contains(0, 0), isFalse);
    expect(cache.contains(0, 1), isTrue);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.hits, 0);
    expect(cache.misses, 0);
  });

  test('loader 失败不缓存且可重试', () async {
    var calls = 0;
    final cache = PageCache(
      loader: (spine, page) async {
        calls += 1;
        if (calls == 1) {
          throw StateError('load failed');
        }
        return _page(page);
      },
    );
    await expectLater(cache.get(0, 0), throwsStateError);
    expect(cache.contains(0, 0), isFalse);
    final page = await cache.get(0, 0);
    expect(page.pageIndex, 0);
    expect(calls, 2);
  });
}
