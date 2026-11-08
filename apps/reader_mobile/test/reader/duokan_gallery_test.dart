import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub/chapter_layout_cache.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

const _css = '''
body, p { margin: 0; }
.duokan-image-gallery { width: 60%; margin: 10px auto; padding: 6px;
  border: 2px solid black; text-align: center; }
.duokan-image-gallery-cell img { width: 100px; height: 60px; }
.duokan-image-maintitle { font-size: 18px; line-height: 1.25; color: #a12345; }
.duokan-image-subtitle { font-size: 12px; line-height: 1.5; }
''';

String _frame(int number, {String extra = '', bool caption = true}) =>
    '''
<div class="duokan-image-gallery-cell" id="frame$number" $extra>
  <img src="../Images/p.png" alt="第 $number 幅插图"/>
  ${caption ? '<p class="duokan-image-maintitle">主标题 $number</p><p class="duokan-image-subtitle">副标题 $number</p>' : ''}
</div>''';

String _gallery(List<String> frames) =>
    '<div class="duokan-image-gallery">${frames.join()}</div>';

Future<EpubChapterSource> _open(
  String body, {
  String css = _css,
  double height = 500,
}) async {
  final source = await openCssChapter(
    body: body,
    css: css,
    contentHeight: height,
    binaryFiles: {
      'OEBPS/Images/p.png': base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7XsAAAAASUVORK5CYII=',
      ),
    },
  );
  addTearDown(source.close);
  return source;
}

