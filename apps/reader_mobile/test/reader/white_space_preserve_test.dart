import 'package:flutter_test/flutter_test.dart';

import 'support/css_chapter_book.dart';

/// 聚合前计算元素最终 white-space；同章、同段内不同规则分别生效。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, String>> texts(String body, {String css = ''}) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      contentWidth: 300,
      contentHeight: 500,
    );
    final pages = await source.loadChapter(0);
    final result = <String, String>{};
    for (final slice in pages.expand((page) => page.slices)) {
      final block = slice.block;
      // 用块首行文本片段做键：样式类名写在文本里，便于断言定位。
      result.putIfAbsent(
        block.layout.text.split('\n').first.split(' ').first,
        () => block.layout.text,
      );
    }
    return result;
  }

  test('white-space: pre 保留连续空格与换行', () async {
    final result = await texts(
      '<p class="p">pre:a  b\nc</p>',
      css: '.p { white-space: pre; }',
    );
    expect(result['pre:a'], 'pre:a  b\nc');
  });

  test('white-space: pre-wrap / pre-line 保留换行', () async {
    final result = await texts(
      '<p class="pw">pw:a  b\nc</p><p class="pl">pl:a  b\nc</p>',
      css: '.pw { white-space: pre-wrap; } .pl { white-space: pre-line; }',
    );
    expect(result['pw:a'], 'pw:a  b\nc');
    // pre-line 折叠连续空格但保留换行。
    expect(result['pl:a'], 'pl:a b\nc');
  });

  test('同一章内普通块仍按 normal 折叠（不受 pre 块影响）', () async {
    final result = await texts(
      '<p class="p">pre:a  b\nc</p><p class="n">普通:a  b\nc</p>',
      css: '.p { white-space: pre; }',
    );
    expect(result['pre:a'], 'pre:a  b\nc');
    expect(result['普通:a'], '普通:a b c');
  });

  test('<pre> 标签始终按 pre 聚合（回归）', () async {
    final result = await texts('<pre>标签:a  b\nc</pre>');
    expect(result['标签:a'], '标签:a  b\nc');
  });

  test('章节未声明 pre 族时聚合行为不变', () async {
    final result = await texts('<p>普通:a  b\nc</p>');
    expect(result['普通:a'], '普通:a b c');
  });
}
