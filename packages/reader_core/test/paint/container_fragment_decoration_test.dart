import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _width = 100;
const _red = 0xff0000ff;
const _green = 0x00ff00ff;
const _blue = 0x0000ffff;
const _background = 0xeeeeeeff;
const _white = 0xffffffff;

PageContainer _container(
  String color,
  double left, {
  bool clone = true,
  double padding = 4,
}) => PageContainer(
  style: ComputedStyle({
    'border': '2px solid $color',
    'padding': '${padding}px',
    'background-color': '#eeeeee',
  }),
  left: left,
  width: _width - left * 2,
  cloneDecoration: clone,
);

List<PageContent> _pages(
  List<PageContainer> containers, {
  int lineCount = 7,
  double height = 50,
}) {
  final insets = containers.map((c) => c.style.padding.top + 2).toList();
  final total = insets.fold(0.0, (a, b) => a + b);
  final style = ComputedStyle({
    'font-family': 'Ahem',
    'font-size': '10px',
    'line-height': '1',
    'white-space': 'pre',
    'margin-left': '${total}px',
    'margin-right': '${total}px',
  });
  final layout = TextLayoutEngine.layout(
    text: List.filled(lineCount, 'aa').join('\n'),
    style: style,
    maxWidth: _width - total * 2,
  );
  final block =
      PageBlock.styled(
        layout: layout,
        style: style,
        containingWidth: _width.toDouble(),
      ).withSpacing(
        topInset: total,
        bottomInset: total,
        containers: _fragments(containers, insets),
      );
  return Paginator(
    pageHeight: height,
    pageWidth: _width.toDouble(),
    tolerance: 0,
  ).measureChapter(blocks: [block]).pages;
}

List<PageContainerFragment> _fragments(
  List<PageContainer> containers,
  List<double> insets,
) => [
  for (var i = 0; i < containers.length; i++)
    PageContainerFragment(
      container: containers[i],
      startsHere: true,
      endsHere: true,
      topInset: insets.skip(i).fold(0.0, (a, b) => a + b),
      bottomInset: insets.skip(i).fold(0.0, (a, b) => a + b),
    ),
];

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: Size(_width.toDouble(), page.pageHeight),
  );
  final image = await recorder.endRecording().toImage(
    _width,
    page.pageHeight.ceil(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _pixel(ByteData data, int x, int y) => data.getUint32((y * _width + x) * 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('克隆容器三页各自封框，并保留续页上下内边距', () async {
    final pages = _pages([_container('#ff0000', 0)]);
    expect(pages, hasLength(3));
    for (final page in pages.take(2)) {
      final data = await _render(page);
      expect(_pixel(data, 50, 0), _red);
      expect(_pixel(data, 50, 49), _red, reason: '未完成的框撑到正文区底部');
      expect(_pixel(data, 0, 25), _red);
      expect(_pixel(data, 99, 25), _red);
      expect(_pixel(data, 8, 3), _background, reason: '顶边框与首行间留白');
      expect(_pixel(data, 8, 46), _background, reason: '末行与底边框间留白');
      expect(_pixel(data, 8, 8), 0x000000ff, reason: '文字排在顶部内边距之后');
    }
  });

  test('三层克隆框的续页上下边框逐层内缩', () async {
    final pages = _pages(
      [
        _container('#ff0000', 0, padding: 2),
        _container('#00ff00', 4, padding: 2),
        _container('#0000ff', 8, padding: 2),
      ],
      lineCount: 13,
      height: 80,
    );
    expect(pages, hasLength(3));
    final data = await _render(pages[1]);
    for (final band in [(0, 79, _red), (4, 75, _green), (8, 71, _blue)]) {
      expect(_pixel(data, 50, band.$1), band.$3);
      expect(_pixel(data, 50, band.$2), band.$3);
    }
    expect(_pixel(data, 15, 10), _background);
    expect(_pixel(data, 15, 14), 0x000000ff);
  });

  test('短末页按内容自然收口，不强行铺满页底', () async {
    final page = _pages([_container('#ff0000', 0)]).last;
    expect(page.usedHeight, lessThan(page.pageHeight));
    final data = await _render(page);
    final end = page.usedHeight.round();
    expect(_pixel(data, 50, 0), _red);
    expect(_pixel(data, 50, end - 1), _red);
    expect(_pixel(data, 50, end + 1), _white);
    expect(_pixel(data, 50, 49), _white);
  });

  test('默认切片模式仍只在真实首尾画上下边框', () async {
    final pages = _pages([_container('#ff0000', 0, clone: false)]);
    final first = await _render(pages.first);
    final last = await _render(pages.last);
    expect(_pixel(first, 50, 0), _red);
    expect(_pixel(first, 50, pages.first.usedHeight.toInt() - 1), _background);
    expect(_pixel(last, 50, 0), _background);
    expect(_pixel(last, 50, pages.last.usedHeight.toInt() - 1), _red);
  });

  test('非克隆外框不占用续页上下内边距，内框仍独立封闭', () async {
    final pages = _pages(
      [
        _container('#ff0000', 0, clone: false, padding: 2),
        _container('#0000ff', 4, padding: 2),
      ],
      lineCount: 17,
      height: 80,
    );
    final data = await _render(pages[1]);
    expect(_pixel(data, 1, 0), _red, reason: '外框仍只有连续侧边');
    expect(_pixel(data, 50, 0), _blue, reason: '内框不预留外框已切掉的padding');
    expect(_pixel(data, 50, 79), _blue);
    expect(_pixel(data, 15, 2), _background);
    expect(_pixel(data, 15, 6), 0x000000ff);
  });
}
