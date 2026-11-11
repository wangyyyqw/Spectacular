import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/hit_test.dart';

import 'support/css_chapter_book.dart';

late Uint8List _image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff345678), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 150);
    picture.dispose();
    _image = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
  });

  for (final side in ['left', 'right']) {
    test('$side 满宽浮动的负段后距只计算一次，标题等待可用行宽', () async {
      final source = await openCssChapter(
        body:
            '<div class="picture"><img src="../Images/a.png" '
            'width="100%" height="120"/></div>'
            '<div class="mask"><img src="../Images/a.png" '
            'width="100%" height="80"/></div>'
            '<h1>章节标题需要正确绕排</h1>'
            '<p>${'正文绕排后恢复整行。' * 15}</p>',
        css:
            'body,h1,p {margin:0; font:16px/1 Ahem; text-indent:0;} '
            '.picture {float:$side; width:100%; margin-bottom:-20px;} '
            '.mask {float:left; width:55%; margin-right:8px;} '
            'h1 {text-align:center;}',
        binaryFiles: {'OEBPS/Images/a.png': _image},
        contentWidth: 300,
        contentHeight: 600,
      );
      addTearDown(source.close);
      final page = (await source.loadChapter(0)).single;
      final pictures = page.slices.where((slice) => slice.overlay).toList();
      expect(pictures, hasLength(2));
      expect(pictures.first.absoluteTop, 0);
      expect(pictures.last.absoluteTop, closeTo(100, .01));
      final lines = TextHitTester.lineBoxes(page)
          .where((box) => box.text.isNotEmpty)
          .toList();
      expect(lines.first.rect.top, closeTo(100, .01));
      expect(lines.first.rect.left, greaterThanOrEqualTo(173));
      expect(
        lines.map((box) => box.text).join(),
        '章节标题需要正确绕排${'正文绕排后恢复整行。' * 15}',
      );
      expect(
        lines.where((box) => box.rect.top >= 180 && box.rect.left == 0),
        isNotEmpty,
        reason: '透明占位图结束后正文恢复整行，不能提前叠到满宽插图上',
      );
    });
  }

  for (final height in ['105px', '35%']) {
    test('浮动图片容器的 $height 声明高度控制正文绕排范围', () async {
      final source = await openCssChapter(
        body:
            '<div class="float"><img src="../Images/a.png" '
            'width="100%" height="20"/></div>'
            '<p>${'正文需要避让完整的浮动容器。' * 12}</p>',
        css:
            'body,p {margin:0;font:16px/1 Ahem;text-indent:0;} '
            '.float {float:left;width:50%;height:$height;}',
        binaryFiles: {'OEBPS/Images/a.png': _image},
        contentWidth: 300,
        contentHeight: 500,
      );
      addTearDown(source.close);
      final page = (await source.loadChapter(0)).single;
      final lines = TextHitTester.lineBoxes(page)
          .where((box) => !box.slice.overlay && box.text.isNotEmpty)
          .toList();
      expect(
        lines.where((box) => box.rect.top < 105).map((box) => box.rect.left),
        everyElement(greaterThanOrEqualTo(150)),
      );
      expect(
        lines.where((box) => box.rect.top >= 105 && box.rect.left == 0),
        isNotEmpty,
      );
    });
  }

  test('段落先绕排再遇到满宽浮动时，同页等待后续排且原文完整', () async {
    final text = '这段正文需要跨过中间的满宽浮动继续排版。' * 12;
    final source = await openCssChapter(
      body:
          '<div class="small"><img src="../Images/a.png" '
          'width="100%" height="48"/></div>'
          '<div class="full"><img src="../Images/a.png" '
          'width="100%" height="60"/></div><p>$text</p>',
      css:
          'body,p {margin:0;font:16px/1 Ahem;text-indent:0;} '
          '.small {float:left;width:30%;} .full {float:right;width:100%;}',
      binaryFiles: {'OEBPS/Images/a.png': _image},
      contentWidth: 300,
      contentHeight: 500,
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final lines = TextHitTester.lineBoxes(page)
        .where((box) => !box.slice.overlay && box.text.isNotEmpty)
        .toList();
    expect(lines.take(3).map((box) => box.rect.top), [0, 16, 32]);
    expect(lines[3].rect.top, closeTo(108, .01));
    expect(lines.map((box) => box.text).join(), text);
  });

  test('浮动留下的行宽低于断行下限时等待，不把文字扩进图片', () async {
    final source = await openCssChapter(
      body: '<div class="float">占位</div><p>等待浮动结束再显示完整正文。</p>',
      css:
          'body,p {margin:0;font:20px/1 Ahem;text-indent:0;} '
          '.float {float:right;width:90%;height:80px;}',
      contentWidth: 300,
      contentHeight: 200,
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final text = TextHitTester.lineBoxes(page)
        .where((box) => !box.slice.overlay && box.text.isNotEmpty);
    expect(text.first.rect.top, closeTo(80, .01));
    expect(text.first.rect.left, 0);
    expect(text.map((box) => box.text).join(), '等待浮动结束再显示完整正文。');
  });
}
