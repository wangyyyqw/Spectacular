import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(200, 120);
const _pageColor = Color(0xFF000000);

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'color': '#ffffff',
  'background-color': '#ff0000',
  'margin': '20px',
});

PageContent _page({required bool bleed, bool verticalBleed = false}) {
  final style = _style();
  final block = PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: '出血',
      style: style,
      maxWidth: _pageSize.width - 40,
    ),
    style: style,
    containingWidth: _pageSize.width,
    bleedLeft: bleed,
    bleedRight: bleed,
    bleedTop: verticalBleed,
    bleedBottom: verticalBleed,
  );
  return Paginator(pageHeight: _pageSize.height)
      .measureChapter(blocks: <PageBlock>[block])
      .pages
      .single;
}

Future<ByteData> _render(
  PageContent page, {
  Size pageSize = _pageSize,
  EdgeInsets pageInsets = EdgeInsets.zero,
}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(background: _pageColor).paint(
    Canvas(recorder),
    page,
    pageSize: pageSize,
    pageInsets: pageInsets,
  );
  final image = await recorder.endRecording().toImage(
    pageSize.width.toInt(),
    pageSize.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

Color _pixel(ByteData bytes, int x, int y, [Size size = _pageSize]) {
  final offset = (y * size.width.toInt() + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

PageContainerFragment _containerFragment({bool root = false}) =>
    PageContainerFragment(
      container: PageContainer(
        style: ComputedStyle({'overflow': 'hidden'}),
        left: 0,
        width: 176,
        isPageRoot: root,
      ),
      startsHere: true,
      endsHere: true,
    );

PageContent _containerPage({
  required bool root,
  bool bleed = true,
  bool nestedClip = false,
}) {
  final block = PageBlock(
    layout: TextLayoutResult(
      text: '',
      lines: const [
        LineBox(start: 0, end: 0, top: 0, height: 40, baseline: 40, width: 176),
      ],
      width: 176,
      height: 40,
      maxWidth: 176,
      runs: const [],
    ),
    style: ComputedStyle({'background-color': '#ff0000'}),
    bleedLeft: bleed,
    bleedRight: bleed,
    bleedTop: bleed,
    containers: [
      _containerFragment(root: root),
      if (nestedClip) _containerFragment(),
    ],
  );
  return Paginator(
    pageHeight: 84,
    pageWidth: 176,
  ).measureChapter(blocks: [block]).pages.single;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('duokan-bleed 让背景延伸到页面边缘（P9-22）', () async {
    final data = await _render(_page(bleed: true));
    // 取块内容带（纵向 margin 20px 之后）验证左右出血。
    expect(_pixel(data, 0, 30), const Color(0xFFFF0000), reason: '左缘应出血');
    expect(
      _pixel(data, _pageSize.width.toInt() - 1, 30),
      const Color(0xFFFF0000),
      reason: '右缘应出血',
    );
    // 出血只作用于声明的左右边；纵向 margin 带仍是页面底色。
    expect(_pixel(data, 100, 10), _pageColor, reason: '上 margin 带不画背景');
    expect(_pixel(data, 100, 110), _pageColor, reason: '下 margin 带不画背景');
  });

  test('没有出血时保留页边距', () async {
    final data = await _render(_page(bleed: false));
    expect(_pixel(data, 0, 30), _pageColor, reason: '左缘应为页面底色');
    expect(
      _pixel(data, _pageSize.width.toInt() - 1, 30),
      _pageColor,
      reason: '右缘应为页面底色',
    );
    expect(_pixel(data, 30, 30), const Color(0xFFFF0000), reason: '块内应着色');
  });

  test('pageInsets 下出血块铺到整页边缘', () async {
    const insets = EdgeInsets.fromLTRB(12, 16, 12, 20);
    final data = await _render(
      _page(bleed: true, verticalBleed: true),
      pageInsets: insets,
      pageSize: const Size(220, 160),
    );
    // 四角都在页边之外的内缩里：出血块应铺满整页。
    expect(_pixel(data, 0, 0, const Size(220, 160)), const Color(0xFFFF0000));
    expect(
      _pixel(data, 219, 159, const Size(220, 160)),
      const Color(0xFFFF0000),
      reason: '右下角应贴页边',
    );
  });

  test('pageInsets 下非出血内容仍按内缩排布', () async {
    const insets = EdgeInsets.fromLTRB(12, 16, 12, 20);
    final data = await _render(
      _page(bleed: false),
      pageInsets: insets,
      pageSize: const Size(220, 160),
    );
    final size = const Size(220, 160);
    expect(_pixel(data, 0, 0, size), _pageColor, reason: '页边留白应是底色');
    // 块左缘 = pageInsets.left + margin.left，上缘 = pageInsets.top + margin.top。
    final blockLeft = insets.left.toInt() + _style().margin.left.toInt();
    final blockTop = insets.top.toInt() + _style().margin.top.toInt();
    expect(
      _pixel(data, blockLeft + 8, blockTop + 8, size),
      const Color(0xFFFF0000),
      reason: '块应从内缩处开始着色',
    );
  });

  test('根容器 overflow 裁到整页，不截掉左上右出血', () async {
    final data = await _render(
      _containerPage(root: true),
      pageInsets: const EdgeInsets.fromLTRB(12, 16, 12, 20),
    );
    expect(_pixel(data, 0, 0), const Color(0xFFFF0000));
    expect(_pixel(data, 199, 0), const Color(0xFFFF0000));
    expect(_pixel(data, 100, 119), _pageColor, reason: '未声明下出血');
  });

  test('根容器中的非出血块仍保留正文内缩', () async {
    final data = await _render(
      _containerPage(root: true, bleed: false),
      pageInsets: const EdgeInsets.fromLTRB(12, 16, 12, 20),
    );
    expect(_pixel(data, 0, 20), _pageColor);
    expect(_pixel(data, 199, 20), _pageColor);
    expect(_pixel(data, 100, 0), _pageColor);
    expect(_pixel(data, 100, 20), const Color(0xFFFF0000));
  });

  for (final root in [false, true]) {
    test('普通容器的 overflow 裁剪仍生效（外层根容器：$root）', () async {
      final data = await _render(
        _containerPage(root: root, nestedClip: root),
        pageInsets: const EdgeInsets.fromLTRB(12, 16, 12, 20),
      );
      expect(_pixel(data, 0, 20), _pageColor);
      expect(_pixel(data, 199, 20), _pageColor);
      expect(_pixel(data, 100, 0), _pageColor);
      expect(_pixel(data, 100, 20), const Color(0xFFFF0000));
    });
  }
}
