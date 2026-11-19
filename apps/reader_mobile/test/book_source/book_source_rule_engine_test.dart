import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_rule_engine.dart';

import 'book_source_test_helpers.dart';

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

    test('裸星号段按通配处理', () {
      final grouped = <String, Object?>{
        'data': <String, Object?>{
          'chapterListWithVolume': <Object?>[
            <Object?>[
              <String, Object?>{'title': 'A'},
            ],
            <Object?>[
              <String, Object?>{'title': 'B'},
            ],
          ],
        },
      };
      final chapters = engine.evaluateList(
        grouped,
        r'$.data.chapterListWithVolume.*[*]',
        context,
      );
      expect(chapters, hasLength(2));
      expect(engine.evaluateString(chapters[0], 'title', context), 'A');
      expect(engine.evaluateString(chapters[1], 'title', context), 'B');
    });

    test('递归下降匹配', () {
      final items = engine.evaluateList(json, r'$..book', context);
      expect(items, hasLength(1));
      expect(engine.evaluateString(items.single, r'$.name', context), '深层');
    });

    test('JSON 根节点支持前导点与裸字段', () {
      final searchJson = <String, Object?>{
        'ret_data': <Object?>[
          <String, Object?>{'book_name': 'A', 'author': '甲'},
        ],
        'data': <Object?>[
          <String, Object?>{'book_name': 'B', 'author': '乙'},
        ],
      };
      final items = engine.evaluateList(
        searchJson,
        '.ret_data[*]||.data[0]',
        context,
      );
      expect(items, hasLength(1));
      expect(engine.evaluateString(items.single, 'book_name', context), 'A');
      expect(engine.evaluateString(items.single, 'author', context), '甲');
    });

    test('<js> 尾部 JSONPath 在脚本结果上执行', () {
      final rule =
          '<js>var list = data.list || []; result = {data: {list: list}};</js>'
          r'$.data.list[0].name';
      final script = FakeBookSourceScriptSession(
        (code, result, variables, session) =>
            '{"data":{"list":[{"name":"A"}]}}',
      );
      expect(engine.evaluateString(json, rule, context, script: script), 'A');
    });

    test('前导规则结果作为脚本的 result', () {
      final script = FakeBookSourceScriptSession(
        (code, result, variables, session) => 'url:$result',
      );
      expect(
        engine.evaluateString(
          <String, Object?>{'itemId': '123'},
          r'$.itemId'
          '\n'
          r'<js>url = result;</js>',
          context,
          script: script,
        ),
        'url:123',
      );
    });

    test('模板中的转义引号不阻断 @js 后缀', () {
      final calls = <String>[];
      final script = FakeBookSourceScriptSession((
        code,
        result,
        variables,
        session,
      ) {
        calls.add(code);
        return code.contains('result.replace') ? '已清理' : '前缀';
      });
      final value = engine.evaluateString(
        <String, Object?>{'roles': 'A|B'},
        r'''{{$.roles##[\"|]##}}@js:result.replace('前缀','已清理')''',
        context,
        script: script,
      );
      expect(value, '已清理');
      expect(calls.last, contains('result.replace'));
    });

    test('模板支持 JSONPath 与上下文字段', () {
      expect(
        engine.evaluateString(
          <String, Object?>{'book_id': 42},
          r'https://example.com/detail?book_id={{$.book_id}}',
          context,
        ),
        'https://example.com/detail?book_id=42',
      );
      expect(
        engine.evaluateString(
          <String, Object?>{},
          'https://example.com/search?q={{key}}',
          const BookSourceRuleContext(
            baseUrl: 'https://example.com',
            variables: <String, String>{'key': 'a b'},
          ),
        ),
        'https://example.com/search?q=a b',
      );
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

  test('绝对地址规则直接作为地址返回', () {
    expect(
      engine.evaluateString(
        <String, Object?>{},
        'https://example.com/book/1',
        context,
      ),
      'https://example.com/book/1',
    );
  });

  test('无法静态执行的 JS 规则给出明确错误', () {
    final document = engine.parseHtml('<div class="book">内容</div>');
    for (final rule in <String>[
      '@js:result = baseUrl + "/search";',
      '.book@js:result = result.replace("a", "b");',
      '<js>result = data;</js>',
    ]) {
      expect(
        () => engine.evaluateList(document, rule, context),
        throwsA(
          isA<BookSourceException>().having(
            (error) => error.code,
            'code',
            'ONLINE_RULE_JS',
          ),
        ),
        reason: rule,
      );
    }
  });
}
