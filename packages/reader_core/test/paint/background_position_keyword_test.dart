import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(120, 80);
const _red = 0xFF0000FF;
const _white = 0xFFFFFFFF;
const _keywordPositions = <String, Offset>{
  'top center': Offset(50, 0),
  'center top': Offset(50, 0),
  'bottom center': Offset(50, 100),
  'center bottom': Offset(50, 100),
  'center left': Offset(0, 50),
  'left center': Offset(0, 50),
  'center right': Offset(100, 50),
  'right center': Offset(100, 50),
  'top left': Offset(0, 0),
  'left top': Offset(0, 0),
  'top right': Offset(100, 0),
  'right top': Offset(100, 0),
  'bottom left': Offset(0, 100),
  'left bottom': Offset(0, 100),
  'bottom right': Offset(100, 100),
  'right bottom': Offset(100, 100),
};

ComputedStyle _style(String declarations) => Cascade.compute(
  element: const _Element(),
  ancestors: const <SelectorElement>[],
  rules: const <CascadeRule>[],
  inlineDeclarations: CssParser.parseStyleAttribute(
    'width:120px; height:80px; $declarations',
  ),
  containingWidth: _pageSize.width,
);

void _expectPosition(CssBackgroundPosition actual, Offset expected) {
  expect(actual.x.isPercent, isTrue);
  expect(actual.y.isPercent, isTrue);
  expect(actual.x.value, expected.dx);
  expect(actual.y.value, expected.dy);
}

void _parsingTests() {
  test('双关键字位置按轴归一，关键字前后顺序不改变位置', () {
    for (final entry in _keywordPositions.entries) {
      _expectPosition(
        _style('background-position:${entry.key}').backgroundPosition,
        entry.value,
      );
    }
  });

  test('单关键字与长度百分比组合保留既有轴顺序', () {
    _expectPosition(
      _style('background-position:top').backgroundPosition,
      const Offset(50, 0),
    );
    _expectPosition(
      _style('background-position:right').backgroundPosition,
      const Offset(100, 50),
    );
    final length = _style('background-position:10px top').backgroundPosition;
    expect(length.x.isPercent, isFalse);
    expect(length.x.value, 10);
    expect(length.y.value, 0);
    final percent = _style('background-position:left 25%').backgroundPosition;
    _expectPosition(percent, const Offset(0, 25));
  });
}

void _layerParsingTest() {
  test('背景简写和多背景层同样按关键字所在轴定位', () {
    final shorthand = _style(
      'background:url(a.png) no-repeat bottom center / 16px 12px',
    );
    _expectPosition(shorthand.backgroundPosition, const Offset(50, 100));
    final style = _style(
      'background-image:url(a.png),url(b.png); '
      'background-position:bottom center,top center',
    );
    expect(style.backgroundLayers, hasLength(2));
    _expectPosition(style.backgroundLayers[0].position, const Offset(50, 100));
    _expectPosition(style.backgroundLayers[1].position, const Offset(50, 0));
  });
}

Future<ui.Image> _redImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFFFF0000), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  picture.dispose();
  return image;
}

PageContent _page(ComputedStyle style, {required bool wholePage}) {
  final blockStyle = wholePage ? _style('') : style;
  var page = Paginator(pageHeight: _pageSize.height)
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: TextLayoutResult(
              text: '',
              lines: const [],
              width: 120,
              height: 0,
              maxWidth: 120,
            ),
            style: blockStyle,
            containingWidth: _pageSize.width,
          ),
        ],
      )
      .pages
      .single;
  if (wholePage) {
    page = page.withBackground(
      PageBackground(
        imageUrl: style.backgroundImage!,
        size: style.backgroundSize,
        repeat: style.backgroundRepeat,
        position: style.backgroundPosition,
      ),
    );
  }
  return page;
}

Future<ByteData> _render(
  ComputedStyle style,
  ui.Image image, {
  required bool wholePage,
}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => image).paint(
    Canvas(recorder),
    _page(style, wholePage: wholePage),
    pageSize: _pageSize,
  );
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(120, 80);
  picture.dispose();
  final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  rendered.dispose();
  return data!;
}

int _pixel(ByteData bytes, Offset point) =>
    bytes.getUint32((point.dy.toInt() * 120 + point.dx.toInt()) * 4);

void _paintingTests() {
  const anchors = <String, Offset>{
    'top center': Offset(60, 6),
    'center top': Offset(60, 6),
    'bottom center': Offset(60, 74),
    'center bottom': Offset(60, 74),
    'center left': Offset(8, 40),
    'left center': Offset(8, 40),
    'center right': Offset(112, 40),
    'right center': Offset(112, 40),
  };
  for (final wholePage in [false, true]) {
    test('${wholePage ? '整页' : '块级'}背景双关键字实际绘制到正确边缘', () async {
      final image = await _redImage();
      addTearDown(image.dispose);
      for (final entry in anchors.entries) {
        final style = _style(
          'background-image:url(bg://red); background-size:16px 12px; '
          'background-repeat:no-repeat; background-position:${entry.key}',
        );
        final bytes = await _render(style, image, wholePage: wholePage);
        expect(_pixel(bytes, entry.value), _red, reason: entry.key);
        expect(
          _pixel(bytes, const Offset(60, 40)),
          _white,
          reason: '${entry.key} 不应退化为居中',
        );
      }
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _parsingTests();
  _layerParsingTest();
  _paintingTests();
}

class _Element implements SelectorElement {
  const _Element();

  @override
  String get tag => 'div';

  @override
  Map<String, String> get attributes => const {};

  @override
  List<SelectorElement> get childElements => const [];
}
