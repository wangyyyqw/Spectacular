import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/stylesheet_loader.dart';

void main() {
  test('同步异步加载共用循环、深度、重复引用与媒体展开语义', () async {
    final tables = {
      'styles/a.css': CssParser.parse('@import "b.css" screen;a{color:red}'),
      'styles/b.css': CssParser.parse('@import "a.css";b{color:blue}'),
      for (var index = 0; index < 12; index++)
        'styles/$index.css': CssParser.parse(
          '@import "${index + 1}.css";p$index{color:red}',
        ),
    };
    const sources = [
      CssStyleSource.embedded('@import "a.css";i{color:black}'),
      CssStyleSource.linked('a.css', media: '(min-width:500px)'),
      CssStyleSource.linked('0.css'),
    ];
    final loader = CssStylesheetLoader(
      readSheet: (url) => tables[url]!,
      resolveUrl: (url, base) => p.posix.join(base, url),
      prepareInline: (css, _) => CssParser.parse(css),
    );
    final sync = loader.load(sources, 'styles');
    final async = await loader.loadAsync(
      sources,
      'styles',
      readSheetAsync: (url) async => tables[url]!,
      prepareInlineAsync: (css, _) async => CssParser.parse(css),
    );
    expect(_values(async), _values(sync));
    expect(sync.map((sheet) => sheet.rules.single.selector), [
      'b',
      'a',
      'i',
      'b',
      'a',
      for (var index = 8; index >= 0; index--) 'p$index',
    ]);
    expect(async[0].rules, same(async[3].rules));
    expect(async[3].mediaConditions, ['(min-width:500px)', 'screen']);
  });
}

List<Object> _values(List<CssStylesheet> sheets) => [
  for (final sheet in sheets)
    [
      sheet.mediaConditions,
      sheet.imports.length,
      sheet.warnings,
      for (final rule in sheet.rules)
        [
          rule.selector,
          for (final declaration in rule.declarations)
            [declaration.property, declaration.value, declaration.important],
        ],
    ],
];
