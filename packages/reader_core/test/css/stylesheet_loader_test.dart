import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/stylesheet_loader.dart';

void main() {
  test('逐表等待加载，保留循环深度、重复引用与媒体展开语义', () async {
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
      readSheet: (url) async => tables[url]!,
      resolveUrl: (url, base) => p.posix.join(base, url),
      prepareInline: (css, _) async => CssParser.parse(css),
    );
    final sheets = await loader.load(sources, 'styles');
    expect(sheets.map((sheet) => sheet.rules.single.selector), [
      'b',
      'a',
      'i',
      'b',
      'a',
      for (var index = 8; index >= 0; index--) 'p$index',
    ]);
    expect(sheets[0].rules, same(sheets[3].rules));
    expect(sheets[3].mediaConditions, ['(min-width:500px)', 'screen']);
    expect(sheets.every((sheet) => sheet.imports.isEmpty), isTrue);
    expect(sheets[0].rules.single.declarations.single.value, 'blue');
    expect(sheets[1].rules.single.declarations.single.value, 'red');
  });
}
