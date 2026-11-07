import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/parser/full_bleed.dart';
import 'package:reader_core/position/cfi.dart';

({ParsedDocument parsed, BlockDocument display}) _chapter(String body) {
  final parsed = DocumentParser.parse(
    xhtml:
        '<html xmlns="http://www.w3.org/1999/xhtml">'
        '<head/><body>$body</body></html>',
    spineIndex: 0,
  );
  return (parsed: parsed, display: BlockBuilder.build(parsed));
}

void _expectLeaf(FullBleedChapter analysis, ParsedDocument parsed, String id) {
  final leaf = parsed.elementById(id)!;
  expect(analysis.singleImageCfi, leaf.cfi.serialize());
  expect(
    parsed.nodeAtCfi(EpubCfi.parse(analysis.singleImageCfi!)!),
    same(leaf),
  );
}

void main() {
  for (final (tag, reference) in [
    ('img', 'src'),
    ('image', 'href'),
    ('object', 'data'),
  ]) {
    test('单 $tag 从聚合前 display 冻结自己的真实叶 CFI', () {
      final image = '<$tag id="leaf" $reference="p.png"/>';
      final fixture = _chapter(
        '<div id="parent">${tag == 'image' ? '<svg>$image</svg>' : image}</div>',
      );
      final analysis = analyzeFullBleed(fixture.display);
      expect(analysis.imageCount, 1);
      expect(analysis.singleImageSrc, 'p.png');
      expect(analysis.isFullBleed, isTrue);
      _expectLeaf(analysis, fixture.parsed, 'leaf');
      expect(
        analysis.singleImageCfi,
        isNot(fixture.parsed.elementById('parent')!.cfi.serialize()),
      );
    });
  }

  test('重复引用的 object 与 img 统计为两张图，不提供单图快路 CFI', () {
    final fixture = _chapter(
      '<div><object id="a" data="p.png"/></div>'
      '<div><img id="b" src="p.png"/></div>',
    );
    final analysis = analyzeFullBleed(fixture.display);
    expect(analysis.imageCount, 2);
    expect(analysis.hasVisibleText, isFalse);
    expect(analysis.singleImageSrc, isNull);
    expect(analysis.singleImageCfi, isNull);
    expect(analysis.isFullBleed, isFalse);
  });

  test('隐藏回调排除同引用 object 子树，唯一可见 img 冻结自身 CFI', () {
    final fixture = _chapter(
      '<div hidden="hidden"><object data="p.png"/></div>'
      '<div><img id="leaf" src="p.png"/></div>',
    );
    final analysis = analyzeFullBleed(
      fixture.display,
      isRendered: (node) => switch (node) {
        BlockNode() => !node.attributes.containsKey('hidden'),
        InlineNode() => !node.attributes.containsKey('hidden'),
        _ => true,
      },
    );
    expect(analysis.imageCount, 1);
    _expectLeaf(analysis, fixture.parsed, 'leaf');
  });

  test('带 data 的 object 是替换图片，其备用正文与后代图片不重复统计', () {
    final fixture = _chapter(
      '<object id="leaf" data="p.png">备用正文<img src="p.png"/></object>',
    );
    final analysis = analyzeFullBleed(fixture.display);
    expect(analysis.imageCount, 1);
    expect(analysis.hasVisibleText, isFalse);
    expect(analysis.isFullBleed, isTrue);
    _expectLeaf(analysis, fixture.parsed, 'leaf');
  });

  test('缺少或空白 data 的 object 保留备用正文，不作为图片统计', () {
    for (final attributes in ['', ' data="  "']) {
      final fixture = _chapter('<object$attributes>备用正文</object>');
      final analysis = analyzeFullBleed(fixture.display);
      expect(analysis.imageCount, 0);
      expect(analysis.singleImageCfi, isNull);
      expect(analysis.hasVisibleText, isTrue);
      expect(analysis.isFullBleed, isFalse);
    }
  });
}
