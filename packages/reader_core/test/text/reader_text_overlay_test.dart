import 'dart:math';

import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart'
    show ReaderTextOverlay, ReaderTextOverlayResolver;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/text_cfi_map.dart';

const _blockCfi = 'epubcfi(/6/2!/4/2/1)';

ReaderTextOverlay _overlay(
  int start,
  int end, {
  double scale = 1,
  int? color,
}) => ReaderTextOverlay(
  startCfi: cfiWithCharOffset(_blockCfi, start),
  endCfi: cfiWithCharOffset(_blockCfi, end),
  fontSizeScale: scale,
  color: color,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('大量无关覆盖只对命中原文区间进行精确映射', () {
    String point(int paragraph, int offset) =>
        'epubcfi(/6/2!/4/${paragraph * 2 + 2}/1:$offset)';
    final overlays = [
      for (var paragraph = 0; paragraph < 4096; paragraph++)
        ReaderTextOverlay(
          startCfi: point(paragraph, 1),
          endCfi: point(paragraph, 3),
          fontSizeScale: 1.5,
        ),
    ]..shuffle(Random(7));
    final resolver = ReaderTextOverlayResolver(overlays);
    for (final paragraph in [0, 2048, 4095]) {
      final runs = resolver.resolve(
        blockCfi: point(paragraph, 0),
        text: '甲乙丙丁',
        style: ComputedStyle(const {'font-size': '16px'}),
        runs: const [],
      );
      expect(runs.map((run) => (run.start, run.end)), [(1, 3)]);
      expect(runs.single.style.fontSize, 24);
    }
    expect(resolver.metrics!.resolveCalls, 3);
    expect(resolver.metrics!.candidateChecks, 3);
  });

  test('乱序及跨章覆盖保持输入优先级，结果与原文交集一致', () {
    String point(int paragraph, int offset) =>
        'epubcfi(/6/2!/4/${paragraph * 2 + 2}/1:$offset)';
    final random = Random(43);
    final overlays = [
      const ReaderTextOverlay(
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/4!/4/2/1:2)',
        fontSizeScale: 1.25,
      ),
      for (var index = 0; index < 120; index++)
        (() {
          final first = random.nextInt(20);
          final last = first + random.nextInt(20 - first);
          return ReaderTextOverlay(
            startCfi: point(first, random.nextInt(4)),
            endCfi: point(last, 4 + random.nextInt(4)),
            fontSizeScale: index.isEven ? 1.5 : 2,
          );
        })(),
    ]..shuffle(random);
    final resolver = ReaderTextOverlayResolver(overlays);
    final style = ComputedStyle(const {'font-size': '16px'});
    for (var paragraph = 19; paragraph >= 0; paragraph--) {
      final cfi = point(paragraph, 0);
      final map = TextCfiMap.linear(EpubCfi.parse(cfi)!, 8);
      final runs = resolver.resolve(
        blockCfi: cfi,
        textCfis: map,
        text: '甲乙丙丁戊己庚辛',
        style: style,
        runs: const [],
      );
      for (var offset = 0; offset < 8; offset++) {
        var expected = 16.0;
        for (final overlay in overlays) {
          final interval = map.rangeFor(overlay.startCfi, overlay.endCfi);
          if (interval != null &&
              interval.$1 <= offset &&
              offset < interval.$2) {
            expected = 16 * overlay.fontSizeScale;
          }
        }
        final actual =
            runs
                .where((run) => run.start <= offset && offset < run.end)
                .lastOrNull
                ?.style
                .fontSize ??
            16;
        expect(actual, expected, reason: '第 $paragraph 段偏移 $offset');
      }
    }
  });

  test('候选范围来自各来源 run，保留乱序映射及元素半开边界', () {
    final builder = TextCfiMapBuilder()
      ..add(
        0,
        2,
        cfi: EpubCfi.parse('epubcfi(/6/2!/4/8/1)')!,
        sourceStart: 0,
        sourceEnd: 2,
      )
      ..add(
        2,
        3,
        cfi: EpubCfi.parse('epubcfi(/6/2!/4/4/2)')!,
        sourceStart: 0,
        sourceEnd: 0,
      )
      ..add(
        3,
        5,
        cfi: EpubCfi.parse('epubcfi(/6/2!/4/2/1)')!,
        sourceStart: 0,
        sourceEnd: 2,
      );
    final overlays = [
      const ReaderTextOverlay(
        startCfi: 'epubcfi(/6/2!/4/8/1:0)',
        endCfi: 'epubcfi(/6/2!/4/8/1:2)',
        fontSizeScale: 1.5,
      ),
      const ReaderTextOverlay(
        startCfi: 'epubcfi(/6/2!/4/4/2)',
        endCfi: 'epubcfi(/6/2!/4/4/3:0)',
        fontSizeScale: 2,
      ),
      const ReaderTextOverlay(
        startCfi: 'epubcfi(/6/2!/4/4/1:0)',
        endCfi: 'epubcfi(/6/2!/4/4/2)',
        fontSizeScale: 1.75,
      ),
    ];
    final resolver = ReaderTextOverlayResolver(overlays);
    final runs = resolver.resolve(
      blockCfi: _blockCfi,
      textCfis: builder.build(5),
      text: '甲乙图丙丁',
      style: ComputedStyle(const {'font-size': '16px'}),
      runs: const [],
    );
    expect(runs.map((run) => (run.start, run.end, run.style.fontSize)), [
      (0, 2, 24.0),
      (2, 3, 32.0),
    ]);
    expect(resolver.metrics!.candidateChecks, 2);
  });

  test('断言与侧偏不改变区间索引的文字位置顺序', () {
    final map = TextCfiMap.linear(
      EpubCfi.parse('epubcfi(/6/2[书]!/4/2[段]/1:0)')!,
      5,
    );
    final start = EpubCfi.parse('epubcfi(/6/2!/4/2/1:1[;s=a])')!;
    final end = EpubCfi.parse('epubcfi(/6/2!/4/2/1:4[;s=b])')!;
    expect(map.rangeForPoints(start, end), (1, 4));
    final resolver = ReaderTextOverlayResolver([
      ReaderTextOverlay(
        startCfi: start.serialize(),
        endCfi: end.serialize(),
        fontSizeScale: 2,
      ),
    ]);
    final runs = resolver.resolve(
      blockCfi: _blockCfi,
      textCfis: map,
      text: '甲😀乙丙',
      style: ComputedStyle(const {'font-size': '16px'}),
      runs: const [],
    );
    expect(runs.map((run) => (run.start, run.end)), [(1, 4)]);
  });

  test('后置普通图片清除重叠点九占位，普通图片本身不失效几何', () {
    final source = ComputedStyle(const {
      'font-family': 'Ahem',
      'font-size': '16px',
    });
    final plain = ReaderTextOverlay(
      startCfi: cfiWithCharOffset(_blockCfi, 0),
      endCfi: cfiWithCharOffset(_blockCfi, 4),
      paddingByTextHeight: EdgeInsets.zero,
    );
    expect(
      ReaderTextOverlayResolver([plain], colors: false).typographyFingerprint,
      '[]',
    );
    final resolver = ReaderTextOverlayResolver([
      ReaderTextOverlay(
        startCfi: plain.startCfi,
        endCfi: plain.endCfi,
        paddingByTextHeight: const EdgeInsets.all(0.5),
      ),
      plain,
    ], colors: false);
    final runs = resolver.resolve(
      blockCfi: _blockCfi,
      text: '甲乙丙丁',
      style: source,
      runs: const [],
    );
    expect(runs.single.inlinePadding, EdgeInsets.zero);
    expect(runs.single.leadingInset, 0);
    expect(runs.single.trailingInset, 0);
  });

  test('点九叠加字体回退片段时不重复计入作者块内边距', () {
    final style = ComputedStyle(const {
      'font-family': 'Ahem',
      'font-size': '16px',
      'padding': '8px',
    });
    final runs =
        ReaderTextOverlayResolver([
          ReaderTextOverlay(
            startCfi: cfiWithCharOffset(_blockCfi, 0),
            endCfi: cfiWithCharOffset(_blockCfi, 4),
            paddingByTextHeight: const EdgeInsets.all(0.5),
          ),
        ]).resolve(
          blockCfi: _blockCfi,
          text: '甲乙丙丁',
          style: style,
          runs: [
            StyledRun(
              start: 0,
              end: 4,
              style: style,
              syntheticFontFallback: true,
            ),
          ],
        );
    expect(runs.single.leadingInset, runs.single.inlinePadding.left);
    expect(runs.single.trailingInset, runs.single.inlinePadding.right);
  });

  test('行内字体覆盖完整保留作者非继承样式', () {
    final author = ComputedStyle(const {
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'serif',
      'background-color': '#ffeecc',
      'background-image': 'url(card.png)',
      'border': '2px dashed #112233',
      'border-radius': '6px',
      'padding': '3px 5px',
      'margin': '4px 7px',
      'opacity': '0.8',
      'text-decoration': 'underline',
      'font-feature-settings': '"liga" 0',
    });
    final result = author.withInlineTypography(
      fontFamily: '测试字体',
      fontSize: 24,
      fontWeight: 700,
      italic: true,
      letterSpacing: 2,
      color: const Color(0x80886644),
    );
    expect(result.fontFamily, '测试字体');
    expect(result.fontSize, 24);
    expect(result.lineHeight, 36);
    expect(result.fontWeight, 700);
    expect(result.italic, isTrue);
    expect(result.letterSpacing, 2);
    expect(result.color, const Color(0x80886644));
    expect(result.hasExplicitTextColor, isTrue);
    expect(result.backgroundColor, author.backgroundColor);
    expect(result.backgroundImage, author.backgroundImage);
    expect(result.borders, same(author.borders));
    expect(result.padding, same(author.padding));
    expect(result.margin, same(author.margin));
    expect(result.opacity, author.opacity);
    expect(result.textDecoration, author.textDecoration);
    expect(result.fontFeatureSettings, author.fontFeatureSettings);
    expect(author.withInlineTypography(), same(author));
  });

  test('颜色不会改变字体度量指纹', () {
    final author = ComputedStyle(const {'font-size': '16px'});
    expect(
      author
          .withInlineTypography(color: const Color(0xffff0000))
          .layoutFingerprint,
      author.layoutFingerprint,
    );
    final red = ReaderTextOverlayResolver([
      _overlay(1, 3, color: 0xffff0000),
    ], colors: false);
    final blue = ReaderTextOverlayResolver([
      _overlay(1, 3, color: 0xff0000ff),
    ], colors: false);
    expect(red.typographyFingerprint, blue.typographyFingerprint);
    expect(red.typographyFingerprint, '[]');
  });

  test('覆盖跨作者 run 切分，保留背景、基线与原文偏移', () {
    final base = ComputedStyle(const {'font-size': '16px'});
    final author = ComputedStyle(const {
      'background-color': '#ffeecc',
    }, parent: base);
    final runs =
        ReaderTextOverlayResolver([
          ReaderTextOverlay(
            startCfi: cfiWithCharOffset(_blockCfi, 1),
            endCfi: cfiWithCharOffset(_blockCfi, 4),
            fontSizeScale: 1.5,
            fontWeight: 700,
            italic: true,
            letterSpacingEm: 0.1,
          ),
        ]).resolve(
          blockCfi: _blockCfi,
          text: '甲😀乙丙',
          style: base,
          runs: [StyledRun(start: 0, end: 3, style: author, baselineShift: -3)],
        );
    expect(runs.map((run) => (run.start, run.end)), [(0, 1), (1, 3), (3, 4)]);
    expect(runs[1].style.fontSize, 24);
    expect(runs[1].style.fontWeight, 700);
    expect(runs[1].style.italic, isTrue);
    expect(runs[1].style.letterSpacing, closeTo(2.4, 0.001));
    expect(runs[1].baselineShift, -3);
    expect(runs[1].style.backgroundColor, author.backgroundColor);
    expect(runs[1].syntheticFontFallback, isFalse);
    expect(runs[2].syntheticFontFallback, isTrue);
  });

  test('重叠区间按属性覆盖，字号倍率不累乘', () {
    final base = ComputedStyle(const {'font-size': '16px'});
    final runs = ReaderTextOverlayResolver([
      _overlay(0, 4, scale: 1.5, color: 0xffff0000),
      _overlay(1, 3, scale: 2, color: 0xff0000ff),
    ]).resolve(blockCfi: _blockCfi, text: '甲乙丙丁', style: base, runs: const []);
    expect(runs[0].style.fontSize, 24);
    expect(runs[1].style.fontSize, 32);
    expect(runs[1].style.color, const Color(0xff0000ff));
    expect(runs[2].style.fontSize, 24);
  });

  test('已有块起点偏移正确折算为块内坐标', () {
    final base = ComputedStyle(const {'font-size': '16px'});
    final runs = ReaderTextOverlayResolver([_overlay(12, 14, scale: 2)])
        .resolve(
          blockCfi: cfiWithCharOffset(_blockCfi, 10),
          text: '甲乙丙丁戊',
          style: base,
          runs: const [],
        );
    expect(runs.single.start, 2);
    expect(runs.single.end, 4);
  });

  test('跨块覆盖分别裁剪，非法和反向 CFI 不生成覆盖', () {
    const secondCfi = 'epubcfi(/6/2!/4/4/1)';
    final base = ComputedStyle(const {'font-size': '16px'});
    final resolver = ReaderTextOverlayResolver([
      ReaderTextOverlay(
        startCfi: cfiWithCharOffset(_blockCfi, 2),
        endCfi: cfiWithCharOffset(secondCfi, 2),
        fontSizeScale: 2,
      ),
    ]);
    expect(
      resolver
          .resolve(
            blockCfi: _blockCfi,
            text: '甲乙丙丁',
            style: base,
            runs: const [],
          )
          .single
          .start,
      2,
    );
    expect(
      resolver
          .resolve(
            blockCfi: secondCfi,
            text: '甲乙丙丁',
            style: base,
            runs: const [],
          )
          .single
          .end,
      2,
    );
    expect(
      ReaderTextOverlayResolver([
        _overlay(3, 1, scale: 2),
        const ReaderTextOverlay(startCfi: '非法', endCfi: '非法', fontSizeScale: 2),
      ]).resolve(
        blockCfi: _blockCfi,
        text: '甲乙丙丁',
        style: base,
        runs: const [],
      ),
      isEmpty,
    );
  });
}
