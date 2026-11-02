import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Flex 版权卡片保留图片宽度、背景、底部说明和垂直居中', () async {
    final file = File('../../test_corpus/real/shiji-yuewei.epub');
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      verifyCrc: false,
    );
    await source.applyOverrides(
      const ReaderOverrides(fontSize: 17, lineHeight: 1.6),
    );
    await source.applyContentSize(width: 320, height: 640);

    final pages = await source.loadChapter(1);
    final flexBlock = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .firstWhere((block) => block.table?.flex ?? false);
    final cells = flexBlock.table!.cells;
    final imageCell = cells.firstWhere(
      (cell) => cell.style.backgroundImage == 'OEBPS/Images/cover.png',
    );
    final cardCell = cells.firstWhere(
      (cell) =>
          cell.style.backgroundColor.toARGB32() == 0xFFBDBBBE &&
          cell.layout.lineCount == 0,
    );
    final footerCell = cells.firstWhere(
      (cell) => cell.layout.text.contains('本书排版仅适配阅微app'),
    );
    final titleCell = cells.firstWhere(
      (cell) => cell.layout.text.contains('书名：史记'),
    );

    expect(
      imageCell.rect.width,
      closeTo(104.4, 0.1),
      reason: 'width:40% 的 102.4px 内容宽 + 左右 1px 边框',
    );
    expect(imageCell.rect.width, lessThan(flexBlock.table!.tableWidth / 2));
    expect(cardCell.rect.width, closeTo(flexBlock.table!.tableWidth * 0.8, 0.1));
    expect(footerCell.rect.bottom, lessThanOrEqualTo(flexBlock.height));
    expect(footerCell.style.fontSize, closeTo(11.9, 0.01));
    expect(titleCell.style.fontSize, closeTo(16.15, 0.01));
    expect(footerCell.style.fontSize, lessThan(titleCell.style.fontSize * 0.8));
    expect(
      cardCell.rect.top,
      closeTo(flexBlock.height - cardCell.rect.bottom, 0.1),
      reason: 'flex align-items:center 应让版权卡片上下留白相等',
    );
  });
}
