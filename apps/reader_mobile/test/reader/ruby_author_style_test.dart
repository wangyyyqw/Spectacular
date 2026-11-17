import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

Future<PageContent> _page(String body, String css) async {
  final source = await openCssChapter(
    body: body,
    css:
        'body {margin:0; font:20px Ahem;} p {margin:60px 0; '
        'text-indent:0; text-align:left;} $css',
    contentWidth: 300,
    contentHeight: 300,
  );
  addTearDown(source.close);
  return (await source.loadChapter(0)).single;
}

Future<ui.Rect> _colorBounds(PageContent page, int color) async {
  final recorder = ui.PictureRecorder();
  PagePainter(background: const ui.Color(0xff000000))
      .paint(ui.Canvas(recorder), page, pageSize: const ui.Size(300, 300));
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 300);
  picture.dispose();
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  var left = 300, top = 300, right = -1, bottom = -1;
  for (var y = 0; y < 300; y++) {
    for (var x = 0; x < 300; x++) {
      if (pixels!.getUint32((y * 300 + x) * 4) != color) continue;
      if (x < left) left = x;
      if (y < top) top = y;
      if (x > right) right = x;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '作者指定的注音颜色有实际像素');
  return ui.Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无属性 ruby 仍匹配作者样式，rt 按原始父链继承颜色与半号字族', () async {
    final page = await _page(
      '<p><span>第一部 <ruby>海斯曼报告<rt>Heisman Report</rt></ruby></span></p>',
      'p {color:#f08080;} span {color:#808000; font-size:90%;} '
          'ruby {color:#fff;} ruby > rt {font-family:Ahem; font-size:.5em;}',
    );
    final block = page.slices.single.block;
    final ruby = block.rubies!.single;
    final base = block.layout.runs.singleWhere(
      (run) => run.start == ruby.start && run.end == ruby.end,
    );
    expect(base.style.color, const ui.Color(0xffffffff));
    expect(ruby.style!.color, const ui.Color(0xffffffff));
    expect(ruby.style!.fontSize, closeTo(9, .01));
    expect(ruby.style!.fontFamilies, ['Ahem']);
    expect(block.layout.text, '第一部 海斯曼报告');
  });

  test('生成前缀改变原文偏移后，注音保留自身 style 属性与作者选择器链', () async {
    final page = await _page(
      '<p><ruby class="term">汉字<rt style="font-size:40%;color:#00bb55">han</rt></ruby></p>',
      'p::before {content:"前";} ruby.term {font-size:30px; color:#fff;}',
    );
    final block = page.slices.single.block;
    final ruby = block.rubies!.single;
    expect(block.layout.text.substring(ruby.start, ruby.end), '汉字');
    expect(ruby.start, 1);
    expect(ruby.style!.fontSize, closeTo(12, .01));
    expect(ruby.style!.color, const ui.Color(0xff00bb55));
  });

  for (final position in ['over', 'under']) {
    test('横排 $position 注音按作者字号和混排基字的实际位置绘制', () async {
      final page = await _page(
        '<p><span>AA</span><ruby>BB<rt>cc</rt></ruby></p>',
        'p {color:#f08080;} span {font-size:40px;} '
            'ruby {color:#fff; ruby-position:$position; ruby-align:center;} '
            'rt {font-size:25%; font-family:Ahem; color:#00bb55;}',
      );
      final bounds = await _colorBounds(page, 0x00bb55ff);
      final base = await _colorBounds(page, 0xffffffff);
      expect(bounds.left, closeTo(95, 1));
      expect(bounds.width, closeTo(10, 1));
      expect(bounds.height, closeTo(5, 1));
      expect(
        position == 'over' ? base.top - bounds.bottom : bounds.top - base.bottom,
        closeTo(0, 1),
        reason: '注音贴基字内容盒，混排大字产生的行高留白不参与注音定位',
      );
    });
  }

  test('竖排注音保留作者字号、颜色及方向', () async {
    final page = await _page(
      '<p><ruby>汉字<rt>cc</rt></ruby></p>',
      'p {writing-mode:vertical-rl; margin:0; color:#f08080;} '
          'ruby {color:#fff; ruby-position:under;} rt {font-size:25%; color:#00bb55;}',
    );
    final bounds = await _colorBounds(page, 0x00bb55ff);
    expect(bounds.width, closeTo(5, 1));
    expect(bounds.height, closeTo(10, 1));
  });
}
