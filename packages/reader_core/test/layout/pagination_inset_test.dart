import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(200, 200);

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'color': '#FF0000',
      ...overrides,
    });

TextLayoutResult _layout(String text, ComputedStyle style) =>
    TextLayoutEngine.layout(text: text, style: style, maxWidth: 180);

PageBlock _block(String text, ComputedStyle style) => PageBlock.styled(
  layout: _layout(text, style),
  style: style,
  containingWidth: 200,
);

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const PagePainter().paint(canvas, page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(
    _pageSize.width.round(),
    _pageSize.height.round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _firstInkRow(ByteData bytes, {int from = 0}) {
  final width = _pageSize.width.round();
  for (var y = from; y < _pageSize.height.round(); y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      if (_isRedText(bytes, offset)) {
        return y;
      }
    }
  }
  return -1;
}

int _firstInkCol(ByteData bytes) {
  final width = _pageSize.width.round();
  for (var x = 0; x < width; x++) {
    for (var y = 0; y < _pageSize.height.round(); y++) {
      final offset = (y * width + x) * 4;
      if (_isRedText(bytes, offset)) {
        return x;
      }
    }
  }
  return -1;
}

/// 是否红色文字像素（边框是黑色，用颜色区分文字与边框）。
bool _isRedText(ByteData bytes, int offset) =>
    bytes.getUint8(offset) > 200 &&
    bytes.getUint8(offset + 1) < 60 &&
    bytes.getUint8(offset + 2) < 60;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内缩计入页几何与切片', () {
    final style = _style(const {
      'padding': '8px',
      'border': '4px solid #000000',
    });
    final block = _block('aa\nbb', style);
    expect(block.topInset, 12);
    expect(block.bottomInset, 12);
    expect(block.leftInset, 12);

    final pagination = Paginator(pageHeight: 200)
        .measureChapter(blocks: [block]);
    final page = pagination.pages.single;
    expect(page.slices.single.leadingExtent, 12);
    expect(page.slices.single.trailingExtent, 12);
    expect(page.slices.single.leftInset, 12);
    expect(page.slices.single.height, closeTo(48 + 24, 0.01));
    expect(page.usedHeight, closeTo(72, 0.01));
    expect(pagination.totalHeight, closeTo(72, 0.01));
  });

  test('命中区域跳过首尾内缩', () {
    final style = _style(const {
      'padding': '8px',
      'border': '4px solid #000000',
    });
    final page = Paginator(pageHeight: 200)
        .measureChapter(blocks: [_block('aa\nbb', style)])
        .pages
        .single;

    expect(page.hitTest(const Offset(20, 0)), isNull, reason: '上内缩不命中');
    expect(page.hitTest(const Offset(20, 11)), isNull);
    final line0 = page.hitTest(const Offset(20, 12));
    expect(line0?.lineIndex, 0);
    final line1 = page.hitTest(const Offset(20, 59));
    expect(line1?.lineIndex, 1);
    expect(page.hitTest(const Offset(20, 71)), isNull, reason: '下内缩不命中');
    expect(page.hitTest(const Offset(20, 72)), isNull, reason: '页面内容区之外');
  });

  test('段前间距只出现在块首切片，续页不重复', () {
    final style = _style(const {});
    final block = PageBlock(
      layout: _layout('aa\nbb', style),
      style: style,
      spaceBefore: 10,
    );
    final pagination = Paginator(pageHeight: 40)
        .measureChapter(blocks: [block]);

    expect(pagination.pages, hasLength(2));
    expect(pagination.pages[0].slices.single.leadingExtent, 10);
    expect(pagination.pages[0].usedHeight, closeTo(34, 0.01));
    expect(pagination.pages[1].slices.single.leadingExtent, 0);
  });

  test('段尾内缩放不下时退一行到下一页', () {
    final style = _style(const {'padding-bottom': '12px'});
    final block = PageBlock.styled(
      layout: _layout('aa\nbb', style),
      style: style,
      containingWidth: 200,
    );
    final pagination = Paginator(pageHeight: 40)
        .measureChapter(blocks: [block]);

    expect(pagination.pages, hasLength(2));
    expect(pagination.pages[0].slices.single.endLine, 1, reason: '只放一行');
    expect(pagination.pages[0].slices.single.trailingExtent, 0);
    final last = pagination.pages[1].slices.single;
    expect(last.trailingExtent, 12);
    expect(last.height, closeTo(24 + 12, 0.01));
  });

  test('绘制几何与分页切片一致（两块各自内缩）', () async {
    final style = _style(const {
      'padding': '6px',
      'border': '2px solid #000000',
    });
    final blocks = [_block('aa', style), _block('bb', style)];
    final page = Paginator(pageHeight: 200)
        .measureChapter(blocks: blocks)
        .pages
        .single;

    final bytes = await _render(page);
    // 第一块：leading 8 → 首行墨迹行 ≥8；块高 = 8 + 24 + 8 = 40。
    expect(_firstInkRow(bytes), greaterThanOrEqualTo(8));
    expect(_firstInkRow(bytes), lessThan(16));
    // 第二块从 40 起，leading 8 → 墨迹行 ≥48。
    expect(_firstInkRow(bytes, from: 40), greaterThanOrEqualTo(48));
    // 文字左边界让开 8px（border 2 + padding 6）。
    expect(_firstInkCol(bytes), greaterThanOrEqualTo(8));
  });
}
