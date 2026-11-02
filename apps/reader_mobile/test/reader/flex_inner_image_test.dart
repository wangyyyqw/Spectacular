import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Flex 内层图片按自身百分比宽度绘制', () async {
    final file = File('../../test_corpus/real/shiji-yuewei.epub');
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      verifyCrc: false,
    );
    await source.applyContentSize(width: 320, height: 640);

    final pages = await source.loadChapter(1);
    final flexBlock = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .firstWhere((block) => block.table?.flex ?? false);
    final imageCell = flexBlock.table!.cells.firstWhere(
      (cell) => cell.style.backgroundImage == 'OEBPS/Images/cover.png',
    );

    expect(
      imageCell.rect.width,
      closeTo(104.4, 0.1),
      reason: 'width:40% 的 102.4px 内容宽 + 左右 1px 边框',
    );
    expect(imageCell.rect.width, lessThan(flexBlock.table!.tableWidth / 2));
  });
}
