import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_mobile/reader/epub/book_progress.dart';

void main() {
  test('纯图位置兼容旧折叠父 CFI 与零偏移，输出始终是真实叶', () {
    const first = 'epubcfi(/6/2!/4/2/2)';
    const second = 'epubcfi(/6/2!/4/4/2)';
    const parent = 'epubcfi(/6/2!/4/4)';
    final positions = ChapterTextCoordinates(
      AnchorChapter(
        spineIndex: 0,
        href: 'chapter.xhtml',
        title: '',
        readable: true,
        blocks: [],
      ),
      elementCfis: [first, second],
      legacyAliases: {parent: second},
    );
    expect(positions.ratioFor(parent), 1);
    expect(positions.ratioFor('epubcfi(/6/2!/4/4:0)'), 1);
    expect(positions.ratioFor('epubcfi(/6/2!/4/4/2:0)'), 1);
    expect(positions.ratioFor('epubcfi(/6/2!/4/4:1)'), isNull);
    expect(positions.cfiFor(1), second);
    expect(positions.cfiFor(0), first);
  });
}
