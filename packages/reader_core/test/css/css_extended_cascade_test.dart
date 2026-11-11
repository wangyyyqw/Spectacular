import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';

class _Element implements SelectorElement {
  const _Element(this.tag);

  @override
  final String tag;
  @override
  Map<String, String> get attributes => const {'class': 'target'};
  @override
  List<SelectorElement> get childElements => const [];
}

ComputedStyle _compute(
  String declarations, {
  ComputedStyle? parent,
  String tag = 'p',
  CssValueContext? context,
}) => Cascade.compute(
  element: _Element(tag),
  ancestors: const [],
  parent: parent,
  rules: CascadeRule.fromStylesheet(
    CssParser.parse('$tag {$declarations}'),
    origin: CascadeOrigin.author,
  ),
  valueContext:
      context ?? const CssValueContext(viewportWidth: 300, viewportHeight: 600),
);

void main() {
  test('背景简写保留双轴平铺和普通锥形渐变', () {
    for (final axes in [
      ('space', 'round'),
      ('round', 'space'),
      ('repeat', 'no-repeat'),
    ]) {
      final style = _compute(
        'background:conic-gradient(transparent,red,blue) '
        '${axes.$1} ${axes.$2} center / 20px auto',
      );
      expect(style.backgroundGradient, isA<CssConicGradient>());
      expect(style.backgroundGradient!.stops.first.color.a, 0);
      expect(style.backgroundRepeat.x.name, axes.$1);
      expect(
        style.backgroundRepeat.y.name,
        axes.$2 == 'no-repeat' ? 'noRepeat' : axes.$2,
      );
      expect(style.backgroundSize.width!.value, 20);
    }
  });

  test('多层背景简写独立展开图像、重复和定位轴', () {
    final style = _compute(
      'background:conic-gradient(red,blue) round space top left,'
      'url(a.png) space round right bottom / 20px 30px blue',
    );
    final layers = style.backgroundLayers;
    expect(layers, hasLength(2));
    expect(layers.first.gradient, isA<CssConicGradient>());
    expect(layers.first.repeat.x.name, 'round');
    expect(layers.last.image, 'a.png');
    expect(layers.last.repeat.x.name, 'space');
    expect(layers.last.position.x.value, 100);
    expect(layers.last.position.y.value, 100);
  });

  test('简写在函数与字符串边界切词，并保留合法注释分隔', () {
    final background = _compute('background:url(a.png)/* 中间 () */space round');
    expect(background.backgroundImage, 'a.png');
    expect(background.backgroundRepeat.x.name, 'space');
    expect(background.backgroundRepeat.y.name, 'round');
    final marker = _compute('list-style:"A"inside');
    expect(marker.listStyleString, 'A');
    expect(marker.listStylePosition, CssListStylePosition.inside);
  });

  test('无效背景简写和不支持的锥形参数保留较早有效声明', () {
    for (final invalid in [
      'url(b.png) nonsense',
      'url(b.png) repeat-x round',
      'url(b.png) center / cover 20px',
      'conic-gradient(from 90deg,red,blue)',
      'conic-gradient(at center,red,blue)',
      'conic-gradient(red 0deg,blue)',
      'conic-gradient(red,blue,)',
      'repeating-conic-gradient(red,blue)',
    ]) {
      final style = _compute('background:url(a.png);background:$invalid');
      expect(style.backgroundImage, 'a.png', reason: invalid);
    }
    final invalidImage = _compute(
      'background-image:url(a.png);'
      'background-image:conic-gradient(from 90deg,red,blue)',
    );
    expect(invalidImage.backgroundImage, 'a.png');
  });

  test('分轴与简写按声明顺序、特异性及 important 竞争', () {
    final forward = _compute(
      'background-position:10% 20%;background-position-x:30%',
    );
    final reverse = _compute(
      'background-position-x:30%;background-position:10% 20%',
    );
    expect(forward.backgroundPosition.x.value, 30);
    expect(reverse.backgroundPosition.x.value, 10);
    final important = _compute(
      'background-position-x:80% !important;'
      'background:url(a) left bottom',
    );
    expect(important.backgroundPosition.x.value, 80);
    expect(important.backgroundPosition.y.value, 100);
    final specific = Cascade.compute(
      element: const _Element('p'),
      ancestors: const [],
      rules: CascadeRule.fromStylesheet(
        CssParser.parse(
          '.target{background-position-x:80%}'
          'p{background-position:left bottom}',
        ),
        origin: CascadeOrigin.author,
      ),
    );
    expect(specific.backgroundPosition.x.value, 80);
  });

  test('分轴继承保留完整列表，并以父计算字号解算长度', () {
    final parent = _compute(
      'font-size:20px;background-position-x:1em,30%,70%;'
      'background-position-y:2em,4px',
    );
    final child = _compute(
      'font-size:10px;background-image:url(a),url(b),url(c);'
      'background-position:inherit',
      parent: parent,
    );
    expect(child.backgroundLayers.map((v) => v.position.x.value), [20, 30, 70]);
    expect(child.backgroundLayers.map((v) => v.position.y.value), [40, 4, 40]);
    final override = _compute(
      'background-position:inherit !important;background-position-x:99%',
      parent: parent,
    );
    expect(override.backgroundPosition.x.value, 20);
  });

  test('无效定位不能改变另一轴，边缘偏移不冒充单轴支持', () {
    final style = _compute(
      'background-position-x:20%;background-position:garbage bottom;'
      'background-position-x:right 10px',
    );
    expect(style.backgroundPosition.x.value, 20);
    expect(style.backgroundPosition.y.value, 0);
  });

  test('字符串标记经过样式表和内联解析后保留原文与转义', () {
    final cases = <String, String>{
      r'"AbC中文★"': 'AbC中文★',
      r'"\41 bc"': 'Abc',
      r'"A\"B"': 'A"B',
      r'"A\\B"': r'A\B',
      r'"\1f680 "': '🚀',
      r'""': '',
      r'"inside none"': 'inside none',
    };
    for (final entry in cases.entries) {
      final style = _compute('list-style-type:${entry.key}');
      expect(style.listStyleString, entry.value, reason: entry.key);
      final inline = Cascade.compute(
        element: const _Element('p'),
        ancestors: const [],
        rules: const [],
        inlineDeclarations: CssParser.parseInlineDeclarations(
          'list-style-type:${entry.key}',
        ),
      );
      expect(inline.listStyleString, entry.value, reason: entry.key);
      expect(_compute('', parent: style).listStyleString, entry.value);
      expect(
        _compute('list-style-type:inherit', parent: style).listStyleString,
        entry.value,
      );
    }
  });

  test('列表简写 none 按已给出的字符串或图片分配，遗漏项重置', () {
    for (final value in ['none "A"', '"A" none']) {
      final style = _compute('list-style:$value');
      expect(style.listStyleString, 'A');
      expect(style.listStyleImage, isNull);
    }
    final image = _compute('list-style:url(marker.png) "A" inside');
    expect(image.listStyleString, 'A');
    expect(image.listStyleImage, 'marker.png');
    final reset = _compute('list-style:"A" inside;list-style:none');
    expect(reset.listStyleType, CssListStyleType.none);
    expect(reset.listStylePosition, CssListStylePosition.outside);
    final positionOnly = _compute('list-style-type:"A";list-style:inside');
    expect(positionOnly.listStyleType, CssListStyleType.disc);
    expect(positionOnly.listStyleString, isNull);
  });

  test('列表简写的全局值同时作用于三个长属性', () {
    final parent = _compute('list-style:"P" inside url(p.png)');
    for (final keyword in ['inherit', 'unset']) {
      final child = _compute(
        'list-style:"C";list-style:$keyword',
        parent: parent,
      );
      expect(child.listStyleString, 'P');
      expect(child.listStylePosition, CssListStylePosition.inside);
      expect(child.listStyleImage, 'p.png');
    }
    final initial = _compute(
      'list-style:"C";list-style:initial',
      parent: parent,
    );
    expect(initial.listStyleType, CssListStyleType.disc);
    expect(initial.listStylePosition, CssListStylePosition.outside);
    expect(initial.listStyleImage, isNull);
  });

  test('非法字符串简写不覆盖旧值，未知裸关键词沿用原降级', () {
    for (final invalid in [
      '"NEW" bogus',
      '"NEW" "OTHER"',
      'inside outside "NEW"',
      'none none "NEW"',
    ]) {
      final style = _compute('list-style-type:"OLD";list-style:$invalid');
      expect(style.listStyleString, 'OLD', reason: invalid);
    }
    final parent = _compute('list-style-type:upper-roman');
    expect(
      _compute('list-style-type:unknown', parent: parent).listStyleType,
      CssListStyleType.upperRoman,
    );
  });

  test('字符串中的 var 是字面量，变量回退的标点不截断函数', () {
    expect(
      _compute('list-style-type:"var(--missing)"').listStyleString,
      'var(--missing)',
    );
    expect(
      _compute('list-style:var(--missing,"A),B") inside').listStyleString,
      'A),B',
    );
    expect(
      _compute('--marker:"Var(--other)";list-style:var(--marker)')
          .listStyleString,
      'Var(--other)',
    );
  });

  test('字号简写检验行高，支持斜杠周围空白且不重复继承关键字', () {
    final parent = _compute('font-size:20px');
    final style = _compute('font:larger / 1.5 serif', parent: parent);
    expect(style.fontSize, 24);
    expect(style.lineHeight, 36);
    expect(_compute('font-size:inherit', parent: style).fontSize, 24);
    for (final invalid in [
      'large/invalid serif',
      'large/-1 serif',
      'large/1.5/2 serif',
    ]) {
      expect(_compute('font-size:20px;font:$invalid').fontSize, 20);
    }
  });

  test('根视口轴接受大小写与别名，锁定后不被 body 改写', () {
    for (final mode in ['VERTICAL-RL', 'tb-rl', 'tb-lr']) {
      final root = _compute(
        'writing-mode:$mode;padding-left:10vi',
        parent: ComputedStyle({}),
        tag: 'html',
      );
      expect(root.padding.left, 60, reason: mode);
    }
    final locked = const CssValueContext(
      viewportWidth: 300,
      viewportHeight: 600,
    ).withRootAxis(true);
    final body = _compute(
      'writing-mode:horizontal-tb;padding-left:10vi',
      tag: 'body',
      context: locked,
    );
    expect(body.padding.left, 60);
    final html = _compute(
      'writing-mode:horizontal-tb;padding-left:10vi',
      tag: 'html',
      context: locked,
    );
    expect(html.padding.left, 30);
    final direct = ComputedStyle({
      'writing-mode': 'horizontal-tb',
      'padding-left': '10vi',
    }, valueContext: locked);
    expect(direct.padding.left, 60);
  });

  test('内在宽度仅作用于 width，继承和文字覆盖保持独立模式', () {
    for (final value in ['min-content', 'max-content', 'fit-content']) {
      final style = _compute('width:$value');
      expect(style.intrinsicWidth, CssIntrinsicWidth.parse(value));
      expect(style.width, isNull);
      expect(style.computedValue('width'), value);
      expect(
        style.withTypography(fontSize: 32).intrinsicWidth,
        style.intrinsicWidth,
      );
      expect(
        _compute('width:inherit', parent: style).intrinsicWidth,
        style.intrinsicWidth,
      );
      expect(_compute('', parent: style).intrinsicWidth, isNull);
      final invalid = _compute(
        'height:20px;height:$value;min-width:30px;min-width:$value',
      );
      expect(invalid.height!.value, 20);
      expect(invalid.minWidth!.value, 30);
    }
  });

  test('阅读字号覆盖后多背景的 em 与 rem 几何保持作者基准', () {
    final style = _compute(
      'font-size:16px;background-image:url(a),url(b);'
      'background-position-x:1em;background-size:2rem 1em,2rem 1em',
    );
    final overridden = style.withTypography(fontSize: 32);
    expect(overridden.backgroundPosition.x.value, 16);
    expect(overridden.backgroundLayers.map((v) => v.position.x.value), [
      16,
      16,
    ]);
    expect(overridden.backgroundLayers.map((v) => v.size.width!.value), [
      32,
      32,
    ]);
    expect(overridden.backgroundLayers.map((v) => v.size.height!.value), [
      16,
      16,
    ]);
  });
}
