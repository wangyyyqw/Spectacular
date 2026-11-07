import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

const _fragment =
    '甲乙丙丁戊己庚辛壬癸，“中文”与 Latin ffi AV 混排，'
    '相邻标点！？以及数字 123 后继续正文。';

Future<void> _fonts() async {
  for (final (families, stem) in [
    (['builtin_song', 'SpacedSongOracle'], 'SourceHanSerifCN'),
    (['builtin_hei', 'SpacedHeiOracle'], 'SourceHanSansSC'),
  ]) {
    for (final family in families) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Bold']) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              File('../../apps/reader_mobile/assets/fonts/$stem-$weight.otf')
                  .readAsBytesSync(),
            ),
          ),
        );
      }
      await loader.load();
    }
  }
}

ComputedStyle _style(String family, Map<String, String> css) => ComputedStyle({
  'font-family': family,
  'font-size': '21px',
  'line-height': '1.6',
  'text-spacing-trim': 'trim-all',
  ...css,
});

List<Object?> _geometry(TextLayoutResult layout) => [
  layout.text,
  layout.width,
  layout.height,
  layout.maxWidth,
  layout.isRtl,
  layout.writingMode,
  for (final line in layout.lines)
    [
      line.start,
      line.end,
      line.top,
      line.height,
      line.baseline,
      line.width,
      line.indent,
      line.offsetX,
      line.isLastLine,
      line.isHardBreak,
      line.justifyExtra,
      line.justifyMode,
      line.spacing?.fingerprint,
      line.ellipsized,
      line.ellipsisWidth,
      line.hyphenated,
      line.hyphenWidth,
    ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);

  test('同一宋体字库的内置名与自定义名保持长段断点和全部行几何', () {
    for (final css in [
      <String, String>{},
      {'font-size': '22px', 'text-align': 'justify'},
      {'text-indent': '2em', 'letter-spacing': '0.2px'},
      {'text-spacing-trim': 'trim-both', 'text-autospace': 'normal'},
    ]) {
      for (final width in [97.0, 244.0, 301.29999999999995]) {
        for (final scale in [1.0, 1.25]) {
          TextLayoutResult layout(String family) => TextLayoutEngine.layout(
            text: '$_fragment\n${_fragment * 8}',
            style: _style(family, css),
            maxWidth: width,
            textScaleFactor: scale,
          );
          expect(
            _geometry(layout('builtin_song')),
            _geometry(layout('SpacedSongOracle')),
            reason: '$css/$width/$scale',
          );
        }
      }
    }
  });

  test('同字库的宋黑混排、注音和上下标不因字体名改变布局', () async {
    Future<TextLayoutResult> layout(bool builtin) {
      final song = builtin ? 'builtin_song' : 'SpacedSongOracle';
      final hei = builtin ? 'builtin_hei' : 'SpacedHeiOracle';
      return TextLayoutEngine.layoutAsync(
        text: _fragment * 5,
        style: _style(song, {'text-align': 'justify'}),
        maxWidth: 244,
        runs: [
          StyledRun(start: 4, end: 18, style: _style(hei, {})),
          StyledRun(
            start: 21,
            end: 35,
            style: _style(hei, {'font-size': '28px'}),
          ),
          StyledRun(
            start: 47,
            end: 50,
            style: _style(song, {'font-size': '12px'}),
            baselineShift: -5,
          ),
        ],
        rubies: const [RubyAnnotation(start: 55, end: 57, text: '注音')],
        checkpoint: () async {},
      );
    }

    expect(_geometry(await layout(true)), _geometry(await layout(false)));
  });

  test('临界行宽和显式字体特性保留同字库的原生断行', () {
    for (final css in [
      <String, String>{},
      {'font-feature-settings': '"halt" 0'},
      {'font-stretch': '95%'},
    ]) {
      for (final width in [62.99, 63.0, 63.01, 125.99, 126.0, 126.01]) {
        TextLayoutResult layout(String family) => TextLayoutEngine.layout(
          text: '甲乙丙丁，戊己庚辛。壬癸甲乙丙丁戊己！',
          style: _style(family, css),
          maxWidth: width,
        );
        expect(
          _geometry(layout('builtin_hei')),
          _geometry(layout('SpacedHeiOracle')),
          reason: '$css/$width',
        );
      }
    }
  });
}