PageBlock _galleryBlock(List<PageContent> pages) => pages
    .expand((page) => page.slices)
    .map((slice) => slice.block)
    .where((block) => block.gallery != null)
    .single;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('多帧共用一个分页块，重复图片引用保留各自 CFI 与题注', () async {
    final source = await _open(
      '<p>前文</p>${_gallery([_frame(1), _frame(2), _frame(3)])}<p>后文</p>',
    );
    final pages = await source.loadChapter(0);
    final block = _galleryBlock(pages);
    final gallery = block.gallery!;
    expect(gallery.frames, hasLength(3));
    expect(block.breakInsideAvoid, isTrue);
    expect(gallery.frames.map((frame) => frame.imageUrl).toSet(), hasLength(1));
    expect(gallery.frames.map((frame) => frame.cfi).toSet(), hasLength(3));
    for (var index = 0; index < gallery.frames.length; index++) {
      final text = gallery.frames[index].content.slices
          .map((slice) => slice.block.layout.text)
          .join();
      expect(text, contains('主标题 ${index + 1}'));
      expect(text, contains('副标题 ${index + 1}'));
    }
    expect(
      gallery.contentHeight,
      closeTo(gallery.frames.first.content.usedHeight, 0.01),
    );
    expect(pages, hasLength(1));
    expect(pages.single.slices, hasLength(3));
  });

  test('外层百分比宽、居中、边框及各帧题注样式沿用作者 CSS', () async {
    final source = await _open(_gallery([_frame(1), _frame(2)]));
    final block = _galleryBlock(await source.loadChapter(0));
    final gallery = block.gallery!;
    expect(gallery.width, 180);
    expect(gallery.left + gallery.width / 2, closeTo(150, 0.01));
    expect(block.style!.borders.left.width, 2);
    expect(block.style!.padding.left, 6);
    for (final frame in gallery.frames) {
      final image = frame.content.slices.first.block;
      expect(image.style!.width!.resolve(300), 100);
      expect(image.style!.margin.left + 50, closeTo(150, 0.01));
      final title = frame.content.slices[1].block;
      expect(title.style!.fontSize, 18);
      expect(title.style!.color.toARGB32(), 0xffa12345);
      expect(frame.content.slices[2].block.style!.fontSize, 12);
    }
  });

  test('单帧无题注画廊保留容器，不能误走满屏单图快路径', () async {
    final source = await _open(_gallery([_frame(1, caption: false)]));
    final gallery = _galleryBlock(await source.loadChapter(0)).gallery!;
    expect(gallery.frames, hasLength(1));
    expect(gallery.width, 180);
    expect(gallery.indicatorExtent, 0);
    expect(gallery.height, 60);
  });

  test('隐藏与空分帧不进入画廊，缺失图片仍保留题注与原有占位', () async {
    final source = await _open(
      _gallery([
        _frame(1),
        _frame(2, extra: 'style="display:none"'),
        '<div class="duokan-image-gallery-cell"></div>',
        '<div class="duokan-image-gallery-cell">'
            '<img src="../Images/missing.png" width="100" height="60"/>'
            '<p class="duokan-image-subtitle">缺图题注</p></div>',
      ]),
    );
    final gallery = _galleryBlock(await source.loadChapter(0)).gallery!;
    expect(gallery.frames, hasLength(2));
    expect(gallery.frames.last.imageUrl, endsWith('Images/missing.png'));
    expect(gallery.frames.last.content.slices.last.block.layout.text, '缺图题注');
  });

  test('超过页高的画廊整组等比缩小，所有帧及序号留在同一页', () async {
    final source = await _open(_gallery([_frame(1), _frame(2)]), height: 120);
    final pages = await source.loadChapter(0);
    final gallery = _galleryBlock(pages).gallery!;
    expect(pages, hasLength(1));
    expect(gallery.scale, lessThan(1));
    expect(gallery.scale, greaterThan(0));
    expect(
      pages.single.usedHeight,
      lessThanOrEqualTo(source.contentHeight + 0.01),
    );
    expect(gallery.indicatorExtent, 24);
  });

  test('嵌套画廊缩放时为祖先容器的边框和内边距保留空间', () async {
    final source = await _open(
      '<div style="padding:20px; border:2px solid black">'
      '${_gallery([_frame(1), _frame(2)])}</div>',
      height: 120,
    );
    final pages = await source.loadChapter(0);
    expect(pages, hasLength(1));
    expect(
      pages.single.usedHeight,
      lessThanOrEqualTo(source.contentHeight + 0.01),
    );
    expect(_galleryBlock(pages).gallery!.scale, greaterThan(0));
  });

  test('画廊和分帧的作者透明度按祖先链累计一次', () async {
    final source = await _open(
      _gallery([_frame(1), _frame(2)]),
      css:
          '$_css .duokan-image-gallery { opacity:0.5; } '
          '.duokan-image-gallery-cell { opacity:0.4; }',
    );
    final block = _galleryBlock(await source.loadChapter(0));
    expect(block.style!.effectiveOpacity, 0.5);
    expect(block.effectiveOpacity, 0.5);
    for (final frame in block.gallery!.frames) {
      expect(
        frame.content.slices.first.block.effectiveOpacity,
        closeTo(0.2, 0.001),
      );
    }
  });

  test('结构不符合分帧规范时保持普通内容，不误吞正文', () async {
    final source = await _open(
      '<div class="duokan-image-gallery">'
      '${_frame(1)}<p>额外正文</p>${_frame(2)}</div>',
    );
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block);
    expect(blocks.any((block) => block.gallery != null), isFalse);
    expect(blocks.map((block) => block.layout.text).join(), contains('额外正文'));
  });

  test('缓存容量估算包含未显示帧，边距折叠不会丢失画廊载荷', () async {
    final source = await _open('<p>前文</p>${_gallery([_frame(1), _frame(2)])}');
    final pages = await source.loadChapter(0);
    final block = _galleryBlock(pages);
    expect(block.withSpacing(spaceBefore: 2).gallery, same(block.gallery));
    final all = estimateLayoutBytes(pages, [block], const []);
    final frame = block.gallery!.frames.first.content;
    final first = estimateLayoutBytes([frame], const [], const []);
    expect(all, greaterThan(first * 1.5));
  });
}
