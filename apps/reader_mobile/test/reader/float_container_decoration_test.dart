import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

const _width = 200;
const _height = 120;
const _css =
    'body, p { margin: 0; } '
    'p, td { font-size: 10px; line-height: 10px; } '
    '.outer { padding: 4px; border: 2px solid #ff0000; } '
    '.card { padding: 4px; border: 2px solid #0000ff; } '
    '.tag { float: right; width: 20px; font-size: 10px; '
    'line-height: 10px; background: #00ff00; }';

Future<List<PageContent>> _pages(String body, {String css = ''}) async {
  final source = await openCssChapter(
    body: body,
    css: '$_css $css',
    contentWidth: _width.toDouble(),
    contentHeight: _height.toDouble(),
  );
  addTearDown(source.close);
  return source.loadChapter(0);
}

String _flowText(List<PageContent> pages) => [
  for (final page in pages)
    for (final slice in page.slices.where((slice) => !slice.overlay))
      for (final line in slice.lines)
        slice.block.layout.text.substring(line.start, line.end),
].join();

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    ui.Canvas(recorder),
    page,
    pageSize: const ui.Size(200, 120),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_width, _height);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _pixel(ByteData data, int x, int y) => data.getUint32((y * _width + x) * 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('浮动标签的嵌套跨页卡片每页封框，正文连续且不占上下装饰', () async {
    final text = '跨页说明正文。' * 100;
    final pages = await _pages(
      '<div class="outer"><div class="card">'
      '<p><span class="tag">标签</span>标题</p>'
      '<p>$text</p></div></div>',
      css: 'p { clear: both; }',
    );
    expect(pages.length, greaterThan(1));
    expect(_flowText(pages), '标题$text');
    for (final page in pages) {
      expect(page.usedHeight, lessThanOrEqualTo(_height));
      final flow = page.slices.where((slice) => !slice.overlay).toList();
      expect(
        flow.every(
          (slice) => slice.block.containers.every(
            (fragment) => fragment.container.cloneDecoration,
          ),
        ),
        isTrue,
      );
      final pixels = await _render(page);
      expect(_pixel(pixels, 100, 0), 0xff0000ff);
      expect(_pixel(pixels, 100, 6), 0x0000ffff);
      final bottom = page == pages.last ? page.usedHeight.round() : _height;
      expect(_pixel(pixels, 100, bottom - 1), 0xff0000ff);
      expect(_pixel(pixels, 100, bottom - 7), 0x0000ffff);
      for (final color in [0xff0000ff, 0x0000ffff]) {
        expect(
          [for (var y = 0; y < _height; y++) _pixel(pixels, 100, y)]
              .where((pixel) => pixel == color),
          hasLength(4),
          reason: 'clear 占位不能拆散容器，重复绘制页内横线',
        );
      }
      if (page != pages.first) {
        expect(flow.first.leadingExtent, 12);
      }
      expect(flow.last.trailingExtent, 12);
    }
    expect(pages.last.usedHeight, lessThan(_height));
  });

  test('浮动章节中的跨页表格每页保留外框，所有行只出现一次', () async {
    final pages = await _pages(
      '<p class="tag">浮</p><div class="outer"><table>'
      '${List.generate(24, (i) => '<tr><td>第$i行</td></tr>').join()}'
      '</table></div>',
      css: 'table { border-collapse: collapse; } td { padding: 0; }',
    );
    final cells = [
      for (final page in pages)
        for (final slice in page.slices)
          for (final cell in slice.block.table?.cells ?? <TableCellRender>[])
            cell.layout.text,
    ];
    expect(cells, List.generate(24, (i) => '第$i行'));
    for (final page in pages) {
      expect(page.usedHeight, lessThanOrEqualTo(_height));
      final pixels = await _render(page);
      expect(_pixel(pixels, 100, 0), 0xff0000ff);
      final bottom = page == pages.last ? page.usedHeight.round() : _height;
      expect(_pixel(pixels, 100, bottom - 1), 0xff0000ff);
    }
  });

  test('浮动章节中的声明高度盒续页同样预留边框，不截断后续正文', () async {
    final pages = await _pages(
      '<p class="tag">浮</p><div class="outer">'
      '${List.generate(5, (i) => '<p class="box">第$i段</p>').join()}'
      '</div>',
      css: '.box { height: 55px; }',
    );
    expect(_flowText(pages), List.generate(5, (i) => '第$i段').join());
    expect(pages.length, greaterThan(2));
    for (final page in pages) {
      expect(page.usedHeight, lessThanOrEqualTo(_height));
      final pixels = await _render(page);
      expect(_pixel(pixels, 100, 0), 0xff0000ff);
      final bottom = page == pages.last ? page.usedHeight.round() : _height;
      expect(_pixel(pixels, 100, bottom - 1), 0xff0000ff);
    }
  });

  test('浮动标签先移到续页时，外框仍从页首开始且标签避开边框', () async {
    final filler = '前置正文。' * 20;
    final pages = await _pages(
      '<div class="outer"><p class="filler">$filler</p>'
      '<p><span class="tag">标签</span>标题</p><p>正文</p></div>',
      css: '.filler { height: 100px; }',
    );
    expect(pages, hasLength(2));
    expect(_flowText(pages), '$filler标题正文');
    final tag = pages[1].slices.singleWhere((slice) => slice.overlay);
    expect(tag.absoluteTop, greaterThanOrEqualTo(6));
    expect(_pixel(await _render(pages[1]), 100, 0), 0xff0000ff);
  });

  test('浮动章节仍尊重作者显式 slice，不擅自把所有背景强制封框', () async {
    final pages = await _pages(
      '<div class="outer"><p class="tag">浮</p>'
      '<p>${'跨页正文。' * 100}</p></div>',
      css: '.outer { box-decoration-break: slice; }',
    );
    expect(pages.length, greaterThan(1));
    expect(
      pages
          .expand((page) => page.slices)
          .every(
            (slice) => slice.block.containers.every(
              (f) => !f.container.cloneDecoration,
            ),
          ),
      isTrue,
    );
    final middle = await _render(pages[1]);
    expect(_pixel(middle, 100, 0), isNot(0xff0000ff));
  });
}
