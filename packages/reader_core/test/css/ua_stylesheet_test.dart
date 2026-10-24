import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/ua_stylesheet.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/position/cfi.dart';

ParsedElement _element(String tag) => ParsedElement(
      tag: tag,
      attributes: const <String, String>{},
      children: const <ParsedNode>[],
      start: 0,
      end: 0,
      cfi: EpubCfi.parse('epubcfi(/6/2!/4/2/1:0)')!,
    );

/// P7-03：UA 默认样式表——规则可解析、可层叠，块级覆盖层按标签叠加，
/// 行高继承遵循无单位因子语义（CSS 2.1 §10.8）。
void main() {
  group('uaStylesheetCss 解析', () {
    test('整体可解析且规则数符合分区预期', () {
      final rules = uaRules();
      // 分节数：隐藏 2 + 页面 1 + 流内容 3 + 标题 6 + 列表 4 + 表格 1 +
      // 短语 13 + hr 1 + center 1 + ruby 1 ≈ 33；放宽到 ≥30 防规则漏删。
      expect(rules.length, greaterThanOrEqualTo(30));
      expect(
        rules.every((rule) => rule.origin == CascadeOrigin.userAgent),
        isTrue,
      );
    });

    test('层叠可消费：h1 命中字号与避页底声明', () {
      final style = Cascade.compute(
        element: _element('h1'),
        ancestors: const <ParsedElement>[],
        rules: uaRules(),
      );
      expect(style.values['font-size'], '2em');
      expect(style.values['font-weight'], 'bold');
      expect(style.values['page-break-after'], 'avoid');
    });

    test('层叠可消费：noscript 声明 display:none', () {
      final style = Cascade.compute(
        element: _element('noscript'),
        ancestors: const <ParsedElement>[],
        rules: uaRules(),
      );
      expect(style.values['display'], 'none');
    });
  });

  group('UaBlockDefaults 覆盖层', () {
    final base = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'serif',
    });

    test('h1：字号 2em、加粗、上下边距按自身字号解算', () {
      final h1 = UaBlockDefaults.apply(base, 'h1')!;
      expect(h1.fontSize, 32);
      expect(h1.fontWeight, 700);
      // em 边距相对元素自身字号（CSS em 语义）：0.67em × 32。
      expect(h1.margin.top, closeTo(32 * 0.67, 0.01));
      expect(h1.margin.bottom, closeTo(32 * 0.67, 0.01));
      // 无单位行高因子按子元素字号重算：32 × 1.5 = 48。
      expect(h1.lineHeight, 48);
    });

    test('无覆盖标签返回 null（p 的段距待 P4-21 启用）', () {
      expect(UaBlockDefaults.apply(base, 'p'), isNull);
      expect(UaBlockDefaults.apply(base, 'body'), isNull);
      expect(UaBlockDefaults.declarationsFor('h7'), isEmpty);
    });

    test('blockquote：左右 40px 缩进、上下 1em', () {
      final quote = UaBlockDefaults.apply(base, 'blockquote')!;
      expect(quote.margin.left, 40);
      expect(quote.margin.right, 40);
      expect(quote.margin.top, 16);
    });

    test('pre：等宽字体；th：加粗居中', () {
      expect(UaBlockDefaults.apply(base, 'pre')!.fontFamilies, contains('monospace'));
      final th = UaBlockDefaults.apply(base, 'th')!;
      expect(th.fontWeight, 700);
      expect(th.textAlign, CssTextAlign.center);
    });
  });

  group('行高继承语义（CSS 2.1 §10.8）', () {
    test('无单位因子跨字号变化重算', () {
      final base = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
      });
      final child = ComputedStyle(
        const <String, String>{'font-size': '2em'},
        parent: base,
        explicitProperties: const <String>{'font-size'},
      );
      expect(child.fontSize, 32);
      expect(child.lineHeight, 48);
    });

    test('px 行高按绝对量继承（字号变化不放大）', () {
      final base = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '24px',
      });
      expect(base.unitlessLineHeightFactor, isNull);
      final child = ComputedStyle(
        const <String, String>{'font-size': '2em'},
        parent: base,
        explicitProperties: const <String>{'font-size'},
      );
      expect(child.fontSize, 32);
      expect(child.lineHeight, 24);
    });

    test('未声明行高时按绝对量继承（保持既有行为）', () {
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
      });
      final child = ComputedStyle(
        const <String, String>{'font-size': '2em'},
        parent: style,
        explicitProperties: const <String>{'font-size'},
      );
      // 引擎默认因子不是显式无单位声明：子级继承绝对行高不放大，
      // 与改动前行为一致（默认因子不参与跨字号重算）。
      expect(child.fontSize, 32);
      expect(child.lineHeight, style.lineHeight);
      expect(child.unitlessLineHeightFactor, isNull);
    });
  });
}
