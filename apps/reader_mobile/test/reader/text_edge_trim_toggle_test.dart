import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

const _css =
    'body { margin: 0; padding: 0; font-family: "builtin_song"; '
    'font-size: 17px; } p { margin: 6px 0; line-height: 1.8; }';

Future<EpubChapterSource> _open({required bool trimTextEdges}) async {
  final source = await EpubChapterSource.open(
    buildCssChapterBook(body: '<p>下划线 underline</p>', css: _css),
    contentWidth: 350,
    contentHeight: 800,
    verifyCrc: false,
    trimTextEdges: trimTextEdges,
  );
  await source.applyOverrides(const ReaderOverrides());
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('阅读模式默认回收页首行高留白', () async {
    final source = await _open(trimTextEdges: true);
    final slice = (await source.loadChapter(0)).single.slices.single;

    expect(slice.textTopTrim, greaterThan(0));
    expect(
      slice.leadingExtent,
      closeTo(slice.block.leadingExtent - slice.textTopTrim, 0.01),
    );
  });

  test('关闭裁边后保留浏览器同口径的完整块顶', () async {
    final source = await _open(trimTextEdges: false);
    final slice = (await source.loadChapter(0)).single.slices.single;

    expect(slice.textTopTrim, 0);
    expect(slice.leadingExtent, closeTo(slice.block.leadingExtent, 0.01));
  });
}
