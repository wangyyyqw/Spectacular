import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_mobile/reader/epub/book_resources.dart';
import 'package:reader_mobile/reader/epub/chapter_positions.dart';
import 'package:reader_mobile/reader/epub/chapter_structure.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import '../../support/test_epub.dart';

class _Structures extends Fake implements ChapterStructureStore {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('连续绘制页眉复用目录，翻章和重排不重建整书目录', () async {
    final source = await EpubChapterSource.open(
      buildMultiChapterEpub(chapters: [for (var i = 0; i < 80; i++) '第$i章正文']),
      verifyCrc: false,
    );
    addTearDown(source.close);
    final toc = source.toc;
    for (var i = 0; i < 20; i++) {
      expect(identical(source.toc, toc), isTrue);
    }
    await source.loadChapter(1);
    await source.applyOverrides(const ReaderOverrides(fontSize: 24));
    expect(identical(source.toc, toc), isTrue);
    expect(() => source.toc.clear(), throwsUnsupportedError);
  });

  test('新发现缺章使目录失效，重复报告复用结果且保留章序', () async {
    final source = await EpubChapterSource.open(
      buildMultiChapterEpub(chapters: ['首章', '中章', '末章']),
      verifyCrc: false,
    );
    addTearDown(source.close);
    final positions = ChapterPositions(
      BookResources(source.document),
      _Structures(),
    );
    final before = positions.toc;
    positions.markMissing(1);
    final after = positions.toc;
    expect(identical(before, after), isFalse);
    expect(after.where((item) => item.spineIndex == 1).single.missing, isTrue);
    expect(after.map((item) => item.spineIndex), orderedEquals([0, 1, 2]));
    positions.markMissing(1);
    expect(identical(after, positions.toc), isTrue);
    positions.close();
  });
}
