import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/parser/document_parser.dart';/// P7-11：解析器双路径——严格 XML 校验闸门 + html5lib 容错转换。
void main() {
  const wellFormed =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops">'
      '<head><title>好</title></head><body>'
      '<p id="p1">正文<span epub:type="noteref">注</span></p>'
      '</body></html>';

  const unclosed =
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
      '<p>没有闭合的段落<p>第二段</body></html>';

  test('合法 XHTML 命中严格路径且 epub:type 语义保留', () {
    final doc = DocumentParser.parse(xhtml: wellFormed, spineIndex: 0);
    expect(doc.parserChoice, DocumentParserChoice.strict);
    expect(doc.parseDiagnostics, isEmpty);
    // 命名空间属性（epub:type）对下游可用（脚注/pagebreak 语义入口）。
    final span = _findByTag(doc.root, 'span');
    expect(span, isNotNull);
    expect(span!.attributes.containsKey('epub:type'), isTrue);
    expect(span.attributes['epub:type'], 'noteref');
  });

  test('标签不闭合的书回退容错路径并带降级诊断', () {
    final doc = DocumentParser.parse(xhtml: unclosed, spineIndex: 0);
    expect(doc.parserChoice, DocumentParserChoice.tolerantFallback);
    expect(doc.parseDiagnostics, isNotEmpty);
    expect(
      doc.parseDiagnostics.first.startsWith('E_DOCUMENT_TOLERANT_FALLBACK'),
      isTrue,
    );
    // 容错路径仍能读出正文。
    expect(doc.plainText, contains('没有闭合的段落'));
    expect(doc.plainText, contains('第二段'));
  });

  test('两条路径的缓存键可区分', () {
    final strict = DocumentParser.parse(xhtml: wellFormed, spineIndex: 0);
    final tolerant = DocumentParser.parse(xhtml: unclosed, spineIndex: 0);
    expect(strict.parserCacheKey, 'strict');
    expect(tolerant.parserCacheKey, 'tolerant');
    expect(strict.parserCacheKey, isNot(tolerant.parserCacheKey));
  });
}

ParsedElement? _findByTag(ParsedNode node, String tag) {
  if (node is ParsedElement) {
    if (node.tag == tag) {
      return node;
    }
    for (final child in node.children) {
      final hit = _findByTag(child, tag);
      if (hit != null) {
        return hit;
      }
    }
  }
  return null;
}
