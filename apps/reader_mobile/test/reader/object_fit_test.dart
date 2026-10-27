import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

/// W20：`object-fit` 映射为等价 background-size（图片块走背景图绘制）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 4×2 的 PNG（红/蓝各半），用于拿到确定的内在尺寸。
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAABwyOhYAAAAJUlEQVR4nGP4z8Dwn4GB'
    'gYGJgYHhPxMDAwMTAwMDA8N/BgYGAAAvBAH/8vJ4WQAAAABJRU5ErkJggg==',
  );

  Future<Map<String, String>> styleOf(String css) async {
    final source = await EpubChapterSource.open(
      buildCssChapterBook(
        // 附一段正文：避免单图章走「整页满屏」路径（那条路径固定 cover）。
        body: '<div class="box"><img src="../Images/p.png"/></div>'
            '<p>正文一段，避免整页满屏。</p>',
        css: '.box { width: 120px; } $css',
        binaryFiles: {'OEBPS/Images/p.png': png},
      ),
      verifyCrc: false,
    );
    final pages = await source.loadChapter(0);
    for (final page in pages) {
      for (final slice in page.slices) {
        final block = slice.block;
        if (block.style?.backgroundImage != null) {
          return block.style!.values;
        }
      }
    }
    fail('没有生成图片块');
  }

  test('object-fit: cover → background-size cover', () async {
    final values = await styleOf(
      'img { width: 120px; height: 80px; object-fit: cover; }',
    );
    expect(values['background-size'], 'cover');
  });

  test('object-fit: contain → background-size contain', () async {
    final values = await styleOf(
      'img { width: 120px; height: 80px; object-fit: contain; }',
    );
    expect(values['background-size'], 'contain');
  });

  test('object-fit: fill → background-size 100% 100%', () async {
    final values = await styleOf(
      'img { width: 120px; height: 80px; object-fit: fill; }',
    );
    expect(values['background-size'], '100% 100%');
  });
}
