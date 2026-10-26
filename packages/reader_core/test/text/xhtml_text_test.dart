import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/text/xhtml_text.dart';

void main() {
  test('剥标签、块级换行、实体解码、空白折叠', () {
    const xhtml = '''
<html><head><style>p { color: red; }</style></head><body>
<h1>第1章 标题</h1>
<p>第一段 &amp; 内容&nbsp;这里有<em>强调</em>。</p>
<p>第二段<br/>换行后</p>
<script>var a = 1;</script>
</body></html>
''';
    final text = xhtmlToPlainText(xhtml);
    expect(text, isNot(contains('<')));
    expect(text, isNot(contains('color: red')));
    expect(text, isNot(contains('var a')));
    expect(text, contains('第1章 标题'));
    expect(text, contains('第一段 & 内容 这里有强调。'));
    expect(text, contains('第二段\n换行后'));
    expect(text, isNot(contains('  ')), reason: '空白已折叠');
  });

  test('实体与数字实体', () {
    expect(xhtmlToPlainText('<p>&#20320;&#x597d;</p>'), '你好');
    expect(xhtmlToPlainText('<p>&mdash;&hellip;&ldquo;引号&rdquo;</p>'), '—…“引号”');
  });
}
