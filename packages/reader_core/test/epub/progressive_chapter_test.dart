import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/epub/chapter/container_blocks.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

String _prose([int count = 120]) => List.generate(
  count,
  (index) => '<p>第 $index 段：${'稳定边界保留真实后继与原文坐标。' * 8}</p>',
).join();

Future<EpubChapterSource> _source(String body, {String css = ''}) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">渐进章节</dc:identifier>'
          '<dc:title>渐进章节回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body{margin:0}p{margin:0 0 10px;font-size:18px;line-height:1.6}$css'
          '</style></head><body>$body</body></html>',
    }),
    options: const ReaderOpenOptions(
      contentWidth: 366.6666666666667,
      contentHeight: 773.1694444444443,
    ),
  );
  addTearDown(() async {
    source.close();
    await source.preparationsStopped;
  });
  await source.applyContentSize(
    width: 366.6666666666667,
    height: 773.1694444444443,
    topInset: 56.075,
    sideInsets: (left: 8.8, right: 8.53333333333336),
  );
  return source;
}

Object _geometry(PageContent page) => [
  page.usedHeight,
  page.pageHeight,
  page.topPadding,
  page.background,
  for (final slice in page.slices)
    [
      slice.block.startCfi,
      slice.block.layout.text,
      slice.startLine,
      slice.endLine,
      slice.height,
      slice.leadingExtent,
      slice.trailingExtent,
      slice.leftInset,
      slice.textTopTrim,
      slice.textBottomTrim,
      slice.absoluteTop,
      slice.overlay,
      for (final line in slice.lines)
        [
          line.start,
          line.end,
          line.top,
          line.height,
          line.width,
          line.baseline,
        ],
      for (final fragment in slice.block.containers)
        [
          fragment.startsHere,
          fragment.endsHere,
          fragment.topInset,
          fragment.bottomInset,
        ],
    ],
];

// 页索引重放的高度累加顺序可能产生浮点末位差异，文本与页界仍严格比较。
Object? _indexedGeometryExpectation(Object? value) {
  if (value is double) return closeTo(value, 1e-9);
  if (value is List) return value.map(_indexedGeometryExpectation).toList();
  return value;
}

