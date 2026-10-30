import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

/// `font-variant-caps` → OpenType 特性（测量与绘制共用 textStyleFor）。
ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

List<String> _tags(ComputedStyle style) =>
    (TextLayoutEngine.textStyleFor(style).fontFeatures ?? const <FontFeature>[])
        .map((feature) => feature.feature)
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('small-caps → smcp；all-small-caps → smcp + c2sc', () {
    expect(_tags(_style()), isEmpty, reason: 'normal 不带特性');
    expect(
      _tags(_style(const {'font-variant-caps': 'small-caps'})),
      contains('smcp'),
    );
    expect(
      _tags(_style(const {'font-variant-caps': 'all-small-caps'})),
      containsAll(<String>['smcp', 'c2sc']),
    );
  });

  test('font-variant 简写里的 caps 族同样生效', () {
    expect(
      _tags(_style(const {'font-variant': 'small-caps'})),
      contains('smcp'),
    );
  });

  test('font-variant-ligatures: none 关闭 liga 与 clig', () {
    final style = _style(const {'font-variant-ligatures': 'none'});
    expect(_tags(style), containsAll(<String>['liga', 'clig']));
    expect(
      (TextLayoutEngine.textStyleFor(style).fontFeatures ??
              const <FontFeature>[])
          .where((feature) => feature.value == 0)
          .length,
      2,
    );
  });

  test('font-kerning: none 关闭 kern 字偶距', () {
    final features = TextLayoutEngine.textStyleFor(
      _style(const {'font-kerning': 'none'}),
    ).fontFeatures;
    expect(features, contains(const FontFeature.disable('kern')));
    expect(
      TextLayoutEngine.textStyleFor(_style(const {'font-kerning': 'normal'}))
          .fontFeatures,
      isNull,
    );
  });

  test('font-stretch 映射到 wdth 可变字体轴', () {
    final condensed = TextLayoutEngine.textStyleFor(
      _style(const {'font-stretch': 'condensed'}),
    );
    expect(condensed.fontVariations, <FontVariation>[
      const FontVariation('wdth', 75),
    ]);
    expect(
      TextLayoutEngine.textStyleFor(_style()).fontVariations,
      isNull,
      reason: 'normal（100%）不覆盖字体默认宽度轴',
    );
  });

  test('其它 caps 族映射到对应 OpenType 标签', () {
    expect(
      _tags(_style(const {'font-variant-caps': 'petite-caps'})),
      contains('pcap'),
    );
    expect(
      _tags(_style(const {'font-variant-caps': 'all-petite-caps'})),
      containsAll(<String>['pcap', 'c2pc']),
    );
    expect(
      _tags(_style(const {'font-variant-caps': 'unicase'})),
      contains('unic'),
    );
    expect(
      _tags(_style(const {'font-variant-caps': 'titling-caps'})),
      contains('titl'),
    );
  });

  test('无 smcp 的字体：测量宽度不受影响、不报错', () {
    final normal = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(),
      maxWidth: 400,
    );
    final caps = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'font-variant-caps': 'small-caps'}),
      maxWidth: 400,
    );
    // Ahem 没有 smcp 特性 → 引擎按原样渲染，宽度一致（测量/绘制同口径）。
    expect(caps.lines.single.width, closeTo(normal.lines.single.width, 0.01));
    expect(caps.lineCount, normal.lineCount);
  });

  test('内置宋体按 Chromium 合成比例生成小型大写', () {
    final textStyle = TextLayoutEngine.textStyleFor(
      _style(const {
        'font-family': 'builtin_song',
        'font-variant-caps': 'small-caps',
      }),
    );
    expect(
      usesSyntheticSmallCaps(
        _style(const {
          'font-family': 'builtin_song',
          'font-variant-caps': 'all-small-caps',
        }),
      ),
      isTrue,
      reason: '规范名 builtin_song 本身也必须命中内置宋体',
    );
    final synthetic = buildSyntheticSmallCapsSpan(
      text: 'Abc小写',
      style: textStyle,
      caps: CssFontVariantCaps.smallCaps,
    ) as TextSpan;
    final children = synthetic.children!.cast<TextSpan>();
    expect(children.map((span) => span.text), <String>['A', 'BC', '小写']);
    expect(children[0].style!.fontSize, 16);
    expect(children[1].style!.fontSize, 11);
    expect(children[2].style!.fontSize, 16);
    final allSmall = buildSyntheticSmallCapsSpan(
      text: 'Abc-中',
      style: textStyle,
      caps: CssFontVariantCaps.allSmallCaps,
    ) as TextSpan;
    final allSmallChild = allSmall.children!.single as TextSpan;
    expect(allSmallChild.text, 'ABC-中');
    expect(allSmallChild.style!.fontSize, 11);
    final previous = LineBreaker.preserveFractionalLineHeight;
    LineBreaker.preserveFractionalLineHeight = true;
    try {
      final capsLayout = TextLayoutEngine.layout(
        text: 'abc',
        style: _style(const {
          'font-family': 'builtin_song',
          'font-variant-caps': 'small-caps',
        }),
        maxWidth: 400,
      );
      expect(capsLayout.lines.single.height, closeTo(24, 0.1));

      final inlineLayout = TextLayoutEngine.layout(
        text: 'Abc',
        style: _style(const {'font-family': 'builtin_song'}),
        runs: <StyledRun>[
          StyledRun(
            start: 0,
            end: 3,
            style: _style(const {
              'font-family': 'builtin_song',
              'font-size': '22px',
              'font-variant-caps': 'small-caps',
            }),
          ),
        ],
        maxWidth: 400,
      );
      expect(
        inlineLayout.lines.single.height,
        closeTo(33, 0.1),
        reason: '行盒取 22px 行内文字的行高，而不是混合字号导致的 38px',
      );
    } finally {
      LineBreaker.preserveFractionalLineHeight = previous;
    }
    expect(
      syntheticSmallCapsFromTextStyle(textStyle),
      CssFontVariantCaps.smallCaps,
    );
  });
}
