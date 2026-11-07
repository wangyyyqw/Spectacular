import 'block_builder.dart';
import 'document_parser.dart' show ParsedText;
import '../src/api/models.dart' show EpubNode, TextBlockNode;

/// 满屏图页分析结果（P3-10，§8.6）。
class FullBleedChapter {
  const FullBleedChapter({
    required this.imageCount,
    required this.hasVisibleText,
    required this.singleImageSrc,
    required this.singleImageHasDimensions,
    this.singleImageCfi,
  });

  /// 章节内 img/image 与带 data 的 object 图片叶数量。
  final int imageCount;

  /// 是否含非空白正文。
  final bool hasVisibleText;

  /// 唯一图片引用（SVG 使用 href，object 使用 data），多于一张时为 null。
  final String? singleImageSrc;

  /// 唯一图片在聚合前显示树中的真实叶 CFI，与计数和可见性同次确认。
  final String? singleImageCfi;

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
///
/// [isRendered] 可排除被作者 CSS 隐藏的行内子树；未提供时保持纯结构判定。
FullBleedChapter analyzeFullBleed(
  BlockDocument document, {
  bool Function(EpubNode node)? isRendered,
}) {
  final analysis = _FullBleedAnalysis(isRendered);
  analysis.visit(document.root);
  return analysis.result;
}

/// 每次扫描独立保存计数和唯一叶坐标，不引用聚合后的伪父位置。
class _FullBleedAnalysis {
  _FullBleedAnalysis(this.isRendered);
  final bool Function(EpubNode node)? isRendered;
  int _imageCount = 0;
  bool _hasVisibleText = false;
  String? _singleSrc;
  String? _singleCfi;
  bool _singleHasDimensions = false;

  FullBleedChapter get result => FullBleedChapter(
    imageCount: _imageCount,
    hasVisibleText: _hasVisibleText,
    singleImageSrc: _imageCount == 1 ? _singleSrc : null,
    singleImageCfi: _imageCount == 1 ? _singleCfi : null,
    singleImageHasDimensions: _singleHasDimensions,
  );

  void visit(EpubNode node) {
    if (_hasVisibleText && _imageCount > 1) {
      return; // 已确定走普通路径，剪枝。
    }
    if (!_isVisible(node)) return;
    if (node is BlockNode) {
      _visitChildren(node.children);
      return;
    }
    if (node is InlineNode) {
      final objectImage =
          node.tag == 'object' &&
          (node.attributes['data']?.trim().isNotEmpty ?? false);
      if (node.tag == 'img' || node.tag == 'image' || objectImage) {
        _recordImage(node);
        // 可用 object 是图片替换元素，备用文字/图片不进入实际正文流。
        if (objectImage) return;
      }
      _visitChildren(node.children);
      return;
    }
    if (node is TextBlockNode) {
      _recordText(node.text);
    } else if (node is ParsedText) {
      // 原始显示树的文本同样计入正文，避免单图快路丢失文字。
      _recordText(node.text);
    }
  }

  bool _isVisible(EpubNode node) {
    final rendered = isRendered;
    return rendered == null ||
        (node is! BlockNode && node is! InlineNode) ||
        rendered(node);
  }

  void _visitChildren(List<EpubNode> children) {
    for (final child in children) {
      visit(child);
    }
  }

  void _recordImage(InlineNode node) {
    _imageCount += 1;
    if (_imageCount != 1) return;
    _singleSrc =
        node.attributes['src'] ??
        node.attributes['xlink:href'] ??
        node.attributes['href'] ??
        (node.tag == 'object' ? node.attributes['data'] : null) ??
        '';
    _singleCfi = node.cfi.serialize();
    _singleHasDimensions =
        (node.attributes['width']?.trim().isNotEmpty ?? false) ||
        (node.attributes['height']?.trim().isNotEmpty ?? false);
  }

  void _recordText(String text) {
    if (text.trim().isNotEmpty) _hasVisibleText = true;
  }
}
