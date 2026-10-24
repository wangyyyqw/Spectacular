import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/reader_contract.dart';

/// P7-17：阅读器私有契约层——`-reader-*` 属性与 `:-reader-*` 伪类只
/// 允许 UA/阅读器 origin 使用，作者 CSS 使用时剥除/丢弃并记诊断。
void main() {
  test('作者 CSS 使用私有属性：声明剥除并告警，其余声明保留', () {
    final sheet = CssParser.parse(
      'p { -reader-table-fit: scale; color: red; margin-top: 1em; }',
    );
    final warnings = <String>[];
    final rules = CascadeRule.fromStylesheet(
      sheet,
      origin: CascadeOrigin.author,
      warnings: warnings,
    );
    expect(rules, hasLength(1));
    final properties = rules.single.rule.declarations
        .map((declaration) => declaration.property)
        .toList();
    expect(properties, <String>['color', 'margin-top']);
    expect(
      warnings.any((w) => w.startsWith('E_READER_PRIVATE_IN_AUTHOR')),
      isTrue,
    );
    expect(warnings.any((w) => w.contains('-reader-table-fit')), isTrue);
  });

  test('作者 CSS 使用私有伪类：整条规则丢弃并告警', () {
    final sheet = CssParser.parse(
      'p:-reader-blank { margin-top: 2em; } p { color: blue; }',
    );
    final warnings = <String>[];
    final rules = CascadeRule.fromStylesheet(
      sheet,
      origin: CascadeOrigin.author,
      warnings: warnings,
    );
    expect(rules, hasLength(1), reason: '私有伪类规则整条丢弃');
    expect(rules.single.rule.selector, 'p');
    expect(
      warnings.any(
        (w) => w.startsWith('E_READER_PRIVATE_IN_AUTHOR') && w.contains('丢弃'),
      ),
      isTrue,
    );
  });

  test('UA origin 不受契约过滤（预留钩子可用）', () {
    final sheet = CssParser.parse(
      'table { -reader-table-fit: scale; } '
      'p:-reader-blank { margin-top: 0; }',
    );
    final rules = CascadeRule.fromStylesheet(
      sheet,
      origin: CascadeOrigin.userAgent,
    );
    expect(rules, hasLength(2), reason: 'UA 层私有钩子原样保留');
    expect(
      rules[0].rule.declarations.single.property,
      '-reader-table-fit',
    );
  });

  test('契约判定与预留台账', () {
    expect(ReaderContract.propertyIsPrivate('-reader-image-frame'), isTrue);
    expect(ReaderContract.propertyIsPrivate('-READER-TABLE-FIT'), isTrue);
    expect(ReaderContract.propertyIsPrivate('margin-top'), isFalse);
    expect(ReaderContract.selectorIsPrivate('p:-reader-source(txt)'), isTrue);
    expect(ReaderContract.selectorIsPrivate('p:hover'), isFalse);
    expect(ReaderContract.reservedProperties, contains('-reader-title-page'));
  });

  test('filterAuthorStylesheet 返回清洗规则与警告', () {
    final sheet = CssParser.parse(
      'h1 { -reader-title-page: center; font-size: 2em; }',
    );
    final (rules, warnings) = ReaderContract.filterAuthorStylesheet(
      sheet.rules,
    );
    expect(rules.single.declarations.single.property, 'font-size');
    expect(warnings, hasLength(1));
  });
}
