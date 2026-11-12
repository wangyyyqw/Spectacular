import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_mobile/editing/xhtml_chunk_analyzer.dart';

void main() {
  const analyzer = XhtmlChunkAnalyzer();

  test('折叠嵌套 XHTML、命名空间与跨行属性，范围使用可见行号', () {
    final lines = CodeLines.fromText('''<html>
<body>
<svg:g
  data-label="含 > 与 <fake> 的属性">
  <p>正文</p>
</svg:g>
</body>
</html>''');
    expect(analyzer.run(lines), const [
      CodeChunk(0, 7),
      CodeChunk(1, 6),
      CodeChunk(2, 5),
    ]);
  });

  test('同一行只保留最外层折叠，不为单行或自闭合标签生成折叠', () {
    expect(
      analyzer.run(
        CodeLines.fromText('''<div><section>
<img src="a.png"/>
<p>文字</p>
</section>
</div>'''),
      ),
      const [CodeChunk(0, 4)],
    );
    expect(
      analyzer.run(CodeLines.fromText('<p>单行</p>\n<br/>\n<div>\n</div>')),
      isEmpty,
    );
  });

  test('注释、CDATA 与转义正文中的假标签不生成折叠', () {
    final lines = CodeLines.fromText('''<body>
<!--
<fake>
假标签
</fake>
-->
<![CDATA[
<other>
假标签
</other>
]]>
&lt;p&gt;正文&lt;/p&gt;
</body>''');
    expect(analyzer.run(lines), const [CodeChunk(0, 12)]);
  });

  test('DTD 内部子集与处理指令的引号内容不作为正文标签', () {
    final lines = CodeLines.fromText('''<!DOCTYPE html [
<!ENTITY example "<fake>
文字
</fake>">
<!-- ] > <fake> -->
]>
<?instruction value="<fake>
文字
</fake>"?>
<html>
<p>正文</p>
</html>''');
    expect(analyzer.run(lines), const [CodeChunk(9, 11)]);
  });

  test('style 与 script 文字中的标签样字符串不会生成内部折叠', () {
    final lines = CodeLines.fromText('''<body>
<style>
p::after {content: "<fake>
文字
</fake>"}
</style>
<script>
const text = "<other>
文字
</other>";
</script>
</body>''');
    expect(analyzer.run(lines), const [
      CodeChunk(0, 11),
      CodeChunk(1, 5),
      CodeChunk(6, 10),
    ]);
  });

  test('未闭合标签、注释、属性和错误嵌套只保留损坏前的闭合范围', () {
    for (final suffix in [
      '<div>\n<p>\n</div>\n</p>',
      '<div title="未结束\n<fake>\n正文\n</fake>',
      '<!--\n<fake>\n正文\n</fake>',
      '<![CDATA[\n<fake>\n正文\n</fake>',
      '<div>\n未闭合',
      '正文 < 其他文字\n<fake>\n正文\n</fake>',
    ]) {
      expect(
        analyzer.run(CodeLines.fromText('<p>\n完整段落\n</p>\n$suffix')),
        const [CodeChunk(0, 2)],
        reason: suffix,
      );
    }
  });

  test('已折叠的跨行开始标签仍可识别，隐藏子块不会产生可见范围', () {
    final lines = CodeLines.of(const [
      CodeLine('<div', [
        CodeLine(' class="note">'),
        CodeLine('<p>', [CodeLine('嵌套隐藏正文')]),
        CodeLine('</p>'),
      ]),
      CodeLine('</div>'),
      CodeLine('<p>'),
      CodeLine('后续正文'),
      CodeLine('</p>'),
    ]);
    expect(analyzer.run(lines), const [CodeChunk(0, 1), CodeChunk(2, 4)]);
    expect(analyzer.run(lines).first.canCollapse, isFalse);
  });

  test('CSS 继续复用 ReEditor 默认花括号分析器', () {
    final chunks = const DefaultCodeChunkAnalyzer().run(
      CodeLines.fromText('p {\n  color: red;\n}'),
    );
    expect(chunks, const [CodeChunk(0, 2)]);
  });
}
