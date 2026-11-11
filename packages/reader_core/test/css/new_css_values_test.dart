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
  Map<String, String> get attributes => const {};
  @override
  List<SelectorElement> get childElements => const [];
}

ComputedStyle _compute(String declarations, {ComputedStyle? parent}) =>
    Cascade.compute(
      element: const _Element('p'),
      ancestors: const [],
      rules: CascadeRule.fromStylesheet(
        CssParser.parse('p { $declarations }'),
        origin: CascadeOrigin.author,
      ),
      parent: parent,
      rootFontSize: 16,
      valueContext: const CssValueContext(
        viewportWidth: 300,
        viewportHeight: 600,
      ),
    );

void main() {
  test('字号关键字在级联后产生实际字号，绝对档位不随父元素再次放大', () {
    const sizes = {
      'xx-small': 9.0,
      'x-small': 10.0,
      'small': 13.0,
      'medium': 16.0,
      'large': 18.0,
      'x-large': 24.0,
      'xx-large': 32.0,
      'xxx-large': 48.0,
    };
    final parent = ComputedStyle({'font-size': '30px'});
    for (final entry in sizes.entries) {
      expect(
        _compute('font-size: ${entry.key}', parent: parent).fontSize,
        entry.value,
        reason: entry.key,
      );
    }
    expect(_compute('font-size: larger', parent: parent).fontSize, 36);
    expect(_compute('font-size: smaller', parent: parent).fontSize, 25);
    final larger = _compute('font-size: larger', parent: parent);
    expect(_compute('font-size: inherit', parent: larger).fontSize, 36);
    expect(_compute('font-size: initial', parent: larger).fontSize, 16);
  });

  test('font 简写支持关键字行高与 ex，非法后声明不会覆盖有效字号', () {
    final style = _compute(
      'font: italic xxx-large/1.5 serif; font-size: bogus;',
    );
    expect(style.fontSize, 48);
    expect(style.lineHeight, 72);
    expect(style.italic, isTrue);
    final ex = _compute(
      'font: 2ex serif; letter-spacing: 1ex',
      parent: ComputedStyle({'font-size': '20px'}),
    );
    expect(ex.fontSize, 20);
    expect(ex.letterSpacing, 10);
    expect(_compute('padding-left: calc(1vw + 2ex)').padding.left, 19);
  });

  test('盒模型全部视口单位使用同一冻结视口', () {
    final style = _compute(
      'margin: 1vh 2vw; padding: 1vmin 1vmax; '
      'width: 50vw; height: 20vh; left: 3vi; top: 4vb',
    );
    expect(style.margin.top, 6);
    expect(style.margin.right, 6);
    expect(style.padding.top, 3);
    expect(style.padding.right, 6);
    expect(style.width!.resolve(90), 150);
    expect(style.height!.resolve(90), 120);
    expect(style.left!.resolve(300), 9);
    expect(style.top!.resolve(600), 24);
    expect(style.withTypography(fontSize: 28).valueContext.viewportHeight, 600);
  });

  test('逻辑视口单位使用根轴，嵌套元素书写模式不改变该轴', () {
    const context = CssValueContext(viewportWidth: 300, viewportHeight: 600);
    final root = ComputedStyle({
      'writing-mode': 'vertical-rl',
    }, valueContext: context);
    final child = ComputedStyle({
      'writing-mode': 'horizontal-tb',
      'padding-left': '10vi',
      'padding-top': '10vb',
    }, parent: root);
    expect(child.padding.left, 60);
    expect(child.padding.top, 30);
    expect(
      context.resolveValue('url(images/10vw.png) "2vh" 3vw'),
      'url(images/10vw.png) "2vh" 9.0px',
    );
  });
}
