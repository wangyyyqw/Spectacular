import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'background-image': 'url(bg://one)',
});

class _FakeSource implements ReaderChapterSource {
  _FakeSource(this.page);

  final PageContent page;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [page];
}

class _PagesSource implements ReaderChapterSource {
  _PagesSource(this.pages);

  final List<PageContent> pages;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => pages;
}

PageContent _imagePage(int pageIndex, String url) {
  final style = ComputedStyle(<String, String>{
    'font-size': '16px',
    'line-height': '1.5',
    'font-family': 'Ahem',
    'background-image': 'url($url)',
  });
  final layout = TextLayoutEngine.layout(
    text: '图片页',
    style: style,
    maxWidth: 100,
  );
  final block = PageBlock.styled(
    layout: layout,
    style: style,
    containingWidth: 100,
  );
  final height = block.leadingExtent + block.height + block.trailingExtent;
  return PageContent(
    spineIndex: 0,
    pageIndex: pageIndex,
    slices: [
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: layout.lineCount,
        height: height,
      ),
    ],
    usedHeight: height,
    pageHeight: 200,
    topPadding: 0,
  );
}

PageContent _page({bool containerBackground = false}) {
  final style = containerBackground ? ComputedStyle({}) : _style();
  final layout = TextLayoutEngine.layout(
    text: 'aa',
    style: style,
    maxWidth: 100,
  );
  var block = PageBlock.styled(
    layout: layout,
    style: style,
    containingWidth: 100,
  );
  if (containerBackground) {
    block = block.withSpacing(
      containers: [
        PageContainerFragment(
          container: PageContainer(style: _style(), left: 0, width: 100),
          startsHere: true,
          endsHere: true,
        ),
      ],
    );
  }
  final height = block.leadingExtent + block.height + block.trailingExtent;
  return PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: [
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: layout.lineCount,
        height: height,
      ),
    ],
    usedHeight: height,
    pageHeight: 200,
    topPadding: 0,
  );
}

PageContent _tableImagePage() {
  final pageStyle = ComputedStyle(const <String, String>{
    'font-size': '16px',
    'line-height': '1.5',
  });
  final cellStyle = _style();
  final cellLayout = TextLayoutEngine.layout(
    text: '',
    style: cellStyle,
    maxWidth: 60,
  );
  final block = PageBlock(
    layout: TextLayoutEngine.layout(text: '', style: pageStyle, maxWidth: 100),
    style: pageStyle,
    table: TableRenderSpec(
      cells: <TableCellRender>[
        TableCellRender(
          row: 0,
          rect: const Rect.fromLTWH(20, 0, 60, 60),
          layout: cellLayout,
          style: cellStyle,
        ),
      ],
      columnXs: const <double>[0, 100],
      rowYs: const <double>[0, 60],
      tableWidth: 100,
      flex: true,
    ),
  );
  return PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: <PageBlockSlice>[
      PageBlockSlice(block: block, startLine: 0, endLine: 1, height: 60),
    ],
    usedHeight: 60,
    pageHeight: 200,
    topPadding: 0,
  );
}

void main() {
  testWidgets('ReaderPage 沿用行内图片元数据预取装饰盒图片', (tester) async {
    final image = PageBlock.styled(
      layout: TextLayoutResult(
        text: '',
        lines: const [],
        width: 60,
        height: 20,
        maxWidth: 60,
      ),
      style: _style(),
      containingWidth: 100,
    );
    final style = ComputedStyle({'font-size': '16px'});
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: '标题',
        style: style,
        maxWidth: 300,
        inlineBoxes: [
          InlineBoxSpec(offset: 0, width: 60, height: 20, payload: image),
        ],
      ),
      style: style,
      containingWidth: 300,
      inlineImages: const [InlineImageSpec(offset: 0, url: 'bg://one')],
    );
    final page = Paginator(pageHeight: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final requested = <String>[];
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        requested.add(url);
        return null;
      },
    );
    addTearDown(cache.clear);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _FakeSource(page),
          store: MemoryReaderProgressStore(),
          bookId: 'inline-image-book',
          imageCache: cache,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(requested, contains('bg://one'));
  });

  testWidgets('ReaderPage 使用注入的图片缓存并预取背景图', (tester) async {
    var loaderCalls = 0;
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        loaderCalls += 1;
        return null; // 不解码：只验证宿主接线与预取调用
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _FakeSource(_page()),
          store: MemoryReaderProgressStore(),
          bookId: 'book',
          imageCache: cache,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(loaderCalls, greaterThan(0), reason: '背景图 URL 被交给宿主加载器');
  });

  testWidgets('ReaderPage 预取 Flex 图片单元格的背景图', (tester) async {
    final requested = <String>[];
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        requested.add(url);
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _FakeSource(_tableImagePage()),
          store: MemoryReaderProgressStore(),
          bookId: 'table-image-book',
          imageCache: cache,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(requested, contains('bg://one'));
  });

  testWidgets('ReaderPage 预取独立容器上的背景图', (tester) async {
    final requested = <String>[];
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        requested.add(url);
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _FakeSource(_page(containerBackground: true)),
          store: MemoryReaderProgressStore(),
          bookId: 'container-book',
          imageCache: cache,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(requested, contains('bg://one'));
  });

  testWidgets('仿真翻页预热邻页图片后再显示目标页', (tester) async {
    final requested = <String>[];
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        requested.add(url);
        return null;
      },
    );
    addTearDown(cache.clear);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _PagesSource([_page(), _imagePage(1, 'bg://next')]),
          store: MemoryReaderProgressStore(),
          bookId: 'turn-image-book',
          imageCache: cache,
          pageTurnMode: PageTurnMode.simulationBessel,
        ),
      ),
    );
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      requested,
      contains('bg://next'),
      reason: '邻页图片在翻页前完成预取，避免目标页先白屏再补图',
    );
  });

  testWidgets('连续滚动预取已构建的下一屏图片', (tester) async {
    final requested = <String>[];
    final cache = DecodedImageCache(
      loadBytes: (url) async {
        requested.add(url);
        return null;
      },
    );
    addTearDown(cache.clear);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _PagesSource([_page(), _imagePage(1, 'bg://scroll-next')]),
          store: MemoryReaderProgressStore(),
          bookId: 'scroll-image-book',
          imageCache: cache,
          pageTurnMode: PageTurnMode.scroll,
        ),
      ),
    );
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      requested,
      contains('bg://scroll-next'),
      reason: '下一屏已进入构建区时就应预取，而不是等它成为当前页',
    );
  });
}
