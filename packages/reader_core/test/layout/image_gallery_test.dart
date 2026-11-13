import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/image_gallery.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

PageGalleryFrame _frame(int cell) => PageGalleryFrame(
  cfi: 'epubcfi(/6/2!/4/2/$cell)',
  content: PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: const [],
    usedHeight: 60,
    pageHeight: 60,
    topPadding: 0,
  ),
);

PageBlock _block({String visibility = 'visible'}) {
  final style = ComputedStyle({
    'width': '80px',
    'margin': '10px',
    'padding': '2px',
    'visibility': visibility,
  });
  return PageBlock.styled(
    layout: TextLayoutResult(
      text: '',
      lines: const [
        LineBox(start: 0, end: 0, top: 0, height: 84, baseline: 84, width: 80),
      ],
      width: 80,
      height: 84,
      maxWidth: 80,
    ),
    style: style,
    containingWidth: 100,
    gallery: PageGallery(
      cfi: 'epubcfi(/6/2!/4/2)',
      frames: [_frame(2), _frame(20)],
      left: 12,
      width: 80,
      height: 84,
      indicatorExtent: 24,
    ),
  );
}

PageGalleryFrame _imageFrame(int cell, String imageUrl) {
  final style = ComputedStyle({
    'width': '80px',
    'height': '60px',
    'margin-left': '10px',
    'background-image': 'url($imageUrl)',
  });
  final block = PageBlock.styled(
    layout: TextLayoutResult(
      text: '',
      lines: const [
        LineBox(start: 0, end: 0, top: 0, height: 60, baseline: 60, width: 80),
      ],
      width: 80,
      height: 60,
      maxWidth: 80,
    ),
    style: style,
    containingWidth: 100,
    isReplaced: true,
  );
  return PageGalleryFrame(
    cfi: 'epubcfi(/6/2!/4/2/$cell)',
    imageUrl: imageUrl,
    content: Paginator(pageHeight: 100)
        .measureChapter(blocks: [block])
        .pages
        .single,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('按 CFI 步进匹配图片、题注及范围，不能把 /20 当成 /2 的后代', () {
    final gallery = _block().gallery!;
    expect(gallery.frameIndexForCfi('epubcfi(/6/2!/4/2/20/4/1:8)'), 1);
    expect(gallery.frameIndexForCfi('epubcfi(/6/2!/4/2/2/2)'), 0);
    expect(gallery.frameIndexForCfi('epubcfi(/6/2!/4/2/20,/4/1:2,/4/1:5)'), 1);
    expect(gallery.frameIndexForCfi('epubcfi(/6/4!/4/2/2/2)'), isNull);
    expect(gallery.frameIndexForCfi('epubcfi(/6/2!/4/4/2)'), isNull);
    expect(gallery.frameIndexForCfi('无效位置'), isNull);
  });

  test('命中区使用内容起点，索引重放保留同一画廊与几何', () {
    final block = _block();
    final pages = Paginator(
      pageHeight: 200,
      pageWidth: 100,
      topPadding: 5,
    ).measureChapter(blocks: [block]);
    final region = galleryRegionsOf(pages.pages.single).single;
    expect(region.rect, const Rect.fromLTWH(12, 17, 80, 84));
    final index = PageIndex.from(pages, [block]);
    final replay = PageIndex.apply(index, [block], spineIndex: 0)!;
    expect(galleryRegionsOf(replay.single).single.rect, region.rect);
    expect(replay.single.slices.single.block.gallery, same(block.gallery));
  });

  test('隐藏或折叠画廊保留分页占位，但不接收页内手势', () {
    for (final visibility in ['hidden', 'collapse']) {
      final page = Paginator(pageHeight: 200)
          .measureChapter(blocks: [_block(visibility: visibility)])
          .pages
          .single;
      expect(page.slices.single.block.gallery, isNotNull);
      expect(galleryRegionsOf(page), isEmpty);
    }
  });

  test('主图命中矩形跟随帧缩放，不包含画廊题注与序号空间', () {
    final gallery = PageGallery(
      cfi: 'epubcfi(/6/2!/4/2)',
      frames: [_imageFrame(2, 'image://2'), _imageFrame(20, 'image://20')],
      left: 10,
      width: 80,
      height: 84,
      scale: 0.5,
      indicatorExtent: 24,
    );

    expect(
      galleryImageRectOf(
        gallery,
        1,
        contentOrigin: const Offset(12, 17),
        containingWidth: 100,
      ),
      const Rect.fromLTWH(32, 17, 40, 30),
    );
  });
}
