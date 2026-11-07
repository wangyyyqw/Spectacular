import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('直接设置字体覆盖后计页配置隔离，颜色不切换配置', () async {
    final source = await openCssChapter(body: '<p>${'章节正文' * 80}</p>');
    addTearDown(source.close);
    final pages = await source.loadChapter(0);
    source.setCurrentReadingChapter(0);
    final state = source.pageCountState;
    final originalKey = state.value.layoutKey;
    final chapter = await source.loadAnchorChapter(0);
    final start = chapter.cfiAt(0)!;
    final end = chapter.cfiAt(chapter.text.length, end: true)!;

    expect(
      await source.applyTextOverlays([
        ReaderTextOverlay(startCfi: start, endCfi: end, fontSizeScale: 1.5),
      ]),
      isTrue,
    );
    final changedKey = state.value.layoutKey;
    expect(changedKey, isNot(originalKey));
    expect(state.value.completedChapters, 0);
    final changedPages = await source.loadChapter(0);
    expect(changedPages.length, greaterThan(pages.length));
    source.setPageCountingActive(true);
    expect(state.value.isComplete, isTrue);
    expect(state.value.completedPages, changedPages.length);

    expect(
      await source.applyTextOverlays([
        ReaderTextOverlay(
          startCfi: start,
          endCfi: end,
          fontSizeScale: 1.5,
          color: 0xff112233,
        ),
      ]),
      isFalse,
    );
    expect(state.value.layoutKey, changedKey);
    expect(state.value.status, BookPageCountStatus.complete);
    expect(await source.loadChapter(0), same(changedPages));
  });
}
