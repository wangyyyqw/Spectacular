import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/panels/settings_panel.dart';

/// 真书分页稳定性巡检（REAL_EPUB=1 才跑）。
///
/// 目的是给分页链路（表格/绝对定位/行内图片/浮动）一个有代表性的回归网：
/// 抽样章节逐章分页，检查页数、几何数值、切片边界都合法。真实书体量大，
/// 默认不跑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('抽样章节分页几何合法', () async {
    final file = File('../../test_corpus/real/zhushen-yuxi.epub');
    if (!file.existsSync()) {
      // ignore: avoid_print
      print('SKIP 缺少真书 zhushen-yuxi.epub');
      return;
    }
    final source = await EpubChapterSource.open(
      await file.readAsBytes(),
      contentWidth: 350,
      contentHeight: 700,
      verifyCrc: false,
    );
    await source.applyOverrides(ReaderSettingsDefaults.overrides);

    final chapterCount = source.chapterCount;
    final step = (chapterCount / 24).floor().clamp(1, chapterCount);
    final watch = Stopwatch()..start();
    var chapters = 0;
    var pages = 0;
    var maxPages = 0;

    for (var index = 1; index < chapterCount && chapters < 24; index += step) {
      final chapterPages = await source.loadChapter(index);
      chapters += 1;
      expect(chapterPages, isNotEmpty, reason: '章节 $index 应产出至少一页');
      pages += chapterPages.length;
      maxPages = chapterPages.length > maxPages
          ? chapterPages.length
          : maxPages;
      for (final page in chapterPages) {
        expect(page.pageHeight.isFinite && page.pageHeight > 0, isTrue);
        expect(page.usedHeight.isFinite && page.usedHeight >= 0, isTrue);
        for (final slice in page.slices) {
          expect(slice.height.isFinite && slice.height >= 0, isTrue,
              reason: '章节 $index 出现非法切片高度 ${slice.height}');
          expect(slice.leftInset.isFinite, isTrue);
          expect(slice.absoluteTop == null || slice.absoluteTop!.isFinite, isTrue);
          expect(
            slice.block.layout.lineCount >= 0,
            isTrue,
            reason: '章节 $index 行数为负',
          );
        }
      }
    }
    watch.stop();

    // ignore: avoid_print
    print(
      'P9-20 sweep chapters=$chapters pages=$pages maxPages=$maxPages '
      'ms=${watch.elapsedMilliseconds}',
    );
    expect(chapters, greaterThan(0));
  }, skip: Platform.environment['REAL_EPUB'] != '1');
}
