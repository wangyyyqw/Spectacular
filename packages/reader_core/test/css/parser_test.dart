import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/epub/archive_reader.dart';

import '../support/corpus.dart';

const _css = '''
/* 头部注释 */
@import url("base.css");
@import "extra.css" screen;
body, p { color: #111; margin: 0 auto !important; }
@media screen and (min-width: 600px) {
  .title { font-size: 2em; }
  p { text-indent: 2em; }
}
@font-face { font-family: "Book"; src: url(book.otf); }
p { color: ; unknown: 1; bad: 2; }
''';

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('解析规则、媒体查询、!important 与 import', () {
    final result = CssParser.parse(_css);
    expect(result.rules, isNotEmpty);
    final bodyRule = result.rules.firstWhere((r) => r.selector == 'body, p');
    expect(bodyRule.media, isNull);
    expect(bodyRule.declarations.map((d) => d.property), contains('color'));
    final margin = bodyRule.declarations.firstWhere(
      (d) => d.property == 'margin',
    );
    expect(margin.important, isTrue);
    expect(result.imports, hasLength(2));
    expect(result.imports.first.url, 'base.css');
    expect(result.imports.last.media, 'screen');

    final mediaRules = result.rules.where((r) => r.media != null).toList();
    expect(mediaRules, hasLength(2));
    expect(mediaRules.first.media, contains('min-width'));
    expect(mediaRules.map((r) => r.selector), contains('.title'));
  });

  test('注释被忽略，非法声明被跳过并记录', () {
    final result = CssParser.parse(_css);
    expect(result.rules.any((r) => r.selector.contains('/*')), isFalse);
    final pRules = result.rules
        .where((r) => r.selector == 'p' && r.media == null)
        .toList();
    expect(pRules, hasLength(1));
    expect(pRules.single.declarations.map((d) => d.property), [
      'unknown',
      'bad',
    ]);
    expect(result.warnings, isNotEmpty);
    expect(result.warnings.any((w) => w.contains('跳过')), isTrue);
  });

  test('@media 嵌套展开且保留条件', () {
    const css = '''
@media screen {
  @media (min-width: 400px) {
    p { color: red; }
  }
}
''';
    final result = CssParser.parse(css);
    expect(result.rules, hasLength(1));
    expect(result.rules.single.selector, 'p');
    expect(result.rules.single.media, contains('screen'));
    expect(result.rules.single.media, contains('min-width'));
  });

  test('非法 CSS 不抛异常并返回 warnings', () {
    final result = CssParser.parse('a { color: ; } @media {');
    expect(result, isA<CssStylesheet>());
    expect(result.warnings, isNotEmpty);
  });

  test('从 XHTML 提取 style 与 stylesheet link', () {
    const xhtml = '''
<html><head>
<style>p { color: red; }</style>
<link rel="stylesheet" href="css/main.css"/>
<link rel="stylesheet" href="css/extra.css" title="x"/>
</head><body><p>x</p></body></html>
''';
    final styles = CssParser.extractFromXhtml(xhtml);
    expect(styles.css, contains('color: red'));
    expect(styles.links, <String>['css/main.css', 'css/extra.css']);
  });

  test('语法错误后分块恢复后续规则', () {
    const css =
        'p { color: red; } } .good { color: blue; } .tail { margin: 0; }';
    final result = CssParser.parse(css);
    final selectors = result.rules.map((rule) => rule.selector).toList();
    expect(selectors, contains('.good'));
    expect(selectors, contains('.tail'));
    expect(result.warnings, isNotEmpty);
  });

  test('样式来源保留交错顺序、重复引用及媒体条件', () {
    final result = CssParser.extractFromXhtml('''
<html><head>
<style media="screen">p { color: red; }</style>
<link rel="stylesheet" media="print" href="a.css"/>
<style media="(min-width: 400px)">p { color: blue; }</style>
<link rel="stylesheet" href="a.css"/>
</head></html>
''');
    expect(result.sources, hasLength(4));
    expect(result.sources.map((source) => source.href), [
      null,
      'a.css',
      null,
      'a.css',
    ]);
    expect(result.sources.map((source) => source.media), [
      'screen',
      'print',
      '(min-width: 400px)',
      null,
    ]);
    expect(result.sources[2].css, contains('color: blue'));
  });

  test('style 属性声明解析', () {
    final declarations = CssParser.parseStyleAttribute(
      'color: #333; margin: 1em !important',
    );
    expect(declarations, hasLength(2));
    expect(declarations[0].property, 'color');
    expect(declarations[1].important, isTrue);
  });

  test('真实 EPUB 的全部 CSS 可解析', () {
    final archive = EpubArchive.fromBytes(
      readSampleBytes(corpus, 'styles.epub')!,
    );
    final cssFiles = archive.names
        .where((name) => name.toLowerCase().endsWith('.css'))
        .toList();
    expect(cssFiles, isNotEmpty);
    var rules = 0;
    for (final name in cssFiles) {
      final css = archive.readString(name);
      expect(css, isNotNull, reason: name);
      final parsed = CssParser.parse(css!);
      rules += parsed.rules.length;
    }
    expect(rules, greaterThan(0));
  }, skip: skip);
}
