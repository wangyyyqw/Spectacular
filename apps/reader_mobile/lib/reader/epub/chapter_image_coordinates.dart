import 'package:reader_core/parser/document_parser.dart';

import 'chapter_raw_styles.dart';

typedef ChapterImageCoordinates = ({
  List<String> cfis,
  Map<String, String> legacyAliases,
});

/// 图片章使用真实渲染叶元素顺序，SVG 容器不替代内层 image。
ChapterImageCoordinates imageCoordinatesOf(
  ParsedElement root,
  ChapterRawStyles styles,
) {
  final collector = _ImageCoordinates(styles);
  collector.walk(root);
  return (
    cfis: List.unmodifiable(collector.cfis),
    legacyAliases: Map.unmodifiable(collector.aliases),
  );
}

class _ImageCoordinates {
  _ImageCoordinates(this.styles);
  final ChapterRawStyles styles;
  final List<String> cfis = [];
  final Map<String, String> aliases = {};

  void walk(ParsedElement element) {
    if (!styles.isVisibleElement(element)) return;
    final start = cfis.length;
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
    // 仅有一个可见图片后代时兼容旧折叠父 CFI，不按重复 src 猜位置。
    if (cfis.length == start + 1) aliases[element.cfi.serialize()] = cfis.last;
  }
}
