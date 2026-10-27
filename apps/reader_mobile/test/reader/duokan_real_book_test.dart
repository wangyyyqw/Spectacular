import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// 真实书的多看私有属性落点（需求 2）：`duokan-text-indent` 是书里最高频的
/// 私有属性（7 本真实书共 1527 次），必须真的变成段落首行缩进。
///
/// 语料缺失时跳过（CI 不带 test_corpus）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真书：duokan-text-indent 生效为首行缩进', () async {
    final file = File('../../test_corpus/real/zhushen-yuxi.epub');
    if (!file.existsSync()) {
      return;
    }
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      contentWidth: 390,
      contentHeight: 873,
      verifyCrc: false,
    );
    var found = 0;
    for (var spine = 0; spine < 40 && found == 0; spine++) {
      final pages = await source.loadChapter(spine);
      for (final page in pages) {
        for (final slice in page.slices) {
          final style = slice.block.style;
          if (style == null) {
            continue;
          }
          // 私有属性值为 2em（32px 上下文）时首行缩进应显著非零。
          // 书里 duokan-text-indent: 2em → 17px 上下文约 34px。
          if (style.textIndent > 20 && style.values.containsKey('text-indent')) {
            found = 1;
            expect(style.textIndent, greaterThan(20));
            expect(slice.block.layout.text.length, greaterThan(0));
            break;
          }
        }
        if (found == 1) break;
      }
    }
    expect(found, 1, reason: '前 40 章里应至少有一个 duokan-text-indent 段落');
  });
}
