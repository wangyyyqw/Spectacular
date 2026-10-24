import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/full_bleed.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/position/cfi.dart';

BlockNode _block(String tag, List<Object> children) => BlockNode(
      tag: tag,
      display: DisplayMode.block,
      children: children.cast(),
      cfi: _cfi(),
      attributes: const <String, String>{},
      start: 0,
      end: 0,
    );

InlineNode _img(Map<String, String> attributes) => InlineNode(
      tag: 'img',
      children: const [],
      cfi: _cfi(),
      attributes: attributes,
      start: 0,
      end: 0,
    );

InlineNode _inline(String tag, Map<String, String> attributes) => InlineNode(
      tag: tag,
      children: const [],
      cfi: _cfi(),
      attributes: attributes,
      start: 0,
      end: 0,
    );

TextContentNode _text(String text) => TextContentNode(
      text: text,
      runs: const [],
      hardBreaks: const [],
      cfi: _cfi(),
      start: 0,
      end: 0,
    );

EpubCfi _cfi() => EpubCfi([
      const CfiSegment([
        CfiStep(6, assertion: 'x'),
      ]),
    ]);

BlockDocument _doc(BlockNode root) =>
    BlockDocument(spineIndex: 0, root: root, source: '');

void main() {
  test('单图无正文无宽高属性 → 满屏', () {
    final doc = _doc(
      _block('body', [
        _block('div', [_img({'src': 'img/pic.png'})]),
      ]),
    );
    final analysis = analyzeFullBleed(doc);
    expect(analysis.imageCount, 1);
    expect(analysis.hasVisibleText, isFalse);
    expect(analysis.singleImageSrc, 'img/pic.png');
    expect(analysis.isFullBleed, isTrue);
  });

  test('SVG image 元素按 xlink:href 取 src', () {
    final doc = _doc(
      _block('body', [
        _inline('image', {'xlink:href': 'svg/cover.svg'}),
      ]),
    );
    final analysis = analyzeFullBleed(doc);
    expect(analysis.singleImageSrc, 'svg/cover.svg');
    expect(analysis.isFullBleed, isTrue);
  });

  test('声明 width/height 属性 → 普通路径', () {
    final doc = _doc(
      _block('body', [
        _img({'src': 'a.png', 'width': '100', 'height': '50'}),
      ]),
    );
    expect(analyzeFullBleed(doc).isFullBleed, isFalse);
  });

  test('双图 → 普通路径', () {
    final doc = _doc(
      _block('body', [
        _img({'src': 'a.png'}),
        _img({'src': 'b.png'}),
      ]),
    );
    expect(analyzeFullBleed(doc).isFullBleed, isFalse);
  });

  test('有正文 → 普通路径；纯空白不算正文', () {
    final withText = _doc(
      _block('body', [
        _text('正文'),
        _img({'src': 'a.png'}),
      ]),
    );
    expect(analyzeFullBleed(withText).isFullBleed, isFalse);

    final blankOnly = _doc(
      _block('body', [
        _text('  \n\t'),
        _img({'src': 'a.png'}),
      ]),
    );
    expect(analyzeFullBleed(blankOnly).isFullBleed, isTrue);
  });

  test('src 为空 → 不满屏', () {
    final doc = _doc(
      _block('body', [_img(const <String, String>{})]),
    );
    expect(analyzeFullBleed(doc).isFullBleed, isFalse);
  });
}
