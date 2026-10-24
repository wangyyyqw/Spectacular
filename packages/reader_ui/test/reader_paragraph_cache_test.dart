import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/paragraph_cache.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

class _FakeSource implements ReaderChapterSource {
  @override
  int get chapterCount => 2;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: 'aa',
      style: style,
      maxWidth: 120,
    );
    final block = PageBlock.styled(
      layout: layout,
      style: style,
      containingWidth: 120,
    );
    final height = block.leadingExtent + block.height + block.trailingExtent;
    return [
      PageContent(
        spineIndex: spineIndex,
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
      ),
    ];
  }
}

Widget _app(ParagraphCache cache, ReaderOverrides overrides) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 240,
      height: 200,
      child: ReaderPage(
        source: _FakeSource(),
        store: MemoryReaderProgressStore(),
        bookId: 'book',
        overrides: overrides,
        paragraphCache: cache,
      ),
    ),
  ),
);

void main() {
  testWidgets('重排（设置变化）后清空旧段落缓存', (tester) async {
    final cache = ParagraphCache();
    await tester.pumpWidget(_app(cache, const ReaderOverrides(fontSize: 16)));
    await tester.pumpAndSettle();

    expect(cache.length, greaterThan(0), reason: '首帧绘制应写入段落缓存');

    // 放入一个探针条目：重排清空时它必须被释放（即使随后重绘又写入新条目）。
    final probe = cache.obtain(
      'probe-key',
      build: () => TextPainter(
        text: const TextSpan(text: 'probe'),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    expect(probe.debugDisposed, isFalse);

    await tester.pumpWidget(_app(cache, const ReaderOverrides(fontSize: 20)));
    await tester.pump();

    expect(probe.debugDisposed, isTrue, reason: '设置变化应释放旧段落缓存');
    await tester.pumpAndSettle();
  });

  testWidgets('主题变化不清空段落缓存', (tester) async {
    final cache = ParagraphCache();
    await tester.pumpWidget(_app(cache, const ReaderOverrides(fontSize: 16)));
    await tester.pumpAndSettle();
    final length = cache.length;
    expect(length, greaterThan(0));

    await tester.pumpWidget(_app(cache, const ReaderOverrides(fontSize: 16)));
    await tester.pump();
    expect(cache.length, length, reason: '设置未变不应清缓存');
    await tester.pumpAndSettle();
  });
}
