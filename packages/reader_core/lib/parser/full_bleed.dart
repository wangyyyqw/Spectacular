import 'block_builder.dart';
import '../src/api/models.dart' show EpubNode, TextBlockNode;

/// 满屏图页分析结果（P3-10，§8.6）。
class FullBleedChapter {
  const FullBleedChapter({
    required this.imageCount,
    required this.hasVisibleText,
    required this.singleImageSrc,
    required this.singleImageHasDimensions,
  });

  /// 章节内 img/image 元素数量。
  final int imageCount;

  /// 是否含非空白正文。
  final bool hasVisibleText;

  /// 唯一图片的 src（SVG image 用 xlink:href/href），多于一张时为 null。
  final String? singleImageSrc;

  /// 唯一图片是否声明了 width/height 属性。
  final bool singleImageHasDimensions;

  /// 章节是否走满屏路径：仅含一张**无宽高属性**的图片、无正文、
  /// src 非空。双图及以上或含正文走普通路径。
  bool get isFullBleed =>
      imageCount == 1 &&
      !hasVisibleText &&
      singleImageSrc != null &&
      singleImageSrc!.isNotEmpty &&
      !singleImageHasDimensions;
}

/// 章节满屏判定（P3-10）：扫描块树统计图片与正文。
FullBleedChapter analyzeFullBleed(BlockDocument document) {
  var imageCount = 0;
  var hasVisibleText = false;
  String? singleSrc;
  var singleHasDimensions = false;

  void visit(EpubNode node) {
    if (hasVisibleText && imageCount > 1) {
      return; // 已确定走普通路径，剪枝。
    }
    if (node is BlockNode) {
      for (final child in node.children) {
        visit(child);
      }
      return;
    }
    if (node is InlineNode) {
      if (node.tag == 'img' || node.tag == 'image') {
        imageCount += 1;
        if (imageCount == 1) {
          singleSrc = node.attributes['src'] ??
              node.attributes['xlink:href'] ??
              node.attributes['href'] ??
              '';
          singleHasDimensions =
              (node.attributes['width']?.trim().isNotEmpty ?? false) ||
                  (node.attributes['height']?.trim().isNotEmpty ?? false);
        }
      }
      for (final child in node.children) {
        visit(child);
      }
      return;
    }
    if (node is TextBlockNode) {
      if (node.text.trim().isNotEmpty) {
        hasVisibleText = true;
      }
    }
  }

  visit(document.root);
  return FullBleedChapter(
    imageCount: imageCount,
    hasVisibleText: hasVisibleText,
    singleImageSrc: imageCount == 1 ? singleSrc : null,
    singleImageHasDimensions: singleHasDimensions,
  );
}
