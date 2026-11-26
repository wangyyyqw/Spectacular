import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/editing/css_completion.dart';

({String text, int offset}) _input(String source) {
  final offset = source.indexOf('|');
  return (text: source.replaceFirst('|', ''), offset: offset);
}

CssCompletionRequest? _request(
  String source, {
  CssCompletionMode mode = CssCompletionMode.stylesheet,
  String? property,
  bool explicit = false,
}) {
  final input = _input(source);
  return completeCss(
    input.text,
    input.offset,
    mode: mode,
    property: property,
    explicit: explicit,
  );
}

({String text, int caret, CssCompletionItem item}) _apply(
  String source,
  String label, {
  CssCompletionMode mode = CssCompletionMode.stylesheet,
  String? property,
  bool explicit = false,
}) {
  final input = _input(source);
  final request = completeCss(
    input.text,
    input.offset,
    mode: mode,
    property: property,
    explicit: explicit,
  )!;
  final item = request.items.singleWhere((item) => item.label == label);
  return (
    text: input.text.replaceRange(request.start, request.end, item.insertText),
    caret: request.start + item.caretOffset,
    item: item,
  );
}

void main() {
  test('声明属性按前缀排序，缩写也可命中并提供中文说明', () {
    final request = _request('p { font-s| }')!;
    expect(
      request.items.map((item) => item.label),
      containsAll(['font-size', 'font-style', 'font-stretch']),
    );
    expect(request.items.every((item) => item.detail.isNotEmpty), isTrue);
    expect(
      _request('p { f-s| }')!.items.map((item) => item.label),
      contains('font-size'),
    );
    expect(_request('p { fontsize| }')!.items.first.label, 'font-size');
    expect(
      _request(
        'font-s|',
        mode: CssCompletionMode.property,
      )!.items.first.insertText,
      isNot(contains(':')),
    );
  });

  test('缺少标点时插入声明并停在值位置，已有标点和CRLF原样保留', () {
    final inserted = _apply('p { font-s| }', 'font-size');
    expect(inserted.text, 'p { font-size: ; }');
    expect(inserted.text[inserted.caret], ';');
    expect(inserted.item.continueValues, isTrue);
    final existing = _apply(
      'p {\r\n  font-s|ize : 16px; color: red;\r\n}',
      'font-size',
    );
    expect(existing.text, 'p {\r\n  font-size : 16px; color: red;\r\n}');
    expect(existing.text.substring(existing.caret), startsWith('16px;'));
    expect(
      _apply('p { font-s|; color: red; }', 'font-size').text,
      'p { font-size: ; color: red; }',
    );
  });

  test('值依据属性过滤，光标中间替换完整token且不吞相邻声明', () {
    final request = _request('p { text-align: ce|nter; color: red; }')!;
    expect(request.items.map((item) => item.label), contains('center'));
    expect(request.items.map((item) => item.label), isNot(contains('bold')));
    expect(
      _apply('p { text-align: ce|nter; color: red; }', 'center').text,
      'p { text-align: center; color: red; }',
    );
    expect(
      _apply('p { margin: 1e|rem; padding: 0; }', '1em').text,
      'p { margin: 1em; padding: 0; }',
    );
    expect(
      _request(
        '1.25|',
        mode: CssCompletionMode.value,
        property: 'font-size',
      )!.items.map((item) => item.label),
      containsAll(['1.25px', '1.25em', '1.25rem', '1.25%']),
    );
    expect(
      _request('ce|', mode: CssCompletionMode.value, property: 'font-weight'),
      isNull,
    );
  });

  test('空位置仅显式触发，支持嵌套media与font-face声明', () {
    expect(_request('p { | }'), isNull);
    expect(
      _request('p { | }', explicit: true)!.items.map((item) => item.label),
      contains('text-indent'),
    );
    expect(
      _request('@media screen { p { text-i| } }')!.items.first.label,
      'text-indent',
    );
    expect(
      _request('@supports (display: grid) { @media print { p { font-w| } } }')!
          .items
          .first
          .label,
      'font-weight',
    );
    expect(
      _request('@font-face { font-f| }')!.items.map((item) => item.label),
      contains('font-family'),
    );
    expect(
      _request('@font-face { src: u| }')!.items.map((item) => item.label),
      contains('url()'),
    );
    expect(
      _request(
        'p { color: | }',
        explicit: true,
      )!.items.map((item) => item.label),
      contains('currentColor'),
    );
  });

  test('手动键入冒号后自动提示属性值，选择器冒号不会触发', () {
    expect(
      _request('p { display: | }')!.items.map((item) => item.label),
      contains('block'),
    );
    expect(
      _request('p { display:| }')!.items.map((item) => item.label),
      contains('inline'),
    );
    expect(_request('p: | { color: red; }'), isNull);
    expect(_request('p { a: | { color: red; } }'), isNull);
    expect(
      _request('|', mode: CssCompletionMode.value, property: 'display'),
      isNull,
    );
  });

  test('注释字符串URL和选择器中不触发，注释后的声明可补全', () {
    for (final input in [
      'font-s| { color: red; }',
      '@media screen { font-s| }',
      'p { /* font-s| */ color: red; }',
      'p { content: "font-s|"; }',
      "p { font-family: 'Noto S|'; }",
      'p { background: url(font-s|); }',
      'p { &:ho|ver { color: red; } }',
      'p { a:fo|cus { color: red; } }',
    ]) {
      expect(_request(input, explicit: true), isNull, reason: input);
    }
    expect(_request('p { /*说明*/ font-s| }')!.items.first.label, 'font-size');
    expect(
      _request('p { color: red; /*说明*/ text-i| }')!.items.first.label,
      'text-indent',
    );
  });

  test('当前缓冲变量可引用，var函数内替换保留单个括号且caret在括号后', () {
    const sheet =
        ':root { --body-size: 1em; /* --fake: 0; */ } p { font-size: va|; }';
    final result = _apply(sheet, 'var(--body-size)');
    expect(result.text, contains('font-size: var(--body-size);'));
    expect(result.text[result.caret], ';');
    expect(
      _request(sheet)!.items.map((item) => item.label),
      isNot(contains('var(--fake)')),
    );
    final inside = _apply(
      ':root { --body-size: 1em; } p { font-size: var(--bo|dy-size); }',
      'var(--body-size)',
    );
    expect(inside.text, contains('font-size: var(--body-size);'));
    expect(inside.text[inside.caret], ';');
  });

  test('XHTML只在真实style元素及style属性补全，其他引号属性不误识别', () {
    const mode = CssCompletionMode.xhtml;
    expect(
      _request(
        '<html><head><style>p { font-s| }</style></head></html>',
        mode: mode,
      )!.items.first.label,
      'font-size',
    );
    expect(
      _request('<p style="font-s|">正文</p>', mode: mode)!.items.first.label,
      'font-size',
    );
    expect(
      _apply(
        '<p style="font-s|ize: 1em;">正文</p>',
        'font-size',
        mode: mode,
      ).text,
      '<p style="font-size: 1em;">正文</p>',
    );
    for (final input in [
      '<p>font-s|</p>',
      '<p title="style=\'font-s|\'">正文</p>',
      '<!-- <style>p { font-s| }</style> -->',
      '<![CDATA[<p style="font-s|">]]>',
      '<script>const text = "<style>p {font-s|}</style>";</script>',
      '<p data-example="<style>p {font-s|}</style>">正文</p>',
      '<textarea><style>p { font-s| }</style></textarea>',
    ]) {
      expect(
        _request(input, mode: mode, explicit: true),
        isNull,
        reason: input,
      );
    }
  });

  test('UTF16偏移保留emoji及CRLF，非法偏移和未知词不修改源码', () {
    const input = '<p>😀</p>\r\n<style>p {\r\n font-s|ize: 1em;\r\n}</style>';
    final result = _apply(input, 'font-size', mode: CssCompletionMode.xhtml);
    expect(result.text, input.replaceFirst('|', ''));
    expect(result.text.substring(result.caret), startsWith('1em;'));
    expect(completeCss('p{}', -1), isNull);
    expect(completeCss('p{}', 99), isNull);
    expect(_request('p { custom-unknown| }'), isNull);
  });

  test('函数名中间补全保留已有括号，HTML实体引号内部不触发', () {
    expect(
      _apply('p { background-image: u|rl(image.png); }', 'url()').text,
      'p { background-image: url(image.png); }',
    );
    final result = _apply('p { background-image: u|rl(image.png); }', 'url()');
    expect(result.text.substring(result.caret), startsWith('image.png)'));
    for (final quotes in [
      ('&quot;', '&quot;'),
      ('&#34;', '&#34;'),
      ('&#x27;', '&#x27;'),
    ]) {
      expect(
        _request(
          '<p style="font-family: ${quotes.$1}font-s|${quotes.$2}">正文</p>',
          mode: CssCompletionMode.xhtml,
          explicit: true,
        ),
        isNull,
      );
    }
    expect(
      _request(
        '<style><![CDATA[p { font-s| }]]></style>',
        mode: CssCompletionMode.xhtml,
      )!.items.first.label,
      'font-size',
    );
  });
}
