import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show BookMeta;
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/paint/hit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('正式引擎保留显式正文动作地址并按字符几何命中', () async {
    final source = EpubChapterSource.fromChapterLoader(
      meta: const BookMeta(
        title: '正文动作回归',
        author: '',
        language: 'zh-CN',
        identifier: 'content-action',
      ),
      chapterTitles: const ['第一章'],
      loadChapterXhtml: (_) async =>
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<p>正文<a href="reader-review:test" data-reader-action="true">〔12〕</a>结尾</p>'
          '<p><a href="https://example.test">普通链接</a></p>'
          '</body></html>',
    );
    addTearDown(() async {
      source.close();
      await source.preparationsStopped;
    });
    await source.applyContentSize(width: 320, height: 580);
    final pages = await source.loadChapter(0);
    final notes = pages
        .expand((page) => page.slices)
        .expand((slice) => slice.block.footnotes)
        .toList();
    expect(notes, hasLength(1));
    expect(notes.single.actionHref, 'reader-review:test');
    final page = pages.firstWhere(
      (page) => page.slices.any((slice) => slice.block.footnotes.isNotEmpty),
    );
    final box = TextHitTester.lineBoxes(page)
        .firstWhere((box) => box.slice.block.footnotes.isNotEmpty);
    final rects = TextHitTester.selectionRects(
      box,
      notes.single.start - box.blockTextOffset,
      notes.single.end - box.blockTextOffset,
    );
    expect(
      TextHitTester.footnoteAt(
        page,
        rects.first.center + box.rect.topLeft,
      )?.actionHref,
      'reader-review:test',
    );
  });
}
