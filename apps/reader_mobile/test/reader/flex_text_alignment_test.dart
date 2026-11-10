import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final align in ['left', 'center', 'right', 'start', 'end']) {
    for (final direction in ['ltr', 'rtl']) {
      test('Flex 自然宽文字保持 $direction $align 及行内字号', () async {
        final source = await openCssChapter(
          body: '<div><h1>ABCD<br/><span>AB</span></h1></div>',
          css:
              'body {margin:0;} div {display:flex;justify-content:center;} '
              'h1 {margin:0;max-width:80%;padding:10px;border:2px solid red; '
              'font:20px/1.5 Ahem;text-indent:0;text-align:$align;direction:$direction;} '
              'span {font-size:.5em;}',
          contentWidth: 350,
        );
        addTearDown(source.close);
        final pages = await source.loadChapter(0);
        final cell = pages.single.slices.single.block.table!.cells.single;
        expect(cell.rect.width, closeTo(104, .01));
        expect(cell.rect.center.dx, closeTo(175, .01));
        expect(cell.layout.maxWidth, closeTo(80, .01));
        expect(cell.layout.lines, hasLength(2));
        expect(
          cell.layout.runs
              .where((run) => run.start <= 5 && run.end >= 7)
              .single
              .style
              .fontSize,
          10,
        );
        expect(cell.layout.lines.first.offsetX, closeTo(0, .01));
        final right =
            align == 'right' ||
            (align == 'start' && direction == 'rtl') ||
            (align == 'end' && direction == 'ltr');
        final shortOffset = align == 'center' ? 30.0 : (right ? 60.0 : 0.0);
        expect(cell.layout.lines.last.offsetX, closeTo(shortOffset, .01));
        expect(cell.layout.lines.map((line) => line.height), [30, 15]);
        expect(cell.layout.height, closeTo(45, .01));
      });
    }
  }

  test('Flex 标题收宽后完整绘制，末行独立对齐仍生效', () async {
    final source = await openCssChapter(
      body: '<div><h1>ABC</h1></div>',
      css:
          'body {margin:0;} div {display:flex;justify-content:center;} '
          'h1 {margin:0;max-width:80%;font:35.2px/1.3 Ahem; '
          'text-indent:0;text-align:center;text-align-last:right;color:#008000;}',
      contentWidth: 350,
      contentHeight: 200,
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final cell = page.slices.single.block.table!.cells.single;
    expect(cell.rect.width, closeTo(105.6, .01));
    expect(cell.layout.lines.single.offsetX, closeTo(0, .01));
    final recorder = ui.PictureRecorder();
    PagePainter().paint(
      ui.Canvas(recorder),
      page,
      pageSize: const ui.Size(350, 200),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(350, 200);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    var left = 350;
    var right = -1;
    for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
      if (bytes.getUint8(i + 1) != 128 || bytes.getUint8(i + 3) != 255) {
        continue;
      }
      final x = i ~/ 4 % 350;
      if (x < left) left = x;
      if (x > right) right = x;
    }
    expect(right - left + 1, closeTo(105.6, 2), reason: '不能只画出被裁剪的标题尾片');
    expect((left + right + 1) / 2, closeTo(175, 1));
  });
}
