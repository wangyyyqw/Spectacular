import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _canvasSize = Size(200, 200);

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageBlock _block(
  String text, {
  double spaceBefore = 0,
  double spaceAfter = 0,
}) => PageBlock(
  layout: TextLayoutEngine.layout(text: text, style: _style(), maxWidth: 180),
  style: _style(),
  spaceBefore: spaceBefore,
  spaceAfter: spaceAfter,
);

Future<ByteData> _render(void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas);
  final image = await recorder.endRecording().toImage(
    _canvasSize.width.round(),
    _canvasSize.height.round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

Future<ByteData> _renderPage(PageContent page) => _render(
  (canvas) =>
      const PagePainter().paint(canvas, page, pageSize: const Size(200, 100)),
);

/// 指定行范围内是否有墨迹。
bool _hasInk(ByteData bytes, int rowStart, int rowEnd) {
  final width = _canvasSize.width.round();
  for (var y = rowStart; y < rowEnd; y++) {
    for (var x = 0; x < width; x++) {
      if (bytes.getUint32((y * width + x) * 4) != 0xFFFFFFFF) {
        return true;
      }
    }
  }
  return false;
}

/// 首个有墨迹的像素行；没有时返回 -1。
int _firstInkRow(ByteData bytes) {
  final width = _canvasSize.width.round();
  for (var y = 0; y < _canvasSize.height.round(); y++) {
    for (var x = 0; x < width; x++) {
      if (bytes.getUint32((y * width + x) * 4) != 0xFFFFFFFF) {
        return y;
      }
    }
  }
  return -1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('跨页段落切片标记与可见范围', () {
    final pagination = Paginator(pageHeight: 48)
        .measureChapter(blocks: [_block('a\nb\nc')]);

    expect(pagination.pages, hasLength(2));
    final first = pagination.pages[0].slices.single;
    final second = pagination.pages[1].slices.single;

    expect(first.startLine, 0);
    expect(first.endLine, 2);
    expect(first.continuesBefore, isFalse);
    expect(first.continuesAfter, isTrue);
    expect(second.startLine, 2);
    expect(second.continuesBefore, isTrue);
    expect(second.continuesAfter, isFalse);
  });

  test('跨页段落绘制不越出本页内容区', () async {
    final pagination = Paginator(pageHeight: 48)
        .measureChapter(blocks: [_block('a\nb\nc')]);

    final first = await _renderPage(pagination.pages[0]);
    expect(_hasInk(first, 0, 48), isTrue);
    expect(_hasInk(first, 48, 100), isFalse, reason: '第一页不应画到页内容区下方');

    final second = await _renderPage(pagination.pages[1]);
    expect(_firstInkRow(second), greaterThanOrEqualTo(0));
    expect(_firstInkRow(second), lessThan(24), reason: '续页从页顶开始，无额外缩进');
    expect(_hasInk(second, 24, 100), isFalse, reason: '续页只有一行');
  });

  test('切片裁剪切断超出行框的墨迹', () async {
    final block = _block('a');
    final clipped = PageContent(
      spineIndex: 0,
      pageIndex: 0,
      slices: [
        PageBlockSlice(block: block, startLine: 0, endLine: 1, height: 10),
      ],
      usedHeight: 10,
      pageHeight: 100,
      topPadding: 0,
    );
    final full = PageContent(
      spineIndex: 0,
      pageIndex: 0,
      slices: [
        PageBlockSlice(block: block, startLine: 0, endLine: 1, height: 24),
      ],
      usedHeight: 24,
      pageHeight: 100,
      topPadding: 0,
    );

    final clippedBytes = await _renderPage(clipped);
    final fullBytes = await _renderPage(full);

    expect(_hasInk(clippedBytes, 0, 10), isTrue, reason: '裁剪区内应有墨迹');
    expect(_hasInk(clippedBytes, 10, 100), isFalse, reason: '裁剪区外不应有墨迹');
    expect(_hasInk(fullBytes, 10, 24), isTrue, reason: '不裁剪时墨迹会落到 10px 以下');
  });

  test('跨页边框按切片矩形裁剪，不画到下一页', () async {
    final pagination = Paginator(pageHeight: 48)
        .measureChapter(blocks: [_block('a\nb\nc')]);
    final page = pagination.pages[0];
    final slice = page.slices.single;
    expect(slice.continuesAfter, isTrue);

    final bytes = await _render((canvas) {
      canvas.drawRect(
        Offset.zero & _canvasSize,
        Paint()..color = const Color(0xFFFFFFFF),
      );
      // 模拟跨页块的边框/背景：整块高度 72，但本页只应画到切片底边 48。
      canvas.save();
      canvas.clipRect(slice.clipRect(0, _canvasSize.width));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, _canvasSize.width, slice.block.height),
        Paint()..color = const Color(0xFF000000),
      );
      canvas.restore();
    });

    expect(_hasInk(bytes, 0, 48), isTrue);
    expect(_hasInk(bytes, 48, _canvasSize.height.round()), isFalse);
  });

  test('命中区域限制在本页可见行内', () {
    final pagination = Paginator(pageHeight: 48)
        .measureChapter(blocks: [_block('a\nb\nc')]);
    final first = pagination.pages[0];
    final second = pagination.pages[1];

    final hit0 = first.hitTest(const Offset(10, 0));
    expect(hit0?.sliceIndex, 0);
    expect(hit0?.lineIndex, 0);

    final hit1 = first.hitTest(const Offset(10, 47));
    expect(hit1?.lineIndex, 1);

    expect(first.hitTest(const Offset(10, 48)), isNull, reason: '第 3 行不在本页');
    expect(first.hitTest(const Offset(10, -1)), isNull);
    expect(
      first.hitTest(const Offset(201, 0), contentWidth: 200),
      isNull,
      reason: '内容区外不命中',
    );

    final continued = second.hitTest(const Offset(10, 0));
    expect(continued?.slice.startLine, 2);
    expect(continued?.lineIndex, 2, reason: '续页首个可见行是块内第 3 行');
  });

  test('续页不重复段前间距，首页仍保留', () async {
    final pagination = Paginator(pageHeight: 72).measureChapter(
      blocks: [_block('a\nb\nc\nd', spaceBefore: 10, spaceAfter: 10)],
    );
    final first = pagination.pages[0];
    final second = pagination.pages[1];

    expect(first.slices.single.startLine, 0);
    expect(second.slices.single.continuesBefore, isTrue);

    final firstBytes = await _renderPage(first);
    final secondBytes = await _renderPage(second);
    expect(
      _firstInkRow(firstBytes),
      greaterThanOrEqualTo(10),
      reason: '首页保留段前间距',
    );
    expect(_firstInkRow(secondBytes), lessThan(5), reason: '续页不重复段前间距');
  });
}
