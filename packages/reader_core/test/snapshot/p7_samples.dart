import 'dart:typed_data';

import '../support/corpus.dart' show buildZip;

/// P7-31：样式回归样本扩充——五类生成样本（合成内容，无版权依赖，
/// 与 test_corpus 的本地样本库无关，可直接入库运行）：
/// 1. `gen:dense-punct` 密集标点书（悬挂/挤压能力的快照载体）；
/// 2. `gen:deep-list` 深层列表嵌套书（disc→circle 层级语义）；
/// 3. `gen:bare-table` 裸表格书（无任何属性的 table，中文网文高频形态）;
/// 4. `gen:sup-footnote` 含 `<sup>` 脚注书（借行距不跳变的行为载体）；
/// 5. `gen:drop-cap` 首字下沉书（段首大字 run 近似渲染）。
///
/// 版权：全部段落为自写合成文本；字体使用仓库内 OFL 测试字体。

const String p7ChapterCss = '''
body { line-height: 1.6; }
''';

String _chapter({required String title, required String body}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
    '<title>$title</title></head><body>$body</body></html>';

String _densePunctChapter() {
  final buffer = StringBuffer();
  for (var i = 0; i < 6; i++) {
    buffer.write(
      '<p>他说：「好吧，那就这样办。」她点了点头，答道：「行、行、行。」'
      '窗外的雨，还在下；风，也没有停。大家你看看我，我看看你，'
      '谁都没有再说话……</p>',
    );
  }
  return _chapter(title: '密集标点', body: buffer.toString());
}

String _deepListChapter() {
  final buffer = StringBuffer()
    ..write('<h1>第三章 深层列表</h1>')
    ..write('<ol><li>第一层甲<ol><li>第二层甲一<ol><li>第三层甲一甲</li>'
    '<li>第三层甲一乙</li></ol></li><li>第二层甲二</li></ol></li>'
    '<li>第一层乙<ul><li>无序一</li><li>无序二</li></ul></li></ol>')
    ..write('<p>列表之后的收束段落，用来观察列表与正文之间的间距。</p>');
  return _chapter(title: '深层列表', body: buffer.toString());
}

String _bareTableChapter() {
  final buffer = StringBuffer()
    ..write('<h1>第四章 裸表格</h1>')
    ..write('<table><tr><td>甲</td><td>乙</td><td>丙</td></tr>'
    '<tr><td>1</td><td>2</td><td>3</td></tr>'
    '<tr><td>四</td><td>五</td><td>六</td></tr></table>')
    ..write('<p>表格没有 border 与样式属性，是网文最常见的裸表格形态。</p>');
  return _chapter(title: '裸表格', body: buffer.toString());
}

String _supFootnoteChapter() {
  final buffer = StringBuffer();
  for (var i = 0; i < 5; i++) {
    buffer.write(
      '<p>这一段的句子里带有脚注编号<sup>[$i]</sup>，上标借行距不应'
      '撑高行盒；相邻行的行高应保持一致，否则就是行距跳变。</p>',
    );
  }
  return _chapter(title: '脚注编号', body: buffer.toString());
}

String _dropCapChapter() {
  final buffer = StringBuffer()
    ..write('<p><span style="font-size: 32px;">山</span>'
    '中有雾，雾里有灯。灯下有人，人读旧书。这是首字下沉的近似样本，'
    '段首字符以大字号渲染。</p>');
  for (var i = 0; i < 4; i++) {
    buffer.write('<p>普通段落$i：山径、石阶、院门与柴火，构成清晨的画面。</p>');
  }
  return _chapter(title: '首字下沉', body: buffer.toString());
}

Map<String, String> _book({
  required String title,
  required String body,
  required String chapterTitle,
}) => <String, String>{
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<?xml version="1.0"?><container><rootfiles>'
      '<rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
  'OEBPS/content.opf':
      '<?xml version="1.0"?><package '
      'xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bid"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bid">urn:uuid:p7-$title</dc:identifier>'
      '<dc:title>$title</dc:title><dc:language>zh</dc:language></metadata>'
      '<manifest><item id="c1" href="c1.xhtml" '
      'media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="c1"/></spine></package>',
  'OEBPS/c1.xhtml': _chapter(title: chapterTitle, body: body),
};

/// 五类生成样本：键为回归基线里的样本名（`gen:` 前缀与本地样本区分）。
Map<String, Uint8List> buildP7SampleEpubs() => <String, Uint8List>{
  'gen:dense-punct': buildZip(
    _book(title: '密集标点', chapterTitle: '标点', body: _densePunctChapter()),
  ),
  'gen:deep-list': buildZip(
    _book(title: '深层列表', chapterTitle: '列表', body: _deepListChapter()),
  ),
  'gen:bare-table': buildZip(
    _book(title: '裸表格', chapterTitle: '表格', body: _bareTableChapter()),
  ),
  'gen:sup-footnote': buildZip(
    _book(title: '脚注编号', chapterTitle: '脚注', body: _supFootnoteChapter()),
  ),
  'gen:drop-cap': buildZip(
    _book(title: '首字下沉', chapterTitle: '下沉', body: _dropCapChapter()),
  ),
};
