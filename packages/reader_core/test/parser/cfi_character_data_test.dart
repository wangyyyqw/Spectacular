import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/parser/cfi_binder.dart';
import 'package:reader_core/parser/cfi_resolver.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/position/cfi.dart';

const _adjacentElements =
    '<html><body><p id="p">lead<b>A</b><i>B</i>tail</p></body></html>';
const _splitCharacters =
    '<html><body><p id="p">a<!--忽略-->b<![CDATA[😀&]]>'
    '<?reader ignored?>c</p></body></html>';

EpubCfi _cfi(String steps, {int? offset}) =>
    EpubCfi.parse('epubcfi(/6/2!/4$steps${offset == null ? '' : ':$offset'})')!;

void main() {
  test('相邻元素后的字符块在四个正式入口均使用 /5', () {
    final parsed = DocumentParser.parse(
      xhtml: _adjacentElements,
      spineIndex: 0,
    );
    final bound = CfiBinder.bind(xhtml: _adjacentElements, spineIndex: 0);
    final tail = parsed.textNodes.last;
    final expected = _cfi('/2[p]/5');

    expect(tail.cfi.serialize(), expected.serialize());
    expect(bound.textNodes.last.baseCfi.serialize(), expected.serialize());
    expect(parsed.nodeAtCfi(expected), same(tail));
    final resolved = parsed.resolve(expected.withCharOffset(4));
    expect(resolved.exact, isTrue);
    expect(resolved.textOffset, 4);
    expect(resolved.cfi!.serialize(), expected.withCharOffset(4).serialize());
    expect(parsed.plainText, 'leadABtail');
  });

  test('CDATA、注释和处理指令两侧的字符合并且保留源码范围', () {
    final parsed = DocumentParser.parse(xhtml: _splitCharacters, spineIndex: 0);
    final bound = CfiBinder.bind(xhtml: _splitCharacters, spineIndex: 0);

    expect(parsed.parserChoice, DocumentParserChoice.strict);
    expect(parsed.plainText, 'ab😀&c');
    expect(parsed.source, _splitCharacters);
    expect(parsed.textNodes, hasLength(1));
    expect(bound.textNodes, hasLength(1));
    final text = parsed.textNodes.single;
    expect(text.text, 'ab😀&c');
    expect(bound.textNodes.single.text, text.text);
    expect(text.cfi.serialize(), _cfi('/2[p]/1').serialize());
    expect(bound.textNodes.single.baseCfi.serialize(), text.cfi.serialize());
    expect(parsed.nodeAtCfi(text.cfi), same(text));
    expect(text.start, _splitCharacters.indexOf('a<!--'));
    expect(text.end, _splitCharacters.indexOf('c</p>') + 1);
  });

  test('合并后的 UTF-16 偏移可跨 CDATA 和被忽略节点往返', () {
    final parsed = DocumentParser.parse(xhtml: _splitCharacters, spineIndex: 0);
    final bound = CfiBinder.bind(xhtml: _splitCharacters, spineIndex: 0);
    final base = _cfi('/2[p]/1');

    for (final offset in [0, 2, 3, 4, 5, 6]) {
      final target = base.withCharOffset(offset);
      final resolved = CfiResolver.resolve(
        xhtml: _splitCharacters,
        target: target,
        expectedSpineIndex: 0,
      );
      expect(resolved.exact, isTrue, reason: '偏移 $offset');
      expect(resolved.textOffset, offset);
      expect(
        bound.refine(bound.textNodes.first, offset)!.serialize(),
        target.serialize(),
      );
      expect((parsed.nodeAtCfi(target) as ParsedText).text, 'ab😀&c');
    }
    expect(bound.refine(bound.textNodes.first, 7), isNull);
    final clamped = parsed.resolve(base.withCharOffset(99));
    expect(clamped.adjusted, isTrue);
    expect(clamped.textOffset, 6);
  });

  test('CDATA 内的命名实体保持字面字符及偏移', () {
    const xhtml =
        '<html><body><p id="p">a<![CDATA[&nbsp;&unknown;]]>b</p></body></html>';
    final parsed = DocumentParser.parse(xhtml: xhtml, spineIndex: 0);
    final bound = CfiBinder.bind(xhtml: xhtml, spineIndex: 0);

    expect(parsed.parserChoice, DocumentParserChoice.strict);
    expect(parsed.plainText, 'a&nbsp;&unknown;b');
    expect(bound.textNodes.single.text, parsed.plainText);
    final target = parsed.textNodes.single.cfi.withCharOffset(parsed.charCount);
    expect(
      bound.refine(bound.textNodes.single, parsed.charCount)!.serialize(),
      target.serialize(),
    );
    final resolved = parsed.resolve(target);
    expect(resolved.exact, isTrue);
    expect(resolved.textOffset, parsed.charCount);
  });

  test('CDATA 外的已识别命名实体解码，真正未知实体保留空格容错', () {
    const xhtml =
        '<html><body><p id="p">a&amp;&nbsp;&unknown;b</p></body></html>';
    final bound = CfiBinder.bind(xhtml: xhtml, spineIndex: 0);

    expect(bound.warnings, isEmpty);
    expect(bound.textNodes.single.text, 'a&\u00a0 b');
    final target = bound.refine(bound.textNodes.single, 5)!;
    final resolved = CfiResolver.resolve(xhtml: xhtml, target: target);
    expect(resolved.exact, isTrue);
    expect(resolved.textOffset, 5);
  });

  test('潜在空字符槽不产生正文节点且解析偏移钳到零', () {
    const xhtml =
        '<html><body><p id="p"><b>A</b><i>B</i></p>'
        '<p id="empty"/></body></html>';
    final parsed = DocumentParser.parse(xhtml: xhtml, spineIndex: 0);
    final bound = CfiBinder.bind(xhtml: xhtml, spineIndex: 0);

    expect(parsed.plainText, 'AB');
    expect(parsed.textNodes.map((node) => node.text), ['A', 'B']);
    expect(bound.textNodes.map((node) => node.text), ['A', 'B']);
    for (final steps in ['/2[p]/1', '/2[p]/3', '/2[p]/5', '/4[empty]/1']) {
      final target = _cfi(steps, offset: 0);
      expect(parsed.nodeAtCfi(target), isNull, reason: steps);
      final exact = parsed.resolve(target);
      expect(exact.exact, isTrue, reason: steps);
      expect(exact.cfi!.serialize(), target.serialize());
      expect(exact.textOffset, 0);
      final clamped = parsed.resolve(target.withCharOffset(3));
      expect(clamped.adjusted, isTrue);
      expect(clamped.cfi!.serialize(), target.serialize());
      expect(clamped.textOffset, 0);
    }
  });

  test('空槽查找不能错命中后方真实文本', () {
    final parsed = DocumentParser.parse(
      xhtml: _adjacentElements,
      spineIndex: 0,
    );

    expect(parsed.nodeAtCfi(_cfi('/2[p]/3')), isNull);
    final empty = parsed.resolve(_cfi('/2[p]/3', offset: 0));
    expect(empty.exact, isTrue);
    expect(empty.textOffset, 0);
    expect(parsed.nodeAtCfi(_cfi('/2[p]/5')), same(parsed.textNodes.last));
  });

  test('真正越界的字符槽仍回退到最近真实文本或元素', () {
    final parsed = DocumentParser.parse(
      xhtml: _adjacentElements,
      spineIndex: 0,
    );
    final result = parsed.resolve(_cfi('/2[p]/9', offset: 99));

    expect(result.adjusted, isTrue);
    expect(result.cfi!.serialize(), _cfi('/2[p]/5', offset: 4).serialize());
    expect(result.textOffset, 4);
    expect(result.warnings, isNotEmpty);
    final empty = CfiResolver.resolve(
      xhtml: '<html><body><p id="p"/></body></html>',
      target: _cfi('/2[p]/9', offset: 1),
    );
    expect(empty.adjusted, isTrue);
    expect(empty.cfi!.serialize(), _cfi('/2[p]').serialize());
    expect(empty.textOffset, isNull);
  });

  test('容错 HTML 路径沿用字符槽编号并保留正文', () {
    const xhtml = '<html><body><p id="p"><b>A</b><i>B</i>tail';
    final parsed = DocumentParser.parse(xhtml: xhtml, spineIndex: 0);

    expect(parsed.parserChoice, DocumentParserChoice.tolerantFallback);
    expect(parsed.plainText, 'ABtail');
    expect(parsed.source, xhtml);
    expect(parsed.textNodes.last.cfi.serialize(), _cfi('/2[p]/5').serialize());
    expect(parsed.nodeAtCfi(_cfi('/2[p]/1')), isNull);
    expect(parsed.nodeAtCfi(_cfi('/2[p]/3')), isNull);
    expect(parsed.nodeAtCfi(_cfi('/2[p]/5')), same(parsed.textNodes.last));
  });

  test('严格表格不插入隐式 tbody，四个正式入口按源 XML 回读', () {
    const xhtml =
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<table><tr><td id="cell"><p id="p">'
        'lead<b>A</b><i>B</i>tail</p></td></tr></table>'
        '</body></html>';
    final parsed = DocumentParser.parse(xhtml: xhtml, spineIndex: 0);
    final bound = CfiBinder.bind(xhtml: xhtml, spineIndex: 0);
    final expected = _cfi('/2/2/2[cell]/2[p]/5', offset: 2);
    final tail = parsed.textNodes.last;

    expect(parsed.parserChoice, DocumentParserChoice.strict);
    expect(parsed.plainText, 'leadABtail');
    expect(tail.cfi.withCharOffset(2).serialize(), expected.serialize());
    expect(
      bound.refine(bound.textNodes.last, 2)!.serialize(),
      expected.serialize(),
    );
    expect(parsed.nodeAtCfi(expected), same(tail));
    final resolved = parsed.resolve(expected);
    expect(resolved.exact, isTrue);
    expect(resolved.textOffset, 2);
    expect(resolved.cfi!.serialize(), expected.serialize());
    expect(tail.start, xhtml.indexOf('tail'));
    expect(tail.end, xhtml.indexOf('tail') + 4);
    final table = parsed.root.children.single as ParsedElement;
    expect(table.children.whereType<ParsedElement>().single.tag, 'tr');
  });

  test('NBSP、双码元命名实体和 CDATA 在三个解析入口共用字符偏移', () {
    const xhtml =
        '<html><body><p id="p">A&nbsp;&NotEqualTilde;'
        '<![CDATA[&copy;]]><b>X</b>&copy;&unknown;tail</p></body></html>';
    final parsed = DocumentParser.parse(xhtml: xhtml, spineIndex: 0);
    final bound = CfiBinder.bind(xhtml: xhtml, spineIndex: 0);
    const first = 'A\u00a0\u2242\u0338&copy;';
    expect(parsed.textNodes.map((node) => node.text), [first, 'X', '© tail']);
    expect(bound.textNodes.map((node) => node.text), [first, 'X', '© tail']);
    expect(parsed.textNodes.first.start, xhtml.indexOf('A&nbsp;'));
    expect(parsed.textNodes.first.end, xhtml.indexOf(']]>'));
    for (var index = 0; index < parsed.textNodes.length; index++) {
      final node = parsed.textNodes[index];
      for (var offset = 0; offset <= node.text.length; offset++) {
        final cfi = node.cfi.withCharOffset(offset);
        expect(parsed.nodeAtCfi(cfi), same(node));
        expect(
          bound.refine(bound.textNodes[index], offset)!.serialize(),
          cfi.serialize(),
        );
        final resolved = parsed.resolve(cfi);
        expect(resolved.exact, isTrue);
        expect(resolved.textOffset, offset);
      }
    }
  });
}
