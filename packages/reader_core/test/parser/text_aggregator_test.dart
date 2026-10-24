import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/parser/text_aggregator.dart';

import '../support/corpus.dart';

BlockDocument _aggregate(String body) => TextAggregator.aggregate(
  BlockBuilder.build(
    DocumentParser.parse(
      xhtml: '<html><body>$body</body></html>',
      spineIndex: 0,
    ),
  ),
);

List<TextContentNode> _texts(EpubNode node) {
  final result = <TextContentNode>[];
  void walk(EpubNode value) {
    if (value is TextContentNode) {
      result.add(value);
    } else if (value is BlockNode) {
      value.children.forEach(walk);
    } else if (value is InlineNode) {
      value.children.forEach(walk);
    }
  }

  walk(node);
  return result;
}

TextContentNode _onlyText(BlockDocument doc) {
  final texts = _texts(doc.root);
  expect(texts, hasLength(1));
  return texts.single;
}

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('连续空白/换行/制表符折叠为单个空格并去首尾', () {
    final doc = _aggregate(
      '<p id="p">  Hello   <span>world</span>\n next\tline  </p>',
    );
    final text = _onlyText(doc);
    expect(text.text, 'Hello world next line');
    expect(text.runs, isNotEmpty);
    expect(text.runs.first.start, 0);
    expect(text.runs.last.end, text.text.length);
  });

  test('&nbsp; 与全角空格保留', () {
    final doc = _aggregate('<p id="p">a&nbsp;&nbsp;b　　c</p>');
    final text = _onlyText(doc);
    expect(text.text, 'a\u00A0\u00A0b\u3000\u3000c');
  });

  test('pre 保留换行与制表符', () {
    final doc = _aggregate('<pre id="pre">a\n\tb</pre>');
    final text = _onlyText(doc);
    expect(text.text, 'a\n\tb');
  });

  test('br 转为强制换行标记', () {
    final doc = _aggregate('<p id="p">a<br/>b</p>');
    final text = _onlyText(doc);
    expect(text.text, 'a\nb');
    expect(text.hardBreaks, <int>[1]);
  });

  test('相邻 span 文本合并为一个 TextBlockNode', () {
    final doc = _aggregate('<p id="p">a<span>b</span><b>c</b>d</p>');
    final text = _onlyText(doc);
    expect(text.text, 'abcd');
  });

  test('块级子元素切断文本聚合', () {
    final doc = _aggregate('<div id="d">before<p id="p">para</p>after</div>');
    final texts = _texts(doc.root);
    expect(texts.map((t) => t.text), <String>['before', 'para', 'after']);
  });

  test('纯空白段落聚合后不产生文本块', () {
    final doc = _aggregate('<p id="empty">   </p><p id="keep">ok</p>');
    final texts = _texts(doc.root);
    expect(texts.map((t) => t.text), <String>['ok']);
  });

  test('行内图片占一个占位字符', () {
    final doc = _aggregate('<p id="p">a<img src="x.png"/>b</p>');
    final text = _onlyText(doc);
    expect(text.text, 'a\uFFFCb');
  });

  test('内联嵌套空白跨节点折叠', () {
    final doc = _aggregate('<p id="p">a <span> b </span> c</p>');
    final text = _onlyText(doc);
    expect(text.text, 'a b c');
  });

  test('真实章节聚合文本非空', () async {
    final opened = await openEpub(
      readSampleBytes(corpus, 'real/zhushen-yuxi.epub')!,
    );
    final document = opened.document!;
    final index = document.spine.length > 50 ? 50 : 0;
    final aggregated = document.aggregateText(index);
    expect(aggregated.plainText, isNotEmpty);
    expect(_texts(aggregated.root), isNotEmpty);
  }, skip: skip);

  group('white-space 模式', () {
    BlockDocument aggregateWith(String body, CssWhiteSpace whiteSpace) =>
        TextAggregator.aggregate(
          BlockBuilder.build(
            DocumentParser.parse(
              xhtml: '<html><body>$body</body></html>',
              spineIndex: 0,
            ),
          ),
          whiteSpace: whiteSpace,
        );

    test('normal 折叠空白与换行', () {
      final text = _onlyText(
        aggregateWith('<p id="p">a  b\n c</p>', CssWhiteSpace.normal),
      );
      expect(text.text, 'a b c');
      expect(text.hardBreaks, isEmpty);
    });

    test('nowrap 同样折叠空白，只影响换行阶段', () {
      final text = _onlyText(
        aggregateWith('<p id="p">a  b\n c</p>', CssWhiteSpace.nowrap),
      );
      expect(text.text, 'a b c');
    });

    test('pre 保留空格与换行并记录强制换行位置', () {
      final text = _onlyText(
        aggregateWith('<p id="p">a  b\nc</p>', CssWhiteSpace.pre),
      );
      expect(text.text, 'a  b\nc');
      expect(text.hardBreaks, <int>[4]);
    });

    test('pre-wrap 保留空格与换行', () {
      final text = _onlyText(
        aggregateWith('<p id="p">a  b\nc</p>', CssWhiteSpace.preWrap),
      );
      expect(text.text, 'a  b\nc');
      expect(text.hardBreaks, <int>[4]);
    });

    test('pre-line 折叠空格但保留换行', () {
      final text = _onlyText(
        aggregateWith('<p id="p">a  b\nc</p>', CssWhiteSpace.preLine),
      );
      expect(text.text, 'a b\nc');
      expect(text.hardBreaks, <int>[3]);
    });

    test('pre 标签始终按 pre 处理', () {
      final text = _onlyText(_aggregate('<pre id="p">a  b</pre>'));
      expect(text.text, 'a  b');
    });
  });
}
