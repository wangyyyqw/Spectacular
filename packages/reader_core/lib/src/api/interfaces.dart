/// 跨模块接口定义。
///
/// 接口只接收已解析对象，不接收原始 HTML/CSS 字符串；失败路径返回 null 或
/// [ImportReport]，不抛出未捕获异常。
library;

import 'dart:typed_data';
import 'dart:ui' show Canvas, Image;

import 'package:flutter/rendering.dart' show SemanticsBuilderCallback;

import 'models.dart';

/// 已打开的 EPUB 文档。
abstract interface class EpubDocument {
  /// 书籍元信息。
  BookMeta get meta;

  /// 线性阅读顺序。
  List<SpineItem> get spine;

  /// 目录，已按回退链构建。
  List<TocEntry> get toc;

  /// 导入报告（含修复与分级）。
  ImportReport get report;

  /// 读取并解析指定 spine 的内容。
  Future<SpineDocument> readSpine(int spineIndex);
}

/// 单章文档树。
abstract interface class SpineDocument {
  /// spine 序号。
  int get spineIndex;

  /// 已算好样式的排版树根节点。
  EpubNode get root;

  /// 纯文本，用于搜索、进度与 TTS。
  String get plainText;

  /// 字符数。
  int get charCount;
}

/// 资源读取。
abstract interface class ResourceResolver {
  /// 按 href 读取原始字节；未命中返回 null。
  Future<Uint8List?> bytes(String href, {String? baseDir});

  /// 按目标显示宽度解码图片；未命中返回 null。
  Future<Image?> image(
    String href, {
    required double displayWidth,
    required double devicePixelRatio,
  });
}

/// 样式计算。
abstract interface class StyleResolver {
  /// 计算元素样式。
  ComputedStyle compute(Element element, ComputedStyle? parent);

  /// 根样式，供页高与字号基准使用。
  ComputedStyle get rootStyle;
}

/// 行切分。
abstract interface class LineBreaker {
  /// 对文本块做行切分。
  TextLayout breakText(
    TextBlockNode block,
    double maxWidth,
    ComputedStyle style,
  );
}

/// 章节分页。
abstract interface class Paginator {
  /// 分页并按页增量产出；必须响应 [CancelToken]。
  Future<List<PageSlice>> paginate(
    SpineDocument document,
    LayoutMetrics metrics,
    CancelToken token,
  );
}

/// 页绘制。
abstract interface class PageRenderer {
  /// 绘制一页。
  void paint(Canvas canvas, PageSlice page, PaintContext context);

  /// 无障碍语义构建回调；不支持时返回 null。
  SemanticsBuilderCallback? semantics(PageSlice page);
}

/// 位置编码与比较。
abstract interface class LocatorCodec {
  /// 解析字符串位置；非法输入返回 null。
  Locator? parse(String value);

  /// 序列化位置。
  String serialize(Locator locator);

  /// 比较两个位置的全序。
  int compare(Locator a, Locator b);

  /// 由节点与字符偏移构造位置。
  Locator forNode(EpubNode node, {int charOffset = 0});
}

/// 标注存取。
abstract interface class AnnotationStore {
  /// 列出某本书的标注。
  Future<List<Annotation>> list(int bookId);

  /// 新增或更新标注。
  Future<void> upsert(Annotation annotation);

  /// 删除标注。
  Future<void> delete(String id);
}
