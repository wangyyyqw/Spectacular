import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(160, 60);

/// 4×4 纯红图（程序化生成）。
Future<ui.Image> _redImage() {
  final pixels = Uint8List(4 * 4 * 4);
  for (var i = 0; i < 16; i++) {
    pixels[i * 4] = 255;
    pixels[i * 4 + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    4,
    4,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'color': '#000000',
});

Future<ByteData> _render({
  required PageBlock block,
  ui.Image? Function(String url)? imageLookup,
}) async {
  final page = Paginator(pageHeight: _pageSize.height)
      .measureChapter(blocks: <PageBlock>[block])
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(
    background: const Color(0xFFFFFFFF),
    imageLookup: imageLookup,
  ).paint(canvas, page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(
    _pageSize.width.toInt(),
    _pageSize.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _redPixels(ByteData bytes) {
  var count = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    if (bytes.getUint8(i) > 200 && bytes.getUint8(i + 1) < 80) {
      count += 1;
    }
  }
  return count;
}

PageBlock _blockWithInlineImage({List<InlineImageSpec>? images}) {
  final style = _style();
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: '文\uFFFC字',
      style: style,
      maxWidth: _pageSize.width,
    ),
    style: style,
    containingWidth: _pageSize.width,
    inlineImages:
        images ??
        const <InlineImageSpec>[
          InlineImageSpec(offset: 1, url: 'OEBPS/Images/icon.png'),
        ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('行内图片按占位符位置绘制（P9-06）', () async {
    final image = await _redImage();
    var asked = 0;
    final data = await _render(
      block: _blockWithInlineImage(),
      imageLookup: (url) {
        asked += 1;
        return url == 'OEBPS/Images/icon.png' ? image : null;
      },
    );
    expect(asked, greaterThan(0));
    expect(_redPixels(data), greaterThan(0), reason: '占位符位置应出现图片像素');
  });

  test('没有行内图片声明时不画图', () async {
    final image = await _redImage();
    final data = await _render(
      block: _blockWithInlineImage(images: const <InlineImageSpec>[]),
      imageLookup: (url) => image,
    );
    expect(_redPixels(data), 0);
  });

  test('行内宽高比约束绘制高度', () async {
    final image = await _redImage();
    final data = await _render(
      block: _blockWithInlineImage(
        images: const <InlineImageSpec>[
          InlineImageSpec(
            offset: 1,
            url: 'OEBPS/Images/icon.png',
            aspectRatio: 2,
          ),
        ],
      ),
      imageLookup: (url) => image,
    );
    expect(_redPixels(data), 512, reason: '32px 宽按 2:1 应画成 32×16');
  });
}
