import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

PageBlock _block(String text, Map<String, String> extra) {
  final style = ComputedStyle({
    'font-size': '16px',
    'line-height': '1',
    'font-family': 'Ahem',
    'color': '#000000',
    ...extra,
  });
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: 120),
    style: style,
    containingWidth: 200,
    absolute: extra['position'] == 'absolute',
  );
}

Future<ByteData> _render(List<PageBlock> blocks) async {
  final page = Paginator(
    pageHeight: 200,
    pageWidth: 200,
  ).measureChapter(blocks: blocks).pages.first;
  return _renderPage(page);
}

Future<ByteData> _renderPage(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: const Size(200, 200),
  );
  final image = await recorder.endRecording().toImage(200, 200);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

List<int> _pixel(ByteData data, int x, int y) =>
    List.generate(4, (i) => data.getUint8((y * 200 + x) * 4 + i));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final position in ['static', 'relative']) {
    test('负边距容器为 $position 时按绘制阶段叠放图片内容', () async {
      final imageStyle = ComputedStyle({
        'background-color': '#ff0000',
        'width': '100px',
      });
      final image = PageBlock(
        layout: TextLayoutResult(
          text: '',
          lines: const [
            LineBox(
              start: 0,
              end: 0,
              top: 0,
              height: 60,
              baseline: 60,
              width: 100,
            ),
          ],
          width: 100,
          height: 60,
          maxWidth: 100,
        ),
        style: imageStyle,
        isReplaced: true,
      );
      final parent = PageContainer(
        style: ComputedStyle({'position': position, 'background': '#0000ff'}),
        left: 0,
        width: 120,
      );
      final text = _block('aa', {'color': '#ffffff'}).withSpacing(
        topInset: -40,
        containers: [
          PageContainerFragment(
            container: parent,
            startsHere: true,
            endsHere: true,
          ),
        ],
      );
      final data = await _render([image, text]);
      expect(
        _pixel(data, 80, 25),
        position == 'static' ? [255, 0, 0, 255] : [0, 0, 255, 255],
      );
      expect(_pixel(data, 110, 25), [0, 0, 255, 255]);
      expect(_pixel(data, 8, 28), [
        255,
        255,
        255,
        255,
      ], reason: '容器文字仍在图片前景之后绘制');
    });
  }

  test('普通背景图块保持背景阶段，不当作替换图片提升层级', () async {
    final first = _block('aa', {
      'background': '#ff0000',
      'height': '60px',
      'color': 'transparent',
    });
    final next = _block('aa', {
      'background': '#0000ff',
      'margin-top': '-40px',
      'color': 'transparent',
    });
    final data = await _render([first, next]);
    expect(_pixel(data, 80, 25), [0, 0, 255, 255]);
  });

  test('静态祖先内的负层级覆盖块仍先于后续普通流背景绘制', () async {
    final parent = PageContainer(style: ComputedStyle({}), left: 0, width: 200);
    final behind =
        _block(' ', {
          'position': 'absolute',
          'z-index': '-1',
          'background': '#ff0000',
          'width': '120px',
          'height': '120px',
        }).withSpacing(
          containers: [
            PageContainerFragment(
              container: parent,
              startsHere: true,
              endsHere: true,
            ),
          ],
        );
    final front = _block('aa', {
      'background': '#0000ff',
      'height': '120px',
      'color': 'transparent',
    });
    final data = await _render([behind, front]);
    expect(_pixel(data, 80, 8), [0, 0, 255, 255]);
  });

  test('高层不透明背景遮住低层文字', () async {
    const positioned = {
      'position': 'absolute',
      'left': '0',
      'top': '0',
      'width': '120px',
      'height': '120px',
    };
    final data = await _render([
      _block('aa', {...positioned, 'z-index': '1'}),
      _block(' ', {...positioned, 'z-index': '2', 'background': '#ff0000'}),
    ]);
    expect(_pixel(data, 8, 8), [255, 0, 0, 255]);
    expect(_pixel(data, 60, 60), [255, 0, 0, 255]);
  });

  test('同元素背景与文字只应用一次透明度', () async {
    final data = await _render([
      _block('aa', {
        'width': '120px',
        'height': '120px',
        'background': '#000000',
        'opacity': '0.5',
      }),
    ]);
    final glyph = _pixel(data, 8, 8);
    expect(glyph, _pixel(data, 60, 60));
    expect(glyph.first, closeTo(128, 2));
  });

  test('表格内容只应用一次左外边距', () async {
    final content = _block('a', {
      'background': '#ff0000',
      'color': 'transparent',
    });
    final tableStyle = ComputedStyle({'margin-left': '22px'});
    final table = PageBlock.styled(
      layout: content.layout,
      style: tableStyle,
      containingWidth: 200,
      table: TableRenderSpec(
        cells: [
          TableCellRender(
            row: 0,
            rect: const Rect.fromLTWH(0, 0, 120, 16),
            layout: content.layout,
            style: content.style!,
          ),
        ],
        columnXs: const [0, 120],
        rowYs: const [0, 16],
        tableWidth: 120,
      ),
    );
    final data = await _render([table]);
    expect(_pixel(data, 18, 8), [255, 255, 255, 255]);
    expect(_pixel(data, 23, 1), [255, 0, 0, 255]);
    expect(_pixel(data, 141, 8), [255, 0, 0, 255]);
    expect(_pixel(data, 143, 8), [255, 255, 255, 255]);
  });

  test('嵌套容器分别绘制半透明背景', () async {
    final style = ComputedStyle({'background': 'rgba(0,0,0,0.5)'});
    final outer = PageContainer(style: style, left: 10, width: 180);
    final inner = PageContainer(style: style, left: 20, width: 160);
    final block = _block(' ', {}).withSpacing(
      topInset: 20,
      bottomInset: 20,
      containers: [
        PageContainerFragment(
          container: outer,
          startsHere: true,
          endsHere: true,
          topInset: 20,
          bottomInset: 20,
        ),
        PageContainerFragment(
          container: inner,
          startsHere: true,
          endsHere: true,
          topInset: 10,
          bottomInset: 10,
        ),
      ],
    );
    final data = await _render([block]);
    expect(_pixel(data, 15, 5).first, closeTo(128, 2));
    expect(_pixel(data, 25, 20).first, closeTo(64, 2));
  });

  test('半透明表格背景不会在单元格绘制阶段重复叠加', () async {
    final content = _block(' ', {});
    final table = PageBlock.styled(
      layout: content.layout,
      style: ComputedStyle({'background': 'rgba(0,0,0,0.5)'}),
      containingWidth: 200,
      table: const TableRenderSpec(
        cells: [],
        columnXs: [0, 120],
        rowYs: [0, 16],
        tableWidth: 120,
      ),
    );
    final data = await _render([table]);
    expect(_pixel(data, 60, 8).first, closeTo(128, 2));
  });

  test('隐藏容器仍允许后代显式恢复可见', () async {
    final container = PageContainer(
      style: ComputedStyle({'visibility': 'hidden', 'background': '#ff0000'}),
      left: 0,
      width: 200,
    );
    final block = _block('aa', {'visibility': 'visible'}).withSpacing(
      containers: [
        PageContainerFragment(
          container: container,
          startsHere: true,
          endsHere: true,
        ),
      ],
    );
    final data = await _render([block]);
    expect(_pixel(data, 8, 8), [0, 0, 0, 255]);
    expect(_pixel(data, 80, 8), [255, 255, 255, 255]);
  });

  test('祖先透明度作为整组效果，子块不再次乘祖先透明度', () async {
    final parent = ComputedStyle({'background': '#000', 'opacity': '0.5'});
    final child = ComputedStyle({'background': '#000'}, parent: parent);
    final container = PageContainer(style: parent, left: 0, width: 200);
    final content = _block('aa', {});
    final block =
        PageBlock.styled(
          layout: content.layout,
          style: child,
          containingWidth: 200,
          effectiveOpacity: 0.5,
        ).withSpacing(
          topInset: 10,
          bottomInset: 10,
          containers: [
            PageContainerFragment(
              container: container,
              startsHere: true,
              endsHere: true,
              topInset: 10,
              bottomInset: 10,
            ),
          ],
        );
    final data = await _render([block]);
    expect(_pixel(data, 80, 5).first, closeTo(128, 2));
    expect(_pixel(data, 80, 16), _pixel(data, 80, 5));
    expect(_pixel(data, 8, 18), _pixel(data, 80, 5));
  });

  test('跨页容器只在真正首尾绘制上下边框', () async {
    final container = PageContainer(
      style: ComputedStyle({
        'background': '#0000ff',
        'border': '2px solid #ff0000',
      }),
      left: 0,
      width: 160,
    );
    final block =
        _block('a\nb\nc\nd\ne', {
          'white-space': 'pre',
          'color': 'transparent',
        }).withSpacing(
          topInset: 2,
          bottomInset: 2,
          containers: [
            PageContainerFragment(
              container: container,
              startsHere: true,
              endsHere: true,
              topInset: 2,
              bottomInset: 2,
            ),
          ],
        );
    final pages = Paginator(
      pageHeight: 40,
      pageWidth: 200,
    ).measureChapter(blocks: [block]).pages;
    expect(pages.length, greaterThan(1));
    final first = await _renderPage(pages.first);
    final last = await _renderPage(pages.last);
    expect(_pixel(first, 80, 0), [255, 0, 0, 255]);
    expect(_pixel(first, 80, pages.first.usedHeight.toInt() - 1), [
      0,
      0,
      255,
      255,
    ]);
    expect(_pixel(last, 80, 0), [0, 0, 255, 255]);
    expect(_pixel(last, 80, pages.last.usedHeight.toInt() - 1), [
      255,
      0,
      0,
      255,
    ]);
  });
}
