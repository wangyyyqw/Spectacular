import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/position/cfi.dart';

import '../support/corpus.dart';

BlockDocument _build(String body) => BlockBuilder.build(
  DocumentParser.parse(xhtml: '<html><body>$body</body></html>', spineIndex: 0),
);

BlockNode? _block(EpubNode node, String id) {
  if (node is BlockNode) {
    if (node.id == id) {
      return node;
    }
    for (final child in node.children) {
      final found = _block(child, id);
      if (found != null) {
        return found;
      }
    }
  } else if (node is InlineNode) {
    for (final child in node.children) {
      final found = _block(child, id);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

InlineNode? _inline(EpubNode node, String id) {
  if (node is InlineNode) {
    if (node.attributes['id'] == id) {
      return node;
    }
    for (final child in node.children) {
      final found = _inline(child, id);
      if (found != null) {
        return found;
      }
    }
  } else if (node is BlockNode) {
    for (final child in node.children) {
      final found = _inline(child, id);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('嵌套 div 为块节点', () {
    final doc = _build(
      '<div id="outer"><div id="inner"><p id="p1">text</p></div></div>',
    );
    expect(_block(doc.root, 'outer')!.display, DisplayMode.block);
    expect(_block(doc.root, 'inner')!.display, DisplayMode.block);
    expect(_block(doc.root, 'p1')!.display, DisplayMode.block);
  });

  test('段落内 span 为行内节点', () {
    final doc = _build('<p id="p1">Hello <span id="s1">world</span></p>');
    expect(_block(doc.root, 'p1')!.display, DisplayMode.block);
    final span = _inline(doc.root, 's1')!;
    expect(span.tag, 'span');
    expect(
      span.children.whereType<ParsedText>().map((t) => t.text).join(),
      'world',
    );
  });

  test('ul/li 为 listItem', () {
    final doc = _build(
      '<ul id="u"><li id="l1">one</li><li id="l2">two</li></ul>',
    );
    expect(_block(doc.root, 'u')!.display, DisplayMode.block);
    expect(_block(doc.root, 'l1')!.display, DisplayMode.listItem);
    expect(_block(doc.root, 'l2')!.display, DisplayMode.listItem);
  });

  test('嵌套列表保持块结构', () {
    final doc = _build(
      '<ul id="outer"><li id="item"><ul id="inner"><li id="deep">x</li></ul></li></ul>',
    );
    expect(_block(doc.root, 'item')!.display, DisplayMode.listItem);
    expect(_block(doc.root, 'inner')!.display, DisplayMode.block);
    expect(_block(doc.root, 'deep')!.display, DisplayMode.listItem);
  });

  test('blockquote 与标题为块节点', () {
    final doc = _build(
      '<blockquote id="q"><h1 id="h">T</h1><p id="p">q</p></blockquote>',
    );
    expect(_block(doc.root, 'q')!.display, DisplayMode.block);
    expect(_block(doc.root, 'h')!.display, DisplayMode.block);
    expect(_block(doc.root, 'p')!.display, DisplayMode.block);
  });

  test('br 为行内节点', () {
    final doc = _build('<p id="p">a<br/>b</p>');
    final p = _block(doc.root, 'p')!;
    final inlineTags = <String>[];
    void walk(EpubNode node) {
      if (node is InlineNode) {
        inlineTags.add(node.tag);
        node.children.forEach(walk);
      } else if (node is BlockNode) {
        node.children.forEach(walk);
      }
    }

    walk(p);
    expect(inlineTags, contains('br'));
  });

  test('空段落与纯空白段被剔除', () {
    final doc = _build(
      '<p id="empty"></p><p id="space">   </p><p id="keep">ok</p>',
    );
    expect(_block(doc.root, 'empty'), isNull);
    expect(_block(doc.root, 'space'), isNull);
    expect(_block(doc.root, 'keep'), isNotNull);
  });

  test('script/style 不进入节点树', () {
    final doc = _build(
      '<script>bad()</script><style>.x{}</style><p id="p">ok</p>',
    );
    expect(_block(doc.root, 'p'), isNotNull);
    expect(doc.plainText, isNot(contains('bad()')));
    expect(doc.plainText, isNot(contains('.x{}')));
  });

  test('直接文本保留在块容器中', () {
    final doc = _build('<div id="d">text<span id="s">s</span></div>');
    final div = _block(doc.root, 'd')!;
    expect(
      div.children.whereType<ParsedText>().map((t) => t.text).join(),
      'text',
    );
    expect(_inline(doc.root, 's'), isNotNull);
  });

  test('displayFor 默认映射', () {
    expect(BlockBuilder.displayFor('p'), DisplayMode.block);
    expect(BlockBuilder.displayFor('li'), DisplayMode.listItem);
    expect(BlockBuilder.displayFor('span'), DisplayMode.inline);
    expect(BlockBuilder.displayFor('script'), DisplayMode.none);
    expect(BlockBuilder.displayFor('table'), DisplayMode.table);
  });

  test('块节点保留 CFI 与 id', () {
    final doc = _build('<div id="d"><p id="p">x</p></div>');
    final node = _block(doc.root, 'p')!;
    expect(node.id, 'p');
    expect(EpubCfi.parse(node.cfi.serialize()), isNotNull);
  });

  test('真实章节可构建块树', () async {
    final opened = await openEpub(
      readSampleBytes(corpus, 'real/zhushen-yuxi.epub')!,
    );
    final document = opened.document!;
    final index = document.spine.length > 50 ? 50 : 0;
    final blocks = document.parseBlocks(index);
    expect(blocks.root.children, isNotEmpty);
    expect(blocks.plainText, isNotEmpty);
  }, skip: skip);
}
