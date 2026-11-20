import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_rule_engine.dart';
import 'package:reader_mobile/book_source/book_source_script.dart';

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

    test('列表保留 HTML 节点，供后续字段和正文继续解析', () {
      final items = engine.evaluateList(document, '.book', context);
      expect(items, hasLength(2));
      expect(items.every((item) => item is Element), isTrue);
      expect(
        engine.evaluateString(items.first, '.title@href', context),
        '/book/1',
      );
      expect(engine.evaluateString(items.last, '.author@text', context), '另一位');

      final content = engine.parseHtml(
        '<div class="content"><p>第一段</p><p>第二段</p>'
        '<img src="/image.jpg"></div>',
      );
      final html = engine.evaluateHtml(content, '.content', context);
      expect(html, '<p>第一段</p><p>第二段</p><img src="/image.jpg">');
    });

    test('默认规则逐个节点执行选择链，并支持节点本身的提取', () {
      expect(
        engine.evaluateString(document, 'class.book@tag.a.0@text', context),
        '书名\n第二本',
      );
      expect(
        engine.evaluateString(document, '@@class.book@tag.a@href', context),
        '/book/1\n/book/2',
      );
      final link = document.querySelector('a')!;
      expect(engine.evaluateString(link, 'text', context), '书名');
      expect(engine.evaluateString(link, 'href', context), '/book/1');
      expect(engine.evaluateString(link, 'tag.a@href', context), '/book/1');
      expect(engine.evaluateString(link, '.title@href', context), '/book/1');
    });

    test('默认规则支持负数、排除和含右端点的区间索引', () {
      final list = engine.parseHtml(
        '<ol id="list"><li>A</li><li>B</li><li>C</li><li>D</li></ol>',
      );
      expect(engine.evaluateString(list, 'tag.li.-1@text', context), 'D');
      expect(engine.evaluateString(list, 'tag.li!0:2@text', context), 'B\nD');
      expect(
        engine.evaluateString(list, 'tag.li[0:2]@text', context),
        'A\nB\nC',
      );
      expect(
        engine.evaluateString(list, 'tag.li[-1:0:2]@text', context),
        'D\nB',
      );
      expect(
        engine.evaluateString(list, 'tag.li[!1,-1]@text', context),
        'A\nC',
      );
      expect(
        engine.evaluateString(list, 'id.list@children[1,-1]@text', context),
        'B\nD',
      );
      expect(engine.evaluateString(list, 'text.C@text', context), 'C');
      expect(
        engine.evaluateString(list, '@CSS:#list > li@text', context),
        'A\nB\nC\nD',
      );
    });

    test('CSS 属性条件与 first-child 不会被误当成列表索引', () {
      final list = engine.parseHtml(
        '<ul><li data-id="1">A</li><li>B</li></ul>'
        '<ul><li data-id="1">C</li><li>D</li></ul>',
      );
      expect(
        engine.evaluateString(list, 'li[data-id="1"]@text', context),
        'A\nC',
      );
      expect(
        engine.evaluateString(list, 'li:first-child@text', context),
        'A\nC',
      );
      expect(engine.evaluateString(list, 'ul@li:eq(-1)@text', context), 'B\nD');
    });

    test('交错组合保持列表位置，空提取结果可继续后备规则', () {
      expect(
        engine.evaluateString(document, 'tag.a@href%%tag.a@text', context),
        '/book/1\n书名\n/book/2\n第二本',
      );
      expect(
        engine.evaluateString(
          document,
          r'class.book@tag.a@text##.+## || class.book@tag.span@text',
          context,
        ),
        '作 者\n另一位',
      );
    });

    test('textNodes 保留直属文本段，选择后的脚本读取 HTML', () {
      final content = engine.parseHtml(
        '<div id="content">第一段<span>子节点</span>第二段<br>第三段</div>',
      );
      expect(
        engine.evaluateString(
          content,
          'id.content@textNodes',
          context,
          preserveNewlines: true,
        ),
        '第一段\n第二段\n第三段',
      );
      final script = FakeBookSourceScriptSession((
        code,
        result,
        variables,
        session,
      ) {
        expect(result, contains('<span>子节点</span>'));
        return '<p>脚本正文</p>\n<p>下一段</p>';
      });
      expect(
        engine.evaluateHtml(
          content,
          'id.content@js:result',
          context,
          script: script,
        ),
        '<p>脚本正文</p>\n<p>下一段</p>',
      );
    });

    test('全文替换保留换行与 HTML，并展开 Java 捕获组', () {
      const content = '<p>第一段123</p>\n<p>第二段456</p>';
      const expected = '<p>第一段</p>\n<p>第二段</p>';
      expect(
        engine.evaluateHtml(content, r'##<p>(.*?)\d+</p>##<p>$1</p>', context),
        expected,
      );
      expect(
        engine.evaluateHtml(
          content,
          r'all##<p>(.*?)\d+</p>##<p>$1</p>',
          context,
        ),
        expected,
      );
      expect(
        engine.evaluateHtml('a\nB\nc', r'##(?im)^b$##已替换', context),
        'a\n已替换\nc',
      );
    });

    test('正文省略提取器的替换保留段落和图片，文本提取语义保持一致', () {
      final content = engine.parseHtml(
        '<div class="content"><p>第一段广告</p>\n<p>第二段</p>'
        '<img src="/image.jpg"></div>'
        '<div class="after"><p>后续段落</p></div>',
      );
      const expected = '<p>第一段</p>\n<p>第二段</p><img src="/image.jpg">';
      expect(
        engine.evaluateHtml(content, 'class.content##广告##', context),
        expected,
      );
      expect(
        engine.evaluateHtml(content, '@css:.content##广告##', context),
        expected,
      );
      expect(
        engine.evaluateString(content, 'class.content##广告##', context),
        '第一段 第二段',
      );
      expect(
        engine.evaluateHtml(content, 'class.content@text##广告##', context),
        '第一段 第二段',
      );
      expect(
        engine.evaluateString(content, 'class.content@text##广告##', context),
        '第一段 第二段',
      );
      expect(
        engine.evaluateHtml(
          content,
          'class.content##广告##&&class.after',
          context,
        ),
        '$expected<p>后续段落</p>',
      );
      final script = FakeBookSourceScriptSession((
        code,
        result,
        variables,
        session,
      ) {
        expect(result, expected);
        return result;
      });
      expect(
        engine.evaluateHtml(
          content,
          'class.content##广告##@js:result',
          context,
          script: script,
        ),
        expected,
      );
    });

    test('三个井号只返回首个匹配的替换结果，无匹配返回空', () {
      expect(
        engine.evaluateHtml(
          '前缀 word=first 后缀 word=second',
          r'##word=(\w+)##$1###',
          context,
        ),
        'first',
      );
      expect(engine.evaluateHtml('没有匹配', r'##word=(\w+)##$1###', context), '');
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

    test('空字段不占据后备结果，数字零和 false 保留', () {
      const values = <String, Object?>{
        'missing': null,
        'count': 0,
        'valid': false,
      };
      expect(engine.evaluateString(values, 'missing||count', context), '0');
      expect(engine.evaluateString(values, 'valid', context), 'false');
      expect(engine.evaluateHtml(null, '##^##替换', context), '');
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

    test('简介求值可保留模板和 JSON 字段换行', () {
      final json = <String, Object?>{
        'abstract': '第一段\n第二段\n\n第三段',
        'book_id': 42,
      };
      expect(
        engine.evaluateString(
          json,
          '编号：{{\$.book_id}}\n简介：{{\$.abstract}}',
          context,
          preserveNewlines: true,
        ),
        '编号：42\n简介：第一段\n第二段\n\n第三段',
      );
      expect(
        engine.evaluateString(
          json,
          r'$.abstract',
          context,
          preserveNewlines: true,
        ),
        '第一段\n第二段\n\n第三段',
      );
      expect(
        engine.evaluateString(json, r'$.abstract', context),
        '第一段 第二段 第三段',
      );
    });

    test('脚本结果可保留换行', () {
      final script = FakeBookSourceScriptSession(
        (code, result, variables, session) => '第一行\n第二行',
      );
      expect(
        engine.evaluateString(
          <String, Object?>{},
          '@js:result',
          context,
          script: script,
          preserveNewlines: true,
        ),
        '第一行\n第二行',
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

  test('显式正则模式不把模式内容误识别为 HTML 提取器', () {
    expect(
      engine.evaluateString('before all after', '@regex:all', context),
      'all',
    );
    expect(engine.evaluateString('text=示例', '@regex:text=(.+)', context), '示例');
  });

  test('静态 java.getCookie 调用会按域名和名称取值', () {
    final values = resolveScriptCookies(
      '''java.getCookie("fanqienovel.com", "sessionid");
      java.getCookie('example.com', "token");''',
      (domain, name) => '$domain:$name',
    );

    expect(values, <String, String>{
      'fanqienovel.com\nsessionid': 'fanqienovel.com:sessionid',
      'example.com\ntoken': 'example.com:token',
    });
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
