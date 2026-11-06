import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart'
    show ReaderTextOverlay, ReaderTextOverlayResolver;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/position/cfi.dart';

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
