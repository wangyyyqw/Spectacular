import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

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

PageContent _page() {
  final style = _style();
  final layout = TextLayoutEngine.layout(
    text: 'aa',
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

void main() {
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
}
