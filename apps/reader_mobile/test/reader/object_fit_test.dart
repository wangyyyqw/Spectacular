import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

/// W20：`object-fit` 映射为等价 background-size（图片块走背景图绘制）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 4×2 的 PNG（红/蓝各半），用于拿到确定的内在尺寸。
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAABwyOhYAAAAJUlEQVR4nGP4z8Dwn4GB'
    'gYGJgYHhPxMDAwMTAwMDA8N/BgYGAAAvBAH/8vJ4WQAAAABJRU5ErkJggg==',
  );

  Future<(Map<String, String>, double)> imageBoxOf(String css) async {
    final source = await EpubChapterSource.open(
      buildCssChapterBook(
        // 附一段正文：避免单图章走「整页满屏」路径（那条路径固定 cover）。
        body:
            '<div class="box"><img src="../Images/p.png"/></div>'
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
          return (block.style!.values, block.layout.height);
        }
      }
    }
    fail('没有生成图片块');
  }

  Future<Map<String, String>> styleOf(String css) async =>
      (await imageBoxOf(css)).$1;
  double cssPx(String? raw) => double.parse(raw!.replaceFirst('px', ''));

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

  test('object-position 映射为 background-position', () async {
    final values = await styleOf(
      'img { width: 120px; height: 80px; object-fit: cover; '
      'object-position: right bottom; }',
    );
    expect(values['background-position'], 'right bottom');
  });

  test('未声明 object-position 时居中', () async {
    final values = await styleOf(
      'img { width: 120px; height: 80px; object-fit: contain; }',
    );
    expect(values['background-position'], 'center center');
  });

  test('图片块保留 img 自身边距', () async {
    final values = await styleOf(
      'img { width: 120px; height: 80px; margin: 6px 0 2px; }',
    );
    expect(values['margin-top'], '6px');
    expect(values['margin-bottom'], '2px');
  });

  test('aspect-ratio：宽度定高、高度定宽，双显式尺寸不被覆盖', () async {
    final byWidth = await imageBoxOf(
      'img { width: 120px; aspect-ratio: 3/1; }',
    );
    expect(cssPx(byWidth.$1['width']), 120);
    expect(byWidth.$2, 40);

    final byHeight = await imageBoxOf(
      'img { height: 40px; aspect-ratio: 4/1; }',
    );
    expect(cssPx(byHeight.$1['width']), 160);
    expect(byHeight.$2, 40);

    final explicit = await imageBoxOf(
      'img { width: 96px; height: 48px; aspect-ratio: 5/1; }',
    );
    expect(cssPx(explicit.$1['width']), 96);
    expect(explicit.$2, 48);
  });

  test('仅声明高度时，背景与边框收在图片比例宽度内', () async {
    final byHeight = await imageBoxOf('img { height: 40px; }');
    expect(cssPx(byHeight.$1['width']), 80, reason: '4:2 原图按高度推宽');
    expect(byHeight.$2, 40);
  });

  test('max-width 收窄图片盒，高度按原图比例随之收缩', () async {
    final box = await imageBoxOf(
      'img { max-width: 60%; height: auto; display: block; '
      'margin: 0 auto; }',
    );
    expect(cssPx(box.$1['width']), closeTo(192, 0.01));
    expect(box.$2, closeTo(96, 0.01), reason: '宽度 60% 后高度仍保持 4:2');
    expect(cssPx(box.$1['margin-left']), closeTo(64, 0.01));
  });
}
