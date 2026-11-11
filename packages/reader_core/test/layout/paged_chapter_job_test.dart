import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paged_chapter_job.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

PageBlock _block(String text, {bool before = false, bool after = false}) =>
    PageBlock(
      layout: TextLayoutEngine.layout(
        text: text,
        style: ComputedStyle(const <String, String>{
          'font-size': '16px',
          'line-height': '1.5',
          'font-family': 'Ahem',
        }),
        maxWidth: 500,
      ),
      pageBreakBefore: before,
      pageBreakAfter: after,
    );

List<PageBlock> _blocks(int count) => <PageBlock>[
  for (var i = 0; i < count; i++) _block('line$i'),
];

void main() {
  test('流式任务逐页产出并可完成', () async {
    final job = PagedChapterJob(blocks: _blocks(4), pageHeight: 48);
    final pages = await job.pages.toList();
    await job.done;
    expect(pages, hasLength(2));
    expect(pages[0].pageIndex, 0);
    expect(pages[1].pageIndex, 1);
    expect(job.progress, 1);
  });

  test('首屏可取前 3 页', () async {
    final job = PagedChapterJob(blocks: _blocks(30), pageHeight: 24);
    final pages = await job.pages.take(3).toList();
    expect(pages, hasLength(3));
    expect(pages.map((page) => page.pageIndex), <int>[0, 1, 2]);
    // take(3) 取消订阅后任务应停止。
    await job.done.timeout(const Duration(seconds: 1));
    expect(job.progress, lessThan(1));
  });

  test('取消后 50ms 内停止', () async {
    final job = PagedChapterJob(blocks: _blocks(5000), pageHeight: 24);
    final iterator = StreamIterator<PageContent>(job.pages);
    expect(await iterator.moveNext(), isTrue);
    expect(job.progress, greaterThan(0));
    job.cancel();
    final watch = Stopwatch()..start();
    await job.done.timeout(const Duration(milliseconds: 50));
    watch.stop();
    expect(watch.elapsedMilliseconds, lessThan(50));
    expect(job.progress, lessThan(1));
    await iterator.cancel();
  });

  test('取消前已产出的页保留', () async {
    final job = PagedChapterJob(blocks: _blocks(100), pageHeight: 24);
    final iterator = StreamIterator<PageContent>(job.pages);
    expect(await iterator.moveNext(), isTrue);
    final first = iterator.current;
    job.cancel();
    await job.done.timeout(const Duration(milliseconds: 50));
    expect(first.slices, isNotEmpty);
    expect(first.pageIndex, 0);
    await iterator.cancel();
  });

  test('pageBreakBefore 在流式任务中生效', () async {
    final job = PagedChapterJob(
      blocks: [_block('a'), _block('b', before: true), _block('c')],
      pageHeight: 48,
    );
    final pages = await job.pages.toList();
    expect(pages, hasLength(2));
    expect(pages[0].slices, hasLength(1));
    expect(pages[1].slices, hasLength(2));
  });
}
