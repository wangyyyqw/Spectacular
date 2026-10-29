import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/parser/text_aggregator.dart';

List<TextContentNode> textsOf(EpubNode node) => switch (node) {
  TextContentNode() => [node],
  BlockNode() => node.children.expand(textsOf).toList(),
  _ => [],
};

BlockDocument aggregate(String body, {bool classify = true}) =>
    TextAggregator.aggregate(
      BlockBuilder.build(
        DocumentParser.parse(
          xhtml: '<html><body>$body</body></html>',
          spineIndex: 0,
        ),
      ),
      inlineDisplay: !classify
          ? null
          : (node, ancestors) => switch (node.attributes['class']) {
              'block' => CssDisplay.block,
              'hidden' => CssDisplay.none,
              _ => CssDisplay.inline,
            },
    );

void main() {
  test('缺省调用仍按 UA 合并，回调只改变明确指定的显示分类', () {
    const body = '<p>前<span class="block">中</span>后</p>';
    expect(textsOf(aggregate(body, classify: false).root).single.text, '前中后');
    expect(textsOf(aggregate(body).root).map((node) => node.text), [
      '前',
      '中',
      '后',
    ]);
  });

  test('跨块行内标记分片重开，并保留提升块的行内祖先', () {
    final document = aggregate(
      '<p>前<b>粗<span class="block">中</span>后</b>尾</p>',
    );
    final texts = textsOf(document.root);
    expect(texts.map((node) => node.text), ['前粗', '中', '后尾']);
    expect(texts.first.inlineMarks.single.start, 1);
    expect(texts.first.inlineMarks.single.end, 2);
    expect(texts.last.inlineMarks.single.start, 0);
    expect(texts.last.inlineMarks.single.end, 1);
    final paragraph = document.root.children.single as BlockNode;
    final promoted = paragraph.children.whereType<PromotedBlockNode>().single;
    expect(promoted.inlineAncestors.map((node) => node.tag), ['b']);
    expect(texts.map((node) => node.cfi.serialize()).toSet(), hasLength(3));
  });

  test('隐藏子树不产生文字、图片或行内标记', () {
    final text = textsOf(
      aggregate(
        '<p>前<span class="hidden">'
        '隐藏<img src="hidden.png"/><span class="block">块</span></span>后</p>',
      ).root,
    ).single;
    expect(text.text, '前后');
    expect(text.inlineImages, isEmpty);
    expect(text.inlineMarks, isEmpty);
  });

  test('块边界前的图片不污染后文，末尾纯图不覆盖已有块', () {
    final document = aggregate(
      '<p>前<img src="a.png"/>'
      '<span class="block">中</span>后<img src="b.png"/></p>',
    );
    final texts = textsOf(document.root);
    expect(texts.map((node) => node.text), ['前\uFFFC', '中', '后\uFFFC']);
    expect(
      texts.first.inlineImages.map((image) => image.node.attributes['src']),
      ['a.png'],
    );
    expect(
      texts.last.inlineImages.map((image) => image.node.attributes['src']),
      ['b.png'],
    );
    expect(texts.last.inlineImages.single.offset, 1);
    final trailing = aggregate(
      '<p>前<span class="block">中</span><img src="b.png"/></p>',
    );
    expect(textsOf(trailing.root).map((node) => node.text), [
      '前',
      '中',
      '\uFFFC',
    ]);
  });

  test('只有前导空白的片段不会把位置泄漏给块后文本', () {
    final texts = textsOf(
      aggregate('<p> <span class="block">中</span>后</p>').root,
    );
    expect(texts.map((node) => node.text), ['中', '后']);
    expect(texts.last.cfi.serialize(), endsWith('!/4/2/3)'));
    expect((texts.last.start, texts.last.end), (44, 45));
  });

  test('块边界分片 ruby，后文注音不会挂到前一片', () {
    final texts = textsOf(
      aggregate(
        '<p>前<ruby>汉<rt>han</rt><span class="block">块</span>'
        '字<rt>zi</rt></ruby>后</p>',
      ).root,
    );
    expect(texts.map((node) => node.text), ['前汉', '块', '字后']);
    expect(texts.first.rubies.single.text, 'han');
    expect(texts.last.rubies.single.text, 'zi');

    final noPrefix = textsOf(
      aggregate(
        '<p><ruby>汉<rt>han</rt><span class="block">块</span>'
        '字<rt>zi</rt></ruby>后</p>',
      ).root,
    );
    expect(noPrefix.map((node) => node.text), ['汉', '块', '字后']);
    expect(noPrefix.first.rubies.single.text, 'han');
    expect(noPrefix.last.rubies.single.text, 'zi');
  });

  test('注音内部沿用隐藏规则', () {
    final text = textsOf(
      aggregate(
        '<p><ruby>汉<rt>han<span class="hidden">LEAK</span></rt></ruby></p>',
      ).root,
    ).single;
    expect(text.rubies.single.text, 'han');
  });
}
