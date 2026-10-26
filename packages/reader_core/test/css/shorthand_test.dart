import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/css/ua_stylesheet.dart';

/// P9 回归：`font` 简写展开与 -webkit- 对齐值。
void main() {
  ComputedStyle style(Map<String, String> declarations) =>
      ComputedStyle(declarations);

  test('font 简写展开字号/行高/字重/斜体/字族', () {
    final parsed = style(const <String, String>{
      'font': 'italic bold 20px/2 "宋体", serif',
    });
    expect(parsed.fontSize, 20);
    expect(parsed.lineHeightFactor, 2);
    expect(parsed.lineHeight, 40);
    expect(parsed.fontWeight, 700);
    expect(parsed.italic, isTrue);
    expect(parsed.fontFamily, '宋体');
    expect(parsed.fontFamilyFallback, contains('serif'));
  });

  test('font 简写不覆盖已声明的长属性', () {
    final parsed = style(const <String, String>{
      'font': 'bold 20px serif',
      'font-size': '14px',
    });
    expect(parsed.fontSize, 14);
    expect(parsed.fontWeight, 700);
  });

  test('font 简写支持无行高的百分比字号与系统关键字丢弃', () {
    final parsed = style(const <String, String>{'font': '120% serif'});
    expect(parsed.fontSize, greaterThan(0));
    final keyword = style(const <String, String>{'font': 'caption'});
    expect(keyword.fontSize, 16, reason: '系统关键字不支持时保持初始值');
  });

  test('-webkit-center 等对齐值映射', () {
    expect(
      style(const <String, String>{'text-align': '-webkit-center'}).textAlign,
      CssTextAlign.center,
    );
    expect(
      style(const <String, String>{'text-align': '-webkit-right'}).textAlign,
      CssTextAlign.right,
    );
  });

  test('background 简写拆出 repeat/position/size（P9-11）', () {
    final parsed = style(const <String, String>{
      'background': '#101820 url(../Images/bg.png) no-repeat center / cover',
    });
    expect(parsed.backgroundImage, '../Images/bg.png');
    expect(parsed.backgroundColor, const Color(0xFF101820));
    expect(parsed.backgroundRepeat, CssBackgroundRepeat.noRepeat);
    expect(parsed.backgroundSize.mode, CssBackgroundSizeMode.cover);
    expect(parsed.backgroundPosition.x.isPercent, isTrue);
  });

  test('background 简写不覆盖已声明的长属性', () {
    final parsed = style(const <String, String>{
      'background': 'url(a.png) no-repeat',
      'background-repeat': 'repeat-x',
    });
    expect(parsed.backgroundRepeat, CssBackgroundRepeat.repeatX);
  });

  test('list-style-type 长属性（P9-12）', () {
    expect(
      style(
        const <String, String>{'list-style-type': 'upper-roman'},
      ).listStyleType,
      CssListStyleType.upperRoman,
    );
  });

  test('list-style 简写在层叠层展开（P9-12）', () {
    CssListStyleType cascaded(String declarations) {
      final rules = <CascadeRule>[
        ...uaRules(),
        ...CascadeRule.fromStylesheet(
          CssParser.parse('ul.plain { $declarations }'),
          origin: CascadeOrigin.author,
          startOrder: 1000,
        ),
      ];
      return Cascade.compute(
        element: _Element('ul', const <String, String>{'class': 'plain'}),
        ancestors: const <SelectorElement>[],
        rules: rules,
      ).listStyleType;
    }

    expect(cascaded('list-style: square inside'), CssListStyleType.square);
    expect(cascaded('list-style: none'), CssListStyleType.none);
    // 作者简写要压过 UA 的 `ul { list-style-type: disc }`。
    expect(cascaded('list-style: upper-roman'), CssListStyleType.upperRoman);
  });
}

class _Element implements SelectorElement {
  const _Element(this.tag, this.attributes);

  @override
  final String tag;

  @override
  final Map<String, String> attributes;

  @override
  List<SelectorElement> get childElements => const <SelectorElement>[];
}
