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

  test('font 简写的相对长度单位忽略大小写，字体名称保留大小写', () {
    final parsed = ComputedStyle(
      const {'font': 'ITALIC .8REM/1.3 "ExampleFont", serif'},
      parent: style(const {'font-size': '10px'}),
      rootFontSize: 21,
    );
    expect(parsed.fontSize, closeTo(16.8, .001));
    expect(parsed.lineHeight, closeTo(16.8 * 1.3, .001));
    expect(parsed.italic, isTrue);
    expect(parsed.fontFamily, 'ExampleFont');
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

  test('background 简写里的渐变结构化（W2）', () {
    final parsed = style(const <String, String>{
      'background': 'linear-gradient(to right, #f00, rgba(0, 0, 255, 0.5)) '
          'no-repeat center / cover',
    });
    final gradient = parsed.backgroundGradient;
    expect(gradient, isA<CssLinearGradient>());
    final linear = gradient! as CssLinearGradient;
    expect(linear.angle, 90);
    expect(linear.stops, hasLength(2));
    expect(linear.stops.last.color.a, closeTo(0.5, 0.01));
    // 简写的其余部分照旧解析：渐变不能污染 repeat/size 分词。
    expect(parsed.backgroundRepeat, CssBackgroundRepeat.noRepeat);
    expect(parsed.backgroundSize.mode, CssBackgroundSizeMode.cover);
    expect(parsed.backgroundImage, isNull, reason: '渐变不是 url');
  });

  test('text-decoration 简写带线型与颜色（P9-18）', () {
    final parsed = style(const <String, String>{
      'text-decoration': 'underline dotted #ff0000',
    });
    expect(parsed.textDecoration, CssTextDecoration.underline);
    expect(parsed.textDecorationStyle, CssTextDecorationStyle.dotted);
    expect(parsed.textDecorationColor, const Color(0xFFFF0000));

    final longhand = style(const <String, String>{
      'text-decoration-line': 'line-through',
      'text-decoration-style': 'wavy',
      'text-decoration-color': '#00ff00',
    });
    expect(longhand.textDecoration, CssTextDecoration.lineThrough);
    expect(longhand.textDecorationStyle, CssTextDecorationStyle.wavy);
    expect(longhand.textDecorationColor, const Color(0xFF00FF00));
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

  test('font 简写在级联层展开，压过 UA 长属性与继承字号', () {
    ComputedStyle cascaded(String declarations) {
      final rules = <CascadeRule>[
        ...uaRules(),
        ...CascadeRule.fromStylesheet(
          CssParser.parse('h1.special { $declarations }'),
          origin: CascadeOrigin.author,
          startOrder: 1000,
        ),
      ];
      return Cascade.compute(
        element: _Element('h1', const <String, String>{'class': 'special'}),
        ancestors: const <SelectorElement>[],
        rules: rules,
        parent: ComputedStyle(const <String, String>{'font-size': '16px'}),
      );
    }

    final style = cascaded('font: 700 17px/1.6 serif');
    // 不展开时：UA `h1 { font-size: 2em; font-weight: bold }` 按属性名命中，
    // 字号会变成 32px、字重变成 bolder，作者整条 font 简写被静默丢弃。
    expect(style.fontSize, 17);
    expect(style.fontWeight, 700);
    expect(style.lineHeightFactor, 1.6);
    expect(style.fontFamily, 'serif');
    // 展开后长属性确实进了层叠结果：flat 管线重建样式时会把 values 里的
    // 键全部标成显式，长属性缺失就会让继承来的字号顶掉作者简写。
    expect(style.values['font-size'], '17px');
    expect(style.values['font-weight'], '700');
    expect(style.values['line-height'], '1.6');
  });

  test('内联 font 简写同样展开成长属性', () {
    final style = Cascade.compute(
      element: _Element('p', const <String, String>{}),
      ancestors: const <SelectorElement>[],
      rules: uaRules(),
      inlineDeclarations: CssParser.parseStyleAttribute(
        'font: italic 15px/1.4 "宋体"',
      ),
      parent: ComputedStyle(const <String, String>{'font-size': '20px'}),
    );
    expect(style.fontSize, 15);
    expect(style.italic, isTrue);
    expect(style.fontFamily, '宋体');
    expect(style.values['font-size'], '15px');
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
