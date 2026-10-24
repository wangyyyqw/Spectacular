import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _size = Size(200, 200);

ComputedStyle _style(Map<String, String> extra) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...extra,
    });

PageContent _page(List<PageBlock> blocks) =>
    Paginator(pageHeight: 180).measureChapter(blocks: blocks).pages.first;

PageBlock _block(String text, Map<String, String> extra) {
  final style = _style(extra);
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: 180),
    style: style,
    containingWidth: 180,
  );
}

Future<ByteData> _render(PagePainter painter, PageContent page) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, page, pageSize: _size);
  final image = await recorder.endRecording().toImage(
    _size.width.round(),
    _size.height.round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _countColor(ByteData data, int rgba) {
  var count = 0;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    if (data.getUint32(i) == rgba) {
      count += 1;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('绘制阶段固定为 背景→块背景→块边框→文本→装饰→选区', () async {
    final page = _page([
      _block('aa', const {
        'background-color': '#ff0000',
        'border-top': '2px solid #0000ff',
      }),
      _block('bb', const {'text-emphasis': 'dot'}),
    ]);
    final phases = <PagePaintPhase>[];
    await _render(
      PagePainter(
        onPhase: phases.add,
        selection: const PageSelection([
          SelectedTextRange(sliceIndex: 0, start: 0, end: 1),
        ]),
      ),
      page,
    );

    expect(phases, [
      PagePaintPhase.background,
      PagePaintPhase.blockBackground,
      PagePaintPhase.blockBorder,
      PagePaintPhase.text,
      PagePaintPhase.decoration,
      PagePaintPhase.selection,
    ]);
  });

  test('选区最后绘制，覆盖在文字之上', () async {
    final page = _page([_block('aa', const {})]);

    final plain = await _render(const PagePainter(), page);
    final selected = await _render(
      const PagePainter(
        selectionColor: Color(0xFFFF0000),
        selection: PageSelection([
          SelectedTextRange(sliceIndex: 0, start: 0, end: 1),
        ]),
      ),
      page,
    );

    // 不透明红只出现在选区覆盖区域：无选区时不存在，选区时存在。
    expect(_countColor(plain, 0xFF0000FF), 0);
    expect(_countColor(selected, 0xFF0000FF), greaterThan(0));
  });

  test('无选区时不调用选区阶段之外的额外绘制', () async {
    final page = _page([_block('aa', const {})]);
    final phases = <PagePaintPhase>[];
    await _render(PagePainter(onPhase: phases.add), page);
    expect(phases.last, PagePaintPhase.selection);
    expect(phases.where((p) => p == PagePaintPhase.selection), hasLength(1));
  });
}
