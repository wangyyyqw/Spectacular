import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_geometry.dart';
import 'package:reader_ui/decorations/decoration_painter.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/decorations/decoration_image_codec.dart';

import 'support/decoration_test_images.dart';

const _start = 'epubcfi(/6/2!/4/2/1:0)';
const _end = 'epubcfi(/6/2!/4/2/1:20)';
const _red = 0xFFFF0000;
const _green = 0xFF00FF00;
const _blue = 0xFF0000FF;
const _yellow = 0xFFFFFF00;

Future<ByteData> _pixels(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 180);
  picture.dispose();
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return pixels!;
}

int _alpha(ByteData pixels, int left, int top) =>
    pixels.getUint8((top * 240 + left) * 4 + 3);

int _color(ByteData pixels, int left, int top) {
  final offset = (top * 240 + left) * 4;
  return pixels.getUint8(offset + 3) << 24 |
      pixels.getUint8(offset) << 16 |
      pixels.getUint8(offset + 1) << 8 |
      pixels.getUint8(offset + 2);
}

PageContent _page({double width = 160, double lineHeight = 3}) {
  final style = ComputedStyle({
    'font-family': 'Ahem',
    'font-size': '16px',
    'line-height': '$lineHeight',
  });
  return Paginator(pageHeight: 180)
      .measureChapter(
        blocks: [
          PageBlock(
            layout: TextLayoutEngine.layout(
              text: 'abcdefghijklmnopqrst',
              style: style,
              maxWidth: width,
            ),
            style: style,
            startCfi: _start,
          ),
        ],
      )
      .pages
      .single;
}

ReaderDecorationRange _range(
  ReaderDecorationStyle style, {
  String start = _start,
  String end = _end,
}) => ReaderDecorationRange(startCfi: start, endCfi: end, style: style);

