import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/epub/chapter/book_progress.dart';

void main() {
  test('纯图位置只使用真实图片叶，零偏移等价于元素位置', () {
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
    );
    expect(positions.ratioFor(parent), isNull);
    expect(positions.ratioFor('epubcfi(/6/2!/4/4:0)'), isNull);
    expect(positions.ratioFor('epubcfi(/6/2!/4/4/2:0)'), 1);
    expect(positions.ratioFor('epubcfi(/6/2!/4/4:1)'), isNull);
    expect(positions.cfiFor(1), second);
    expect(positions.cfiFor(0), first);
  });
}
