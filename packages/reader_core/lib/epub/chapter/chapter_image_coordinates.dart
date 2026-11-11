import 'package:reader_core/parser/document_parser.dart';

import 'chapter_raw_styles.dart';

/// 图片章使用真实渲染叶元素顺序，SVG 容器不替代内层 image。
List<String> imageCoordinatesOf(ParsedElement root, ChapterRawStyles styles) {
  final collector = _ImageCoordinates(styles);
  collector.walk(root);
  return List.unmodifiable(collector.cfis);
}

class _ImageCoordinates {
  _ImageCoordinates(this.styles);
  final ChapterRawStyles styles;
  final List<String> cfis = [];

  void walk(ParsedElement element) {
    if (!styles.isVisibleElement(element)) return;
    final objectImage =
        element.tag == 'object' &&
        (element.attributes['data']?.trim().isNotEmpty ?? false);
    if (element.tag == 'img' || element.tag == 'image' || objectImage) {
      cfis.add(element.cfi.serialize());
      return;
    }
    for (final child in element.children.whereType<ParsedElement>()) {
      walk(child);
    }
  }
}