ReaderDecoration _decoration(String id, DateTime createdAt) => ReaderDecoration(
  id: id,
  startCfi: _start,
  endCfi: _end,
  quote: 'abcdefghijklmnopqrst',
  style: const ReaderDecorationStyle(backgroundColor: _yellow),
  createdAt: createdAt,
  updatedAt: createdAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('新增高亮兼容旧样式并完整保存，后应用样式按属性覆盖', () {
    final legacy = ReaderDecorationStyle.fromJson({'v': 1, 'color': _red});
    expect(legacy.highlight, isNull);
    expect(legacy.textColor, _red);
    expect(legacy.toJson(), {'v': 1, 'color': _red});
    final highlight = legacy.withValues({
      'highlight': const ReaderDecorationHighlight(
        style: ReaderAnnotationStyle.wavyUnderline,
        color: _blue,
        opacity: 0.6,
        strokeWidth: 2.5,
        joinLines: true,
      ).toJson(),
    });
    final restored = ReaderDecorationStyle.fromJson(highlight.toJson());
    expect(restored.highlight!.toJson(), highlight.highlight!.toJson());
    expect(
      restored
          .merge(const ReaderDecorationStyle(fontWeight: 700))
          .highlight!
          .toJson(),
      highlight.highlight!.toJson(),
    );
    expect(restored.withValues({'highlight': null}).highlight, isNull);
    expect(restored.changesMetrics, isFalse);
    final rule = ReaderDecorationRuleStyle.fromJson({
      'highlight': highlight.highlight!.toJson(),
    });
    expect(
      rule.decorationStyle.highlight!.toJson(),
      highlight.highlight!.toJson(),
    );
    expect(
      ReaderDecorationRuleStyle.fromJson(rule.toJson()).toJson(),
      rule.toJson(),
    );
    expect(rule.decorationStyle.changesMetrics, isFalse);
  });

  test('未知高亮样式忽略，非法颜色和数值在读取边界回退', () {
    expect(ReaderDecorationHighlight.fromJson({'style': 'unknown'}), isNull);
    final highlight = ReaderDecorationHighlight.fromJson({
      'style': 'underline',
      'color': -1,
      'opacity': 2,
      'strokeWidth': -10,
    })!;
    expect(highlight.color, defaultHighlightColor);
    expect(highlight.effectiveOpacity, 1);
    expect(highlight.strokeWidth, 0.5);
  });

  test('点九内容区与拉伸区完整往返，新图片不会继承旧图片切片', () {
    const nineSlice = ReaderDecorationNineSlice(
      slice: Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
      content: Rect.fromLTRB(0.2, 0.3, 0.8, 0.7),
      scale: 1.5,
    );
    const rule = ReaderDecorationRuleStyle(
      backgroundImagePath: '/local/bubble.png',
      backgroundImageFit: ReaderDecorationImageFit.nineSlice,
      backgroundImageNineSlice: nineSlice,
    );
    final restored = ReaderDecorationRuleStyle.fromJson(rule.toJson());
    expect(restored.backgroundImageNineSlice!.toJson(), nineSlice.toJson());
    expect(restored.decorationStyle.changesMetrics, isTrue);
    final replaced = restored.decorationStyle.merge(
      const ReaderDecorationStyle(backgroundImagePath: '/local/new.png'),
    );
    expect(replaced.backgroundImageNineSlice, isNull);
    final raw = nineSlice.toJson();
    expect(
      ReaderDecorationNineSlice.fromJson({
        ...raw,
        'content': {'left': 1, 'top': 0, 'right': 0, 'bottom': 1},
      }),
      isNull,
    );
    expect(
      ReaderDecorationNineSlice.fromJson({
        ...raw,
        'slice': {'left': double.nan, 'top': 0, 'right': 1, 'bottom': 1},
      }),
      isNull,
    );
  });

  test('点九PNG识别拉伸与内容标记，去除标记边并保留图案像素', () async {
    final decoded = await ReaderDecorationImageCodec.decode(
      await ninePatchTestBytes(),
    );
    addTearDown(decoded.image.dispose);
    expect(decoded.image.width, 30);
    expect(decoded.image.height, 20);
    expect(
      decoded.nineSlice!.slice,
      const Rect.fromLTRB(5 / 30, 5 / 20, 25 / 30, 15 / 20),
    );
    expect(
      decoded.nineSlice!.content,
      const Rect.fromLTRB(8 / 30, 7 / 20, 22 / 30, 13 / 20),
    );
    final pixels = await _pixels(
      (canvas) => canvas.drawImage(decoded.image, Offset.zero, Paint()),
    );
    expect(_color(pixels, 1, 1), _red);
    expect(_color(pixels, 29, 0), _blue);
    expect(_color(pixels, 1, 18), _green);
    expect(_color(pixels, 29, 19), _yellow);
  });

  test('普通图片生成点九PNG，四边标记按源像素取整且图案像素不变', () async {
    final source = await ReaderDecorationImageCodec.decode(
      await ninePatchTestBytes(),
    );
    addTearDown(source.image.dispose);
    const config = ReaderDecorationNineSlice(
      slice: Rect.fromLTRB(0.11, 0.17, 0.91, 0.83),
      content: Rect.fromLTRB(0.25, 0.35, 0.75, 0.65),
    );
    final bytes = await ReaderDecorationImageCodec.encodeNinePatch(
      source.image,
      config,
    );
    final decoded = await ReaderDecorationImageCodec.decode(bytes);
    addTearDown(decoded.image.dispose);
    expect(decoded.image.width, source.image.width);
    expect(decoded.image.height, source.image.height);
    expect(
      decoded.nineSlice!.slice,
      const Rect.fromLTRB(3 / 30, 3 / 20, 27 / 30, 17 / 20),
    );
    expect(
      decoded.nineSlice!.content,
      const Rect.fromLTRB(8 / 30, 7 / 20, 23 / 30, 13 / 20),
    );
    expect(
      decoded.nineSlice!.toJson(),
      ReaderDecorationImageCodec.pixelAligned(source.image, config).toJson(),
    );
    final originalPixels = (await source.image.toByteData())!;
    final restoredPixels = (await decoded.image.toByteData())!;
    expect(
      restoredPixels.buffer.asUint8List(),
      originalPixels.buffer.asUint8List(),
    );
  });

  test('点九拉伸仅改变中间，边角大小跟随字高，裁切不侵入相邻行', () async {
    final decoded = await ReaderDecorationImageCodec.decode(
      await ninePatchTestBytes(),
    );
    addTearDown(decoded.image.dispose);
    const config = ReaderDecorationNineSlice(
      slice: Rect.fromLTRB(5 / 30, 5 / 20, 25 / 30, 15 / 20),
      content: Rect.fromLTRB(5 / 30, 5 / 20, 25 / 30, 15 / 20),
    );
    const style = ReaderDecorationStyle(
      backgroundImageFit: ReaderDecorationImageFit.nineSlice,
      backgroundImageNineSlice: config,
    );
    for (final width in [30.0, 90.0]) {
      final pixels = await _pixels(
        (canvas) => ReaderDecorationPainter.paintBox(
          canvas,
          Rect.fromLTWH(20, 20, width, 10),
          style,
          image: decoded.image,
        ),
      );
      expect(_color(pixels, 16, 16), _red);
      expect(_color(pixels, 23, 23), 0xFFCCCCCC);
      expect(_color(pixels, (20 + width + 3).toInt(), 16), _blue);
      expect(_color(pixels, 16, 33), _green);
    }
    final larger = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(30, 30, 90, 20),
        style,
        image: decoded.image,
      ),
    );
    expect(_color(larger, 21, 21), _red);
    expect(_alpha(larger, 19, 21), 0);
    final clipped = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(20, 20, 90, 10),
        style,
        image: decoded.image,
        clipRect: const Rect.fromLTWH(0, 20, 160, 10),
      ),
    );
    expect(_alpha(clipped, 16, 16), 0);
    expect(_alpha(clipped, 23, 23), 255);
  });

  test('原生点九的内容边距不随文字长度拉伸，短句长句保留同样的边角', () async {
    final decoded = await ReaderDecorationImageCodec.decode(
      await ninePatchTestBytes(),
    );
    addTearDown(decoded.image.dispose);
    final config = decoded.nineSlice!;
    for (final width in [20.0, 80.0]) {
      final rect = Rect.fromLTWH(40, 40, width, 12);
      final bounds = config.imageRectFor(rect, const Size(30, 20));
      expect(bounds.left, closeTo(24, 0.001));
      expect(bounds.top, closeTo(26, 0.001));
      expect(bounds.right, closeTo(40 + width + 16, 0.001));
      expect(bounds.bottom, closeTo(66, 0.001));
      final pixels = await _pixels(
        (canvas) => ReaderDecorationPainter.paintBox(
          canvas,
          rect,
          ReaderDecorationStyle(
            backgroundImageFit: ReaderDecorationImageFit.nineSlice,
            backgroundImageNineSlice: config,
          ),
          image: decoded.image,
        ),
      );
      expect(_alpha(pixels, 23, 27), 0);
      expect(_color(pixels, 25, 27), _red);
      expect(_color(pixels, (40 + width + 14).toInt(), 27), _blue);
      expect(_color(pixels, 25, 64), _green);
    }
  });

  test('原生点九拉伸区与内容区独立，互不相交时仍可导入和保存', () async {
    final source = await ReaderDecorationImageCodec.decode(
      await ninePatchTestBytes(),
    );
    addTearDown(source.image.dispose);
    const config = ReaderDecorationNineSlice(
      slice: Rect.fromLTRB(0.6, 0.6, 0.9, 0.9),
      content: Rect.fromLTRB(0.1, 0.1, 0.4, 0.4),
    );
    expect(
      ReaderDecorationNineSlice.fromJson(config.toJson())!.toJson(),
      config.toJson(),
    );
    final decoded = await ReaderDecorationImageCodec.decode(
      await ReaderDecorationImageCodec.encodeNinePatch(source.image, config),
    );
    addTearDown(decoded.image.dispose);
    expect(decoded.image.width, 30);
    expect(decoded.image.height, 20);
    expect(decoded.nineSlice!.toJson(), config.toJson());
  });

  test('同一高亮被文字色切分后，波浪线和圆角背景保持连续像素', () async {
    final page = _page();
    for (final style in [
      ReaderAnnotationStyle.background,
      ReaderAnnotationStyle.wavyUnderline,
    ]) {
      final highlight = _range(
        ReaderDecorationStyle(
          highlight: ReaderDecorationHighlight(
            style: style,
            color: _red,
            joinLines: true,
          ),
        ),
      );
      final original = ReaderDecorationGeometry.boxesFor(page, [highlight]);
      final split = ReaderDecorationGeometry.boxesFor(page, [
        highlight,
        _range(
          const ReaderDecorationStyle(color: _blue),
          start: 'epubcfi(/6/2!/4/2/1:3)',
          end: 'epubcfi(/6/2!/4/2/1:7)',
        ),
      ]);
      expect(split.length, greaterThan(original.length));
      Future<ByteData> paint(List<ReaderDecorationBox> boxes) => _pixels(
        (canvas) => ReaderDecorationPainter.paintHighlights(
          canvas,
          boxes,
          foreground: style == ReaderAnnotationStyle.wavyUnderline,
        ),
      );
      expect(
        (await paint(split)).buffer.asUint8List(),
        (await paint(original)).buffer.asUint8List(),
      );
    }
  });

  test('点九命中被其他规则切分时共用整行图案，不重复边角', () async {
    final decoded = await ReaderDecorationImageCodec.decode(
      await ninePatchTestBytes(),
    );
    addTearDown(decoded.image.dispose);
    final page = _page();
    final image = _range(
      const ReaderDecorationStyle(
        backgroundImagePath: '/local/bubble.png',
        backgroundImageFit: ReaderDecorationImageFit.nineSlice,
        backgroundImageNineSlice: ReaderDecorationNineSlice(),
      ),
    );
    final original = ReaderDecorationGeometry.boxesFor(page, [image]);
    final split = ReaderDecorationGeometry.boxesFor(page, [
      image,
      _range(
        const ReaderDecorationStyle(color: _blue),
        start: 'epubcfi(/6/2!/4/2/1:3)',
        end: 'epubcfi(/6/2!/4/2/1:7)',
      ),
    ]);
    Future<ByteData> paint(List<ReaderDecorationBox> boxes) =>
        _pixels((canvas) {
          for (final box in boxes) {
            for (final rect in box.rects) {
              ReaderDecorationPainter.paintBox(
                canvas,
                rect,
                box.style,
                image: decoded.image,
                imageAnchor: box.imageAnchorFor(rect),
                clipRect: box.imageClipFor(rect, const Size(240, 180)),
              );
            }
          }
        });
    expect(
      (await paint(split)).buffer.asUint8List(),
      (await paint(original)).buffer.asUint8List(),
    );
  });

  test('四字点九经正式页面绘制保留四角，背景不侵入左右邻字', () async {
    final decoded = await ReaderDecorationImageCodec.decode(
      await ninePatchTestBytes(),
    );
    addTearDown(decoded.image.dispose);
    final config = decoded.nineSlice!;
    final size = Size(
      decoded.image.width.toDouble(),
      decoded.image.height.toDouble(),
    );
    const start = 'epubcfi(/6/2!/4/2/1:2)';
    const end = 'epubcfi(/6/2!/4/2/1:6)';
    const text = '前文彻底消失后文';
    final typography = ComputedStyle(const {
      'font-family': 'Ahem',
      'font-size': '16px',
      'line-height': '1.2',
    });
    final page = Paginator(pageHeight: 180, trimTextEdges: true)
        .measureChapter(
          blocks: [
            PageBlock(
              layout: TextLayoutEngine.layout(
                text: text,
                style: typography,
                maxWidth: 240,
                runs:
                    ReaderTextOverlayResolver([
                      ReaderTextOverlay(
                        startCfi: start,
                        endCfi: end,
                        paddingByTextHeight: config.paddingFor(size),
                      ),
                    ]).resolve(
                      blockCfi: _start,
                      text: text,
                      style: typography,
                      runs: const [],
                    ),
              ),
              style: typography,
              startCfi: _start,
            ),
          ],
        )
        .pages
        .single;
    final ranges = [
      _range(
        ReaderDecorationStyle(
          backgroundImagePath: '/local/bubble.9.png',
          backgroundImageFit: ReaderDecorationImageFit.nineSlice,
          backgroundImageNineSlice: config,
        ),
        start: start,
        end: end,
      ),
    ];
    final box = ReaderDecorationGeometry.boxesFor(page, ranges).single;
    final anchor = box.imageAnchorFor(box.rects.single);
    final bounds = config.imageRectFor(anchor, size);
    final pixels = await _pixels(
      (canvas) => PagePainter(
        beforeBlockText: (canvas, page, slice) {
          for (final box in ReaderDecorationGeometry.boxesFor(
            page,
            ranges,
            slice: slice,
          )) {
            for (final rect in box.rects) {
              ReaderDecorationPainter.paintBox(
                canvas,
                rect,
                box.style,
                image: decoded.image,
                imageAnchor: box.imageAnchorFor(rect),
                clipRect: box.imageClipFor(rect, const Size(240, 180)),
              );
            }
          }
        },
      ).paint(canvas, page, pageSize: const Size(240, 180)),
    );
    final left = (bounds.left + 3).floor();
    final right = (bounds.right - 3).floor();
    final top = (bounds.top + 3).floor();
    final bottom = (bounds.bottom - 3).floor();
    expect(_color(pixels, left, top), _red);
    expect(_color(pixels, right, top), _blue);
    expect(_color(pixels, left, bottom), _green);
    expect(_color(pixels, right, bottom), _yellow);
    expect(bounds.left, closeTo(32, 0.01));
    expect(bounds.right, lessThanOrEqualTo(240));
    expect(bounds.top, greaterThanOrEqualTo(-0.01));
    expect(bounds.bottom, lessThanOrEqualTo(page.usedHeight + 0.01));
  });

  test('竖排点九随字宽等比旋转，圆角高亮不加深行距连接处', () async {
    final decoded = await ReaderDecorationImageCodec.decode(
      await ninePatchTestBytes(),
    );
    addTearDown(decoded.image.dispose);
    final vertical = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(40, 20, 10, 60),
        const ReaderDecorationStyle(
          backgroundImageFit: ReaderDecorationImageFit.nineSlice,
          backgroundImageNineSlice: ReaderDecorationNineSlice(
            slice: Rect.fromLTRB(5 / 30, 5 / 20, 25 / 30, 15 / 20),
            content: Rect.fromLTRB(5 / 30, 5 / 20, 25 / 30, 15 / 20),
          ),
        ),
        image: decoded.image,
        vertical: true,
      ),
    );
    expect(_color(vertical, 53, 16), _red);
    expect(_color(vertical, 53, 83), _blue);
    expect(_color(vertical, 37, 16), _green);
    final highlight = await _pixels(
      (canvas) => ReaderDecorationPainter.paintHighlightBackground(
        canvas,
        [
          [const Rect.fromLTWH(10, 10, 100, 20)],
          [const Rect.fromLTWH(10, 36, 100, 20)],
        ],
        const ReaderDecorationHighlight(
          color: _red,
          opacity: 0.5,
          borderRadius: 6,
          joinLines: true,
        ),
      ),
    );
    expect(_alpha(highlight, 10, 10), 0);
    expect(_alpha(highlight, 30, 29), inInclusiveRange(127, 128));
    expect(_alpha(highlight, 30, 33), inInclusiveRange(127, 128));
  });

  test('九种高亮经正式行几何和绘制入口生成不同像素，染色走文字覆盖', () async {
    final page = _page();
    final signatures = <String>{};
    for (final style in ReaderAnnotationStyle.values) {
      final decoration = ReaderDecorationStyle(
        highlight: ReaderDecorationHighlight(style: style, color: _red),
      );
      final boxes = ReaderDecorationGeometry.boxesFor(page, [
        _range(decoration),
      ]);
      final pixels = await _pixels((canvas) {
        ReaderDecorationPainter.paintHighlights(
          canvas,
          boxes,
          foreground: false,
        );
        ReaderDecorationPainter.paintHighlights(
          canvas,
          boxes,
          foreground: true,
        );
      });
      final bytes = pixels.buffer.asUint8List();
      expect(signatures.add(bytes.join(',')), isTrue, reason: style.name);
      if (style == ReaderAnnotationStyle.tint) {
        expect(bytes.every((value) => value == 0), isTrue);
        expect(decoration.textColor, _red);
        expect(decoration.textColorOpacity, style.defaultOpacity);
      } else {
        expect(bytes.any((value) => value != 0), isTrue, reason: style.name);
      }
    }
    expect(signatures, hasLength(9));
  });

  test('背景与线条分层绘制，高亮保留颜色自带透明度', () async {
    const rect = Rect.fromLTWH(10, 10, 120, 40);
    const highlight = ReaderDecorationHighlight(
      color: 0x80FF0000,
      opacity: 0.5,
    );
    final background = await _pixels(
      (canvas) => ReaderDecorationPainter.paintHighlight(
        canvas,
        rect,
        highlight,
        foreground: false,
      ),
    );
    expect(_alpha(background, 50, 30), inInclusiveRange(63, 64));
    final foreground = await _pixels(
      (canvas) => ReaderDecorationPainter.paintHighlight(
        canvas,
        rect,
        highlight,
        foreground: true,
      ),
    );
    expect(_alpha(foreground, 50, 30), 0);
  });

  test('跨行连块只填同一装饰的同段间隙，关闭后保留原空白', () async {
    final page = _page();
    for (final join in [false, true]) {
      final boxes = ReaderDecorationGeometry.boxesFor(page, [
        _range(
          ReaderDecorationStyle(
            highlight: ReaderDecorationHighlight(
              color: _red,
              opacity: 0.5,
              joinLines: join,
            ),
          ),
        ),
      ]);
      final upper = boxes.first.range.rects.single;
      final lower = boxes.last.range.rects.single;
      final pixels = await _pixels(
        (canvas) => ReaderDecorationPainter.paintHighlights(
          canvas,
          boxes,
          foreground: false,
        ),
      );
      expect(
        _alpha(pixels, 40, ((upper.bottom + lower.top) / 2).floor()),
        join ? inInclusiveRange(127, 128) : 0,
      );
      expect(
        _alpha(pixels, 40, upper.center.dy.floor()),
        inInclusiveRange(127, 128),
      );
    }
  });

  test('不同装饰不因同色而连块，重叠高亮只应用最后一个样式', () async {
    final page = _page();
    const style = ReaderDecorationStyle(
      highlight: ReaderDecorationHighlight(
        color: _red,
        opacity: 0.5,
        joinLines: true,
      ),
    );
    final separated = ReaderDecorationGeometry.boxesFor(page, [
      _range(style, end: 'epubcfi(/6/2!/4/2/1:10)'),
      _range(style, start: 'epubcfi(/6/2!/4/2/1:10)'),
    ]);
    final upper = separated.first.range.rects.single;
    final lower = separated.last.range.rects.single;
    final gap = ((upper.bottom + lower.top) / 2).floor();
    final separatePixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintHighlights(
        canvas,
        separated,
        foreground: false,
      ),
    );
    expect(_alpha(separatePixels, 40, gap), 0);
    final overlap = ReaderDecorationGeometry.boxesFor(page, [
      _range(style),
      _range(
        const ReaderDecorationStyle(
          highlight: ReaderDecorationHighlight(
            color: _blue,
            opacity: 0.5,
            joinLines: true,
          ),
        ),
      ),
    ]);
    final pixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintHighlights(
        canvas,
        overlap,
        foreground: false,
      ),
    );
    expect(_color(pixels, 40, gap), 0x80000080);
  });

  test('墨水屏把背景和染色变成黑线，竖排线条沿列绘制', () async {
    for (final style in [
      ReaderAnnotationStyle.background,
      ReaderAnnotationStyle.halfBackground,
      ReaderAnnotationStyle.tint,
    ]) {
      final pixels = await _pixels(
        (canvas) => ReaderDecorationPainter.paintHighlight(
          canvas,
          const Rect.fromLTWH(10, 10, 40, 120),
          ReaderDecorationHighlight(style: style, color: _red),
          foreground: true,
          inkMode: true,
          vertical: true,
        ),
      );
      expect(_color(pixels, 10, 60), 0xFF000000);
      expect(_alpha(pixels, 30, 60), 0);
    }
  });

  test('多行装饰每行独立闭合，不把行间空白连接成外框', () async {
    final page = _page();
    final boxes = ReaderDecorationGeometry.boxesFor(page, [
      _range(
        const ReaderDecorationStyle(
          backgroundColor: _yellow,
          borderRadius: 4,
          borderTop: ReaderDecorationBorderSide(width: 2, color: _red),
          borderBottom: ReaderDecorationBorderSide(width: 2, color: _red),
        ),
      ),
    ]);
    expect(boxes, hasLength(2));
    final first = boxes.first.rects.single;
    final last = boxes.last.rects.single;
    final pixels = await _pixels((canvas) {
      for (final box in boxes) {
        ReaderDecorationPainter.paintBox(canvas, box.rects.single, box.style);
      }
    });
    expect(_color(pixels, 40, first.top.ceil()), _red);
    expect(_color(pixels, 40, last.top.ceil()), _red);
    expect(_color(pixels, 40, first.center.dy.floor()), _yellow);
    expect(_alpha(pixels, 40, ((first.bottom + last.top) / 2).floor()), 0);
  });

  test('背景透明度和圆角裁切均反映到真实像素', () async {
    final pixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 120, 60),
        const ReaderDecorationStyle(
          backgroundColor: _red,
          backgroundOpacity: 0.5,
          borderRadius: 12,
        ),
      ),
    );
    expect(_alpha(pixels, 10, 10), 0);
    expect(_alpha(pixels, 40, 30), inInclusiveRange(127, 128));
    expect(_alpha(pixels, 9, 40), 0);
  });

  test('普通图片各铺放模式按实际图片边界裁切圆角并保留中心', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(_red), BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(60, 60);
    picture.dispose();
    addTearDown(image.dispose);
    for (final fit in ReaderDecorationImageFit.values.where(
      (fit) => fit != ReaderDecorationImageFit.nineSlice,
    )) {
      final pixels = await _pixels(
        (canvas) => ReaderDecorationPainter.paintBox(
          canvas,
          const Rect.fromLTWH(10, 10, 120, 60),
          ReaderDecorationStyle(
            backgroundImageFit: fit,
            borderRadius: 12,
            backgroundOpacity: .5,
          ),
          image: image,
        ),
      );
      final left = fit == ReaderDecorationImageFit.contain ? 40 : 10;
      expect(_alpha(pixels, left, 10), 0, reason: fit.name);
      expect(_alpha(pixels, 70, 40), inInclusiveRange(127, 128));
      expect(_alpha(pixels, 9, 40), 0);
    }
  });

  test('点九圆角裁切完整图案，保留外扩、分片锚点与竖排旋转', () async {
    final decoded = await ReaderDecorationImageCodec.decode(
      await ninePatchTestBytes(),
    );
    addTearDown(decoded.image.dispose);
    const config = ReaderDecorationNineSlice(
      slice: Rect.fromLTRB(5 / 30, 5 / 20, 25 / 30, 15 / 20),
      content: Rect.fromLTRB(5 / 30, 5 / 20, 25 / 30, 15 / 20),
    );
    const style = ReaderDecorationStyle(
      backgroundImageFit: ReaderDecorationImageFit.nineSlice,
      backgroundImageNineSlice: config,
      borderRadius: 8,
    );
    const anchor = Rect.fromLTWH(40, 40, 80, 20);
    final normal = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        anchor,
        style,
        image: decoded.image,
      ),
    );
    expect(_alpha(normal, 30, 30), 0);
    expect(_alpha(normal, 39, 31), 255); // 完整图案外扩依然保留。
    expect(_alpha(normal, 60, 50), 255);
    final sliced = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(40, 40, 40, 20),
        style,
        image: decoded.image,
        imageAnchor: anchor,
        clipRect: const Rect.fromLTRB(0, 0, 80, 180),
      ),
    );
    expect(_alpha(sliced, 30, 30), 0);
    expect(_color(sliced, 79, 40), _color(normal, 79, 40));
    expect(_alpha(sliced, 81, 40), 0);
    final vertical = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(40, 40, 20, 80),
        style,
        image: decoded.image,
        vertical: true,
      ),
    );
    expect(_alpha(vertical, 30, 30), 0);
    expect(_alpha(vertical, 31, 40), 255);
    expect(_alpha(vertical, 50, 70), 255);
  });

  test('四边不同宽度和颜色独立绘制，内部保持透明', () async {
    final pixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 120, 60),
        const ReaderDecorationStyle(
          borderTop: ReaderDecorationBorderSide(width: 2, color: _red),
          borderRight: ReaderDecorationBorderSide(width: 4, color: _green),
          borderBottom: ReaderDecorationBorderSide(width: 6, color: _blue),
          borderLeft: ReaderDecorationBorderSide(width: 3, color: _yellow),
        ),
      ),
    );
    expect(_color(pixels, 50, 10), _red);
    expect(_alpha(pixels, 50, 12), 0);
    expect(_color(pixels, 128, 40), _green);
    expect(_alpha(pixels, 125, 40), 0);
    expect(_color(pixels, 50, 65), _blue);
    expect(_alpha(pixels, 50, 63), 0);
    expect(_color(pixels, 11, 40), _yellow);
    expect(_alpha(pixels, 13, 40), 0);
    expect(_alpha(pixels, 50, 40), 0);
  });

  test('实线双线虚线点线生成四种不同边框像素', () async {
    final signatures = <String>{};
    for (final lineStyle in ReaderDecorationBorderStyle.values) {
      const side = ReaderDecorationBorderSide(width: 6, color: _blue);
      final pixels = await _pixels(
        (canvas) => ReaderDecorationPainter.paintBox(
          canvas,
          const Rect.fromLTWH(10, 10, 120, 60),
          ReaderDecorationStyle(
            borderStyle: lineStyle,
            borderTop: side,
            borderRight: side,
            borderBottom: side,
            borderLeft: side,
          ),
        ),
      );
      expect(_alpha(pixels, 50, 40), 0);
      expect(pixels.buffer.asUint8List().any((value) => value != 0), isTrue);
      expect(
        signatures.add(pixels.buffer.asUint8List().join(',')),
        isTrue,
        reason: lineStyle.name,
      );
    }
    expect(signatures, hasLength(4));
  });

  test('背景图片采用cover居中裁切，缺失时保留背景色', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final (left, color) in [(0.0, _red), (10.0, _green), (20.0, _blue)]) {
      canvas.drawRect(
        Rect.fromLTWH(left, 0, 10, 10),
        Paint()..color = Color(color),
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(30, 10);
    picture.dispose();
    addTearDown(image.dispose);
    const style = ReaderDecorationStyle(
      backgroundColor: _yellow,
      backgroundImagePath: '/local/background.png',
      borderRadius: 6,
    );
    final pixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 30, 30),
        style,
        image: image,
      ),
    );
    expect(_color(pixels, 14, 25), _green);
    expect(_color(pixels, 35, 25), _green);
    expect(_alpha(pixels, 10, 10), 0);
    final missing = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 30, 30),
        style,
      ),
    );
    expect(_color(missing, 25, 25), _yellow);
  });

  test('五种图片铺放方式生成不同像素，规则样式完整往返且不改变度量', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final (left, color) in [(0.0, _red), (10.0, _green), (20.0, _blue)]) {
      canvas.drawRect(
        Rect.fromLTWH(left, 0, 10, 10),
        Paint()..color = Color(color),
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(30, 10);
    picture.dispose();
    addTearDown(image.dispose);
    final signatures = <String>{};
    for (final fit in ReaderDecorationImageFit.values) {
      final rule = ReaderDecorationRuleStyle(
        backgroundColor: _yellow,
        backgroundImagePath: '/local/texture.png',
        backgroundImageFit: fit,
        backgroundOpacity: 0.7,
        borderRadius: 4,
      );
      final style = ReaderDecorationRuleStyle.fromJson(rule.toJson())
          .decorationStyle;
      expect(style.backgroundImagePath, '/local/texture.png');
      expect(style.backgroundImageFit, fit);
      expect(style.changesMetrics, fit == ReaderDecorationImageFit.nineSlice);
      final pixels = await _pixels(
        (canvas) => ReaderDecorationPainter.paintBox(
          canvas,
          const Rect.fromLTWH(10, 10, 90, 60),
          style,
          image: image,
        ),
      );
      expect(
        signatures.add(pixels.buffer.asUint8List().join(',')),
        isTrue,
        reason: fit.name,
      );
    }
    expect(
      ReaderDecorationStyle.fromJson({'backgroundImagePath': '/legacy.png'})
          .backgroundImageFit,
      ReaderDecorationImageFit.cover,
    );
  });

  test('绘制内边距不改变布局，垂直扩展受行距余量和8dp双重限制', () {
    final page = _page();
    final layout = page.slices.single.block.layout;
    final boxes = ReaderDecorationGeometry.boxesFor(page, [
      _range(
        const ReaderDecorationStyle(
          paddingTop: 12,
          paddingRight: 12,
          paddingBottom: 12,
          paddingLeft: 12,
        ),
      ),
    ]);
    for (final box in boxes) {
      final original = box.range.rects.single;
      final expanded = box.rects.single;
      final line = box.range.line.rect;
      expect(expanded.left, original.left - 12);
      expect(expanded.right, original.right + 12);
      expect(
        original.top - expanded.top,
        math.min(8, math.max(0, original.top - line.top)),
      );
      expect(
        expanded.bottom - original.bottom,
        math.min(8, math.max(0, line.bottom - original.bottom)),
      );
    }
    expect(page.slices.single.block.layout, same(layout));
    expect(layout.lineCount, 2);
  });

  test('重叠装饰逐属性合并，手工后者覆盖前者且点击选最新创建记录', () {
    final page = _page(width: 400);
    final boxes = ReaderDecorationGeometry.boxesFor(page, [
      _range(
        const ReaderDecorationStyle(color: _red, backgroundColor: _yellow),
      ),
      _range(
        const ReaderDecorationStyle(color: _blue, borderRadius: 4),
        start: 'epubcfi(/6/2!/4/2/1:5)',
        end: 'epubcfi(/6/2!/4/2/1:15)',
      ),
      _range(
        const ReaderDecorationStyle(fontWeight: 700),
        start: 'epubcfi(/6/2!/4/2/1:7)',
        end: 'epubcfi(/6/2!/4/2/1:9)',
      ),
    ]);
    expect(boxes, hasLength(5));
    expect(boxes.first.style.color, _red);
    expect(boxes[2].style.color, _blue);
    expect(boxes[2].style.backgroundColor, _yellow);
    expect(boxes[2].style.fontWeight, 700);
    expect(boxes[2].style.borderRadius, 4);
    expect(boxes.last.style.color, _red);
    final older = _decoration('older', DateTime(2026));
    final newer = _decoration('newer', DateTime(2026, 2));
    expect(
      ReaderDecorationGeometry.decorationAt(
        page,
        boxes[2].rects.single.center,
        [newer, older],
      )?.id,
      newer.id,
    );
    expect(
      ReaderDecorationGeometry.decorationAt(page, const Offset(10, 160), [
        newer,
        older,
      ]),
      isNull,
    );
  });

  test('墨水屏背景降级黑线，保留边框形状但不保留彩色', () async {
    final pixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 120, 60),
        const ReaderDecorationStyle(
          backgroundColor: _yellow,
          borderTop: ReaderDecorationBorderSide(width: 2, color: _red),
        ),
        inkMode: true,
      ),
    );
    expect(_color(pixels, 50, 10), 0xFF000000);
    expect(_color(pixels, 50, 69), 0xFF000000);
    expect(_alpha(pixels, 50, 40), 0);
  });
}
