import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_rule_engine.dart';

void main() {
  const engine = BookSourceRuleEngine();
  const context = BookSourceRuleContext(
    baseUrl: 'https://example.com',
    pageUrl: 'https://example.com/search?q=test',
  );

  group('HTML 规则', () {
    final document = engine.parseHtml('''
<div class="book">
  <a class="title" href="/book/1">书名</a>
  <span class="author">作 者</span>
</div>
<div class="book">
  <a class="title" href="/book/2">第二本</a>
  <span class="author">另一位</span>
</div>
''');

    test('CSS 选择器、文本与属性提取', () {
      expect(
        engine.evaluateString(document, '.book .title@text', context),
        '书名\n第二本',
      );
      expect(
        engine.evaluateString(document, '.book .title@href', context),
        '/book/1\n/book/2',
      );
      expect(
        engine.evaluateString(document, '.book:eq(0)@text', context),
        '书名 作 者',
      );
    });

    test('正则替换与 ||、&& 组合', () {
      expect(
        engine.evaluateString(document, r'.book .author@text##\s+##', context),
        '作者\n另一位',
      );
      expect(
        engine.evaluateString(
          document,
          '.missing@text || .book .author@text',
          context,
        ),
        '作 者\n另一位',
      );
      expect(
        engine.evaluateString(
          document,
          '.book:eq(0)@text && .book:eq(1)@text',
          context,
        ),
        '书名 作 者\n第二本 另一位',
      );
    });

    test('相对链接按页面地址解析', () {
      expect(
        engine.resolveUrl(context.pageUrl, '/book/1'),
        'https://example.com/book/1',
      );
      expect(
        engine.resolveUrl(context.pageUrl, '//cdn.example.com/a.jpg'),
        'https://cdn.example.com/a.jpg',
      );
    });
  });

  group('JSONPath 规则', () {
    final json = <String, Object?>{
      'data': <String, Object?>{
        'list': <Object?>[
          <String, Object?>{'name': 'A', 'url': '/a'},
          <String, Object?>{'name': 'B', 'url': '/b'},
        ],
      },
      'nested': <String, Object?>{
        'book': <String, Object?>{'name': '深层'},
      },
    };

    test('数组通配与字段提取', () {
      final items = engine.evaluateList(json, r'$.data.list[*]', context);
      expect(items, hasLength(2));
      expect(engine.evaluateString(items[0], r'$.name', context), 'A');
      expect(engine.evaluateString(items[1], r'$.url', context), '/b');
    });

    test('递归下降匹配', () {
      final items = engine.evaluateList(json, r'$..book', context);
      expect(items, hasLength(1));
      expect(engine.evaluateString(items.single, r'$.name', context), '深层');
    });
  });

  test('XPath 规则给出明确错误', () {
    final document = engine.parseHtml('<div>内容</div>');
    expect(
      () => engine.evaluateList(document, '@xpath://div', context),
      throwsA(
        isA<BookSourceException>().having(
          (error) => error.code,
          'code',
          'ONLINE_RULE_XPATH',
        ),
      ),
    );
  });
}
