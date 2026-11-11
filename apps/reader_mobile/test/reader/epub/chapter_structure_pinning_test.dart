import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/chapter/book_fonts.dart';
import 'package:reader_core/epub/chapter/book_resources.dart';
import 'package:reader_core/epub/chapter/chapter_structure.dart';
import 'package:reader_core/epub/chapter/chapter_styles.dart';

import '../../support/test_epub.dart';
import 'package:reader_core/source/chapter_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BookResources resources;
  late BookFonts fonts;
  late ChapterStyles styles;
  late ChapterStructureStore structures;

  setUp(() async {
    final document = (await openEpub(
      buildMultiChapterEpub(
        chapters: [for (var i = 0; i < 6; i++) '第 ${i + 1} 章正文'],
      ),
      verifyCrc: false,
    )).document!;
    resources = BookResources(document);
    fonts = BookFonts(resources, onFontsChanged: (_) {});
    styles = ChapterStyles(resources, fonts);
    structures = ChapterStructureStore(
      resources,
      styles,
      ComputedStyle(const {'font-size': '16px'}),
    );
  });

  tearDown(() async {
    structures.close();
    styles.close();
    fonts.close();
    resources.close();
    await structures.preparationsStopped;
    await styles.preparationsStopped;
    await resources.preparationsStopped;
    expect(resources.preparationWorker.activeIsolates, 0);
    expect(resources.preparationWorker.openPortCount, 0);
  });

  test('后台预取写满容量时仍保留当前阅读章结构', () async {
    const width = 320.0;
    final current = await structures
        .schedule(3, width, priority: ChapterLayoutPriority.reading)
        .result;
    expect(structures.preparations, 1);

    for (final spine in [0, 1, 2]) {
      await structures
          .schedule(spine, width, priority: ChapterLayoutPriority.background)
          .result;
    }
    expect(structures.length, ChapterStructureStore.capacity);
    expect(structures.preparations, 4);

    final reopened = await structures
        .schedule(3, width, priority: ChapterLayoutPriority.reading)
        .result;
    expect(reopened, same(current));
    expect(structures.preparations, 4, reason: '当前章结构不应被后台写入淘汰');
  });

  test('切换阅读章后旧章可淘汰，新章保持命中', () async {
    const width = 320.0;
    await structures
        .schedule(3, width, priority: ChapterLayoutPriority.reading)
        .result;
    final next = await structures
        .schedule(0, width, priority: ChapterLayoutPriority.reading)
        .result;
    for (final spine in [1, 2, 4]) {
      await structures
          .schedule(spine, width, priority: ChapterLayoutPriority.background)
          .result;
    }

    expect(structures.length, ChapterStructureStore.capacity);
    expect(
      await structures
          .schedule(0, width, priority: ChapterLayoutPriority.reading)
          .result,
      same(next),
    );
    expect(structures.preparations, 5);
  });
}
