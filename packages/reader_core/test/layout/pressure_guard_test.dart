import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/text/regex_guard.dart';

/// P7-16：压力防护四道——DOM 深度、属性炸弹、正则预算、页数截断。
void main() {
  group('DOM 嵌套深度（P7-16）', () {
    test('600 层嵌套可解析，超限展平为文本并记诊断', () {
      final open = List.generate(600, (i) => '<div>').join();
      final close = List.generate(600, (i) => '</div>').join();
      final deep = '$open深层正文$close';
      final xhtml = '<html><body><p>普通段落</p>$deep</body></html>';
      final doc = DocumentParser.parse(xhtml: xhtml, spineIndex: 0);
      expect(doc.plainText, contains('深层正文'), reason: '展平保留可读内容');
      expect(doc.plainText, contains('普通段落'));
      expect(
        doc.parseDiagnostics.any((d) => d.startsWith('E_DOM_NESTING_TOO_DEEP')),
        isTrue,
      );
    });

    test('正常深度的书不受影响', () {
      final open = List.generate(20, (i) => '<section>').join();
      final close = List.generate(20, (i) => '</section>').join();
      final doc = DocumentParser.parse(
        xhtml: '<html><body>$open正文$close</body></html>',
        spineIndex: 0,
      );
      expect(doc.plainText, '正文');
      expect(doc.parseDiagnostics, isEmpty);
    });
  });

  group('属性值长度（P7-16）', () {
    test('超长属性截断并记诊断', () {
      final bomb = 'a' * 70000;
      final doc = DocumentParser.parse(
        xhtml: '<html><body>'
            '<p title="$bomb">正文</p>'
            '</body></html>',
        spineIndex: 0,
      );
      expect(doc.plainText, '正文');
      expect(
        doc.parseDiagnostics.any((d) => d.startsWith('E_ATTRIBUTE_TRUNCATED')),
        isTrue,
      );
      final root = doc.root;
      final p = root.children.whereType<ParsedElement>().first;
      expect(
        p.attributes['title']?.length,
        DocumentParser.maxAttributeValueLength,
      );
    });

    test('正常属性不截断', () {
      final doc = DocumentParser.parse(
        xhtml: '<html><body><p id="ok">正文</p></body></html>',
        spineIndex: 0,
      );
      expect(doc.parseDiagnostics, isEmpty);
    });
  });

  group('正则预算（P7-16）', () {
    test('快速正则在预算内返回匹配区间', () async {
      final hit = await RegexGuard.firstMatch(r'\d+', 'abc 12345 def');
      expect(hit, isNotNull);
      expect(hit!.start, 4);
      expect(hit.end, 9);
    });

    test('灾难性回溯在预算内超时返回 null（不卡死）', () async {
      final input = 'a' * 40 + 'b'; // (a+)+$ 对此类输入指数回溯。
      final watch = Stopwatch()..start();
      final hit = await RegexGuard.firstMatch(
        r'(a+)+$',
        input,
        budget: Duration(milliseconds: 800),
      );
      watch.stop();
      expect(hit, isNull, reason: '灾难性正则应超时挂起');
      expect(watch.elapsed, lessThan(Duration(seconds: 5)),
          reason: '守卫必须按时放弃');
    });

    test('非法模式返回 null 且不抛异常', () async {
      final hit = await RegexGuard.firstMatch('([unclosed', 'abc');
      expect(hit, isNull);
    });

    test('isValidPattern 校验模式可编译', () {
      expect(RegexGuard.isValidPattern(r'\d+'), isTrue);
      expect(RegexGuard.isValidPattern('([unclosed'), isFalse);
    });
  });

  group('页数截断（P7-16）', () {
    test('达到页数上限即截断，已产出页保留', () {
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'Ahem',
      });
      final blocks = <PageBlock>[];
      for (var i = 0; i < 60; i++) {
        final layout = TextLayoutEngine.layout(
          text: '第$i段落内容',
          style: style,
          maxWidth: 100,
        );
        blocks.add(
          PageBlock.styled(
            layout: layout,
            style: style,
            containingWidth: 100,
          ),
        );
      }
      final result = Paginator(pageHeight: 24).measureChapter(
        blocks: blocks,
        maxPages: 10,
      );
      expect(result.pages, hasLength(10));
      expect(result.truncated, isTrue);
    });

    test('未达上限不标记截断', () {
      final style = ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'Ahem',
      });
      final layout = TextLayoutEngine.layout(
        text: '短文本',
        style: style,
        maxWidth: 100,
      );
      final result = Paginator(pageHeight: 24).measureChapter(
        blocks: <PageBlock>[
          PageBlock.styled(layout: layout, style: style, containingWidth: 100),
        ],
      );
      expect(result.pages, hasLength(1));
      expect(result.truncated, isFalse);
    });
  });
}