PageBlock _box(
  String text,
  double height, {
  bool avoid = false,
  double after = 0,
}) => PageBlock(
  layout: TextLayoutResult(
    text: text,
    lines: [
      LineBox(
        start: 0,
        end: text.length,
        top: 0,
        height: height,
        baseline: height,
        width: 10,
      ),
    ],
    width: 10,
    height: height,
    maxWidth: 100,
  ),
  spaceAfter: after,
  breakAfterAvoid: avoid,
  style: ComputedStyle(const {'font-size': '10px'}),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('正式引擎先交付稳定首页，完整消费者接管同一作业且页面不回变', () async {
    final body = '<h3>章节标题</h3>${_prose()}';
    final source = await _source(body);
    final baseline = await _source(body);
    final expected = await baseline.loadChapter(0);
    final handle = source.scheduleProgressiveChapter(
      0,
      priority: ChapterLayoutPriority.prefetch,
    );
    final first = await handle.firstPages;
    expect(first, isNotEmpty);
    expect(first.length, lessThan(expected.length));
    expect(handle.isComplete, isFalse);
    expect(handle.priority, ChapterLayoutPriority.background);
    expect(source.chapterLayoutCount, 1);
    expect(first.map(_geometry), expected.take(first.length).map(_geometry));
    final batches = <List<PageContent>>[first];
    final subscription = handle.updates.listen(batches.add);
    final complete = await source.loadChapter(0);
    await subscription.cancel();
    expect(source.chapterLayoutCount, 1, reason: '前台接管不重新构块');
    expect(complete.map(_geometry), expected.map(_geometry));
    for (final batch in batches) {
      for (var index = 0; index < batch.length; index++) {
        expect(complete[index], same(batch[index]));
      }
    }
    expect(await source.loadChapter(0), same(complete), reason: '只缓存完整结果');
    source.clearPaginationCache();
    final replay = await source.loadChapter(0);
    expect(
      replay.map(_geometry),
      expected.map(_geometry).map(_indexedGeometryExpectation),
      reason: '稳定块进入完整页索引后仍可准确重放',
    );
    expect(source.chapterLayoutCount, 1);
  });

  test('avoid 后继单行的末边距未稳定时不能因已有两页就发布首页', () async {
    final prefix = [
      _box('正文', 70),
      _box('标题', 10, avoid: true),
      _box('后继', 10, after: 20),
    ];
    final paginator = Paginator(
      pageHeight: 100,
      tolerance: 0,
      trimTextEdges: false,
    );
    final unsafe = paginator.measureChapter(blocks: prefix).pages;
    expect(unsafe, hasLength(2));
    expect(unsafe.first.slices.map((slice) => slice.block.layout.text), ['正文']);
    final blocks = collapseMarginsIgnoringFloats(prefix);
    final stable = await paginator
        .paginate(
          blocks: blocks,
          stableBlockCount: stableMarginPrefixLength(blocks),
        )
        .toList();
    expect(stable, isEmpty);
    final appended = collapseMarginsIgnoringFloats([
      ...prefix,
      _box('新段', 30),
      _box('再后继', 30),
    ]);
    final pages = await paginator
        .paginate(
          blocks: appended,
          stableBlockCount: stableMarginPrefixLength(appended),
        )
        .toList();
    expect(pages.first.slices.map((slice) => slice.block.layout.text), [
      '正文',
      '标题',
      '后继',
    ]);
    expect(
      _geometry(pages.first),
      _geometry(paginator.measureChapter(blocks: appended).pages.first),
    );
  });

  for (final content in [
    (
      '空块边距链',
      '<h3>标题</h3><p>${'前文。' * 100}</p><div style="margin:30px 0 -10px"></div><div style="margin:50px 0"></div>${_prose(30)}',
    ),
    (
      '普通闭合容器',
      '<div style="padding:10px"><h3>标题</h3>${_prose(8)}</div>${_prose(30)}',
    ),
    ('后文续框容差', '${_prose(30)}<div style="border:1px solid"><p>框内正文</p></div>'),
    (
      '带框闭合容器',
      '<div style="border:1px solid;padding:10px"><h3>标题</h3>${_prose(8)}</div>${_prose(30)}',
    ),
    (
      '表格与避免断页',
      '<p>${'前文。' * 100}</p><h3 style="break-after:avoid">表标题</h3><table><tr><td>单行</td></tr><tr><td>下一行</td></tr></table>${_prose(30)}',
    ),
  ]) {
    test('正式引擎渐进首页与完整结果一致：${content.$1}', () async {
      final source = await _source(content.$2);
      final baseline = await _source(content.$2);
      final expected = await baseline.loadChapter(0);
      final handle = source.scheduleProgressiveChapter(0);
      final first = await handle.firstPages;
      expect(first.map(_geometry), expected.take(first.length).map(_geometry));
      handle.setPriority(ChapterLayoutPriority.reading);
      expect((await handle.result).map(_geometry), expected.map(_geometry));
    });
  }

  for (final tail in [
    ('浮动', '<p style="float:right;width:80px">浮动</p>'),
    ('固定覆盖', '<p style="position:fixed;top:0">固定覆盖</p>'),
    ('竖排', '<p style="writing-mode:vertical-rl;height:120px">竖排</p>'),
    ('多栏', '<div style="column-count:2">多栏正文</div>'),
  ]) {
    test('后文全章布局特征回退完整入口：${tail.$1}', () async {
      final source = await _source('${_prose(30)}${tail.$2}');
      final handle = source.scheduleProgressiveChapter(0);
      final first = await handle.firstPages;
      expect(handle.isComplete, isTrue);
      expect(await handle.result, same(first));
    });
  }

  test('首页交付后取消余章，不提交残缺缓存且可重新加载', () async {
    final source = await _source(_prose());
    final handle = source.scheduleProgressiveChapter(0);
    final first = await handle.firstPages;
    expect(handle.isComplete, isFalse);
    handle.cancel();
    await expectLater(handle.result, throwsA(isA<ChapterLoadCancelled>()));
    final full = await source.loadChapter(0);
    expect(full.length, greaterThan(first.length));
    expect(source.chapterLayoutCount, 2);
    expect(full.take(first.length).map(_geometry), first.map(_geometry));
  });

  test('首页交付后重排取消旧余章，只提交新字号的完整结果', () async {
    final source = await _source(_prose());
    final old = source.scheduleProgressiveChapter(0);
    await old.firstPages;
    await source.applyOverrides(const ReaderOverrides(fontSize: 22));
    await expectLater(old.result, throwsA(isA<ChapterLoadCancelled>()));
    final pages = await source.loadChapter(0);
    expect(pages.first.slices.first.block.style!.fontSize, 22);
    expect(source.chapterLayoutCount, 2);
  });
}
