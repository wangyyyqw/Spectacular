import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

/// `border-image` 在章节源里要做的两件事：解析成 `CssBorderImage`，并把相对
/// URL 解算成书内路径（绘制层按这个路径查图）。真书用它的形态是
/// `border: 20px solid transparent; border-image: url(../Images/xbt2.png) 50 50 repeat`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('border-image URL 解算为书内路径并带上切割量', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAABwyOhYAAAAJUlEQVR4nGP4z8Dwn4GB'
      'gYGJgYHhPxMDAwMTAwMDA8N/BgYGAAAvBAH/8vJ4WQAAAABJRU5ErkJggg==',
    );
    final source = await EpubChapterSource.open(
      buildCssChapterBook(
        body: '<div class="frame"></div><p>正文</p>',
        css: '.frame { width: 100px; height: 100px; '
            'border: 20px solid transparent; '
            'border-image: url("../Images/f.png") 50 50 repeat; }',
        binaryFiles: {'OEBPS/Images/f.png': png},
      ),
      verifyCrc: false,
    );
    final pages = await source.loadChapter(0);
    final blocks = <PageBlock>[
      for (final page in pages)
        for (final slice in page.slices) slice.block,
    ];
    final withBorderImage = blocks.firstWhere(
      (block) => block.style?.borderImage != null,
      orElse: () => throw StateError('没有生成 border-image 块'),
    );
    final spec = withBorderImage.style!.borderImage!;
    expect(
      spec.url.toLowerCase(),
      contains('images/f.png'),
      reason: '相对 URL 应解算为书内路径（zip 条目小写化）',
    );
    expect(spec.sliceTop, 50);
    expect(spec.repeat, CssBorderImageRepeat.repeat);
  });
}
