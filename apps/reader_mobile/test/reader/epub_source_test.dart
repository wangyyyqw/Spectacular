import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

void main() {
  final file = File('../../test_corpus/real/zhushen-yuxi.epub');
  final skip = file.existsSync() ? null : '本地样本库缺失（test_corpus/ 不入库）';

  test(
    '真实 EPUB 打开后可按章加载非空页',
    () async {
      final source = await EpubChapterSource.open(
        await file.readAsBytes(),
        contentWidth: 320,
        contentHeight: 480,
      );
      expect(source.chapterCount, greaterThan(0));
      final index = source.chapterCount > 50 ? 50 : 0;
      final pages = await source.loadChapter(index);
      expect(pages, isNotEmpty);
      expect(pages.every((page) => page.slices.isNotEmpty), isTrue);
      final text = pages.first.slices
          .expand(
            (slice) => slice.block.layout.lines
                .skip(slice.startLine)
                .take(slice.endLine - slice.startLine),
          )
          .map((line) => line)
          .toList();
      expect(text, isNotEmpty);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
