import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

import 'support/css_chapter_book.dart';

const _caption = '银色金属材质，里面有一块不规则灰色石头';
const _width = 344.0;
const _height = 260.0;
const _scale = 3;

Future<PageContent> _captionPage({
  String side = 'right',
  String box = '',
  String inner = '',
  double size = 17,
  bool image = true,
}) async {
  final source = await openCssChapter(
    body:
        '<div class="float"><div class="inner">'
        '${image ? '<img src="../Images/a.png" width="98%" height="70"/>' : ''}'
        '<p class="caption"><span>$_caption</span></p></div></div>',
    css:
        'body { margin: 0; font-family: caption_song; font-size: ${size}px; } '
        'div { margin: 0; padding: 0; } '
        '.float { float: $side; width: 45%; margin-left: .7em; } '
        '.inner { $inner } '
        '.caption { margin: .5em; text-indent: 0; text-align: center; '
        'line-height: 1.6; color: #b32025; $box } '
        '.caption span { font-size: .72em; }',
    binaryFiles: {
      'OEBPS/Images/a.png': base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVR4nGO4cOHCfwAIVANwVMROmgAAAABJRU5ErkJggg==',
      ),
    },
    contentWidth: _width,
    contentHeight: _height,
  );
  return (await source.loadChapter(0)).single;
}

PageBlockSlice _captionSlice(PageContent page) =>
    page.slices.singleWhere((slice) => slice.block.layout.text == _caption);

Future<Uint8List> _paint(
  PageContent page,
  double width, [
  ParagraphCache? cache,
]) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_scale.toDouble());
  PagePainter(paragraphCache: cache)
      .paint(canvas, page, pageSize: Size(width, _height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * _scale).round(),
    (_height * _scale).round(),
  );
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

int _inkCount(Uint8List pixels) {
  var count = 0;
  for (var index = 0; index < pixels.length; index += 4) {
    if (pixels[index] == 0xb3 &&
        pixels[index + 1] == 0x20 &&
        pixels[index + 2] == 0x25 &&
        pixels[index + 3] != 0) {
      count++;
    }
  }
  return count;
}

Future<void> _expectCompleteInk(PageContent page) async {
  final visible = await _paint(page, _width);
  final unclipped = await _paint(page, _width + 40);
  expect(_inkCount(visible), greaterThan(0));
  expect(
    _inkCount(visible),
    _inkCount(unclipped),
    reason: '扩大绘制区域不能多出被正文右缘截掉的字形墨迹',
  );
  final cache = ParagraphCache();
  addTearDown(cache.dispose);
  for (var pass = 0; pass < 2; pass++) {
    expect(await _paint(page, _width, cache), orderedEquals(visible));
  }
  for (final line in TextHitTester.lineBoxes(page)) {
    expect(line.rect.right, lessThanOrEqualTo(_width));
  }
}

void _boxModelTests() {
  for (final side in ['left', 'right']) {
    for (final box in {
      '外边距': ('', _width * .45 - 17),
      '内边距及边框': (
        'padding: 0 3px; border: 1px solid black;',
        _width * .45 - 17 - 8,
      ),
      '百分比边框盒': (
        'width: 80%; box-sizing: border-box; padding: 0 3px; '
            'border: 1px solid black;',
        _width * .45 * .8 - 8,
      ),
    }.entries) {
      test('$side 浮动图注${box.key}：按子内容盒断行，不重复扣容器外边距', () async {
        final page = await _captionPage(side: side, box: box.value.$1);
        final caption = _captionSlice(page);
        expect(caption.block.layout.maxWidth, closeTo(box.value.$2, .01));
        expect(
          caption.block.layout.lines
              .map((line) => _caption.substring(line.start, line.end))
              .join(),
          _caption,
        );
        final image = page.slices.first;
        expect(caption.block.groupId, image.block.groupId);
        expect(caption.leftInset, image.leftInset, reason: '子段收窄不改变整组定位');
      });
    }

    test('$side 浮动首块也是图注时，仍扣自身外边距', () async {
      final page = await _captionPage(side: side, image: false);
      expect(
        _captionSlice(page).block.layout.maxWidth,
        closeTo(_width * .45 - 17, .01),
      );
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'caption_song',
    )..addFont(rootBundle.load('assets/fonts/MoyuSerif-Regular.otf'))).load();
  });
  _boxModelTests();

  test('浮动内部嵌套容器的内外边距逐层收窄，不扣浮动自身的占位边距', () async {
    final page = await _captionPage(inner: 'margin: 0 4px; padding: 0 3px;');
    expect(
      _captionSlice(page).block.layout.maxWidth,
      closeTo(_width * .45 - 14 - 17, .01),
    );
  });

  for (final size in [17.0, 22.0]) {
    test('${size}px 图注末字墨迹完整，缓存与无缓存绘制一致', () async {
      await _expectCompleteInk(await _captionPage(size: size));
    });
  }
}
