/// 跨模块共享的数据模型。
///
/// 这里的类型只描述契约，不包含解析或布局实现；字段以《技术方案》§81 为依据。
library;

/// 书籍元信息，来自 OPF 的 metadata 段。
class BookMeta {
  /// 创建元信息。
  const BookMeta({
    required this.title,
    required this.author,
    required this.language,
    required this.identifier,
  });

  /// 书名。
  final String title;

  /// 作者，缺失时为空串。
  final String author;

  /// 语言标签（BCP 47）。
  final String language;

  /// 唯一标识，字体解混淆时也用作密钥来源。
  final String identifier;
}

/// spine 中的一项。
class SpineItem {
  /// 创建 spine 项。
  const SpineItem({
    required this.index,
    required this.href,
    required this.mediaType,
    this.linear = true,
  });

  /// 在 spine 中的序号，从 0 开始。
  final int index;

  /// 相对 OPF 的路径。
  final String href;

  /// 媒体类型。
  final String mediaType;

  /// 是否属于线性阅读顺序。
  final bool linear;
}

/// 目录项。
class TocEntry {
  /// 创建目录项。
  const TocEntry({
    required this.title,
    required this.spineIndex,
    this.fragment,
    this.children = const <TocEntry>[],
  });

  /// 显示标题。
  final String title;

  /// 指向的 spine 序号。
  final int spineIndex;

  /// 章内片段标识，可为空。
  final String? fragment;

  /// 子目录。
  final List<TocEntry> children;
}

/// 导入结果与可读性分级。
class ImportReport {
  /// 创建导入报告。
  const ImportReport({
    required this.ok,
    this.errorCode,
    this.message,
    this.warnings = const <String>[],
    this.readabilityLevel = 0,
  });

  /// 是否可用于阅读。
  final bool ok;

  /// 失败时的结构化错误码。
  final String? errorCode;

  /// 可读的错误说明。
  final String? message;

  /// 导入过程中的修复与告警。
  final List<String> warnings;

  /// 可读性分级 L0～L4。
  final int readabilityLevel;
}

/// 一页的布局参数。
class LayoutMetrics {
  /// 创建布局参数。
  const LayoutMetrics({
    required this.pageWidth,
    required this.pageHeight,
    required this.contentWidth,
    required this.contentHeight,
    required this.devicePixelRatio,
    required this.fontSize,
  });

  /// 页面逻辑宽。
  final double pageWidth;

  /// 页面逻辑高。
  final double pageHeight;

  /// 正文区宽。
  final double contentWidth;

  /// 正文区高。
  final double contentHeight;

  /// 设备像素比。
  final double devicePixelRatio;

  /// 基准字号。
  final double fontSize;
}

/// 绘制上下文。
class PaintContext {
  /// 创建绘制上下文。
  const PaintContext({
    required this.pageIndex,
    required this.locator,
    required this.metrics,
  });

  /// 当前页序号。
  final int pageIndex;

  /// 当前页起始位置。
  final Locator locator;

  /// 页面布局参数。
  final LayoutMetrics metrics;
}

/// 一条标注。
class Annotation {
  /// 创建标注。
  const Annotation({
    required this.id,
    required this.bookId,
    required this.locator,
    required this.colorValue,
    required this.createdAt,
    this.note,
  });

  /// 标注 ID。
  final String id;

  /// 所属书籍 ID。
  final int bookId;

  /// 起始位置。
  final Locator locator;

  /// 颜色（ARGB）。
  final int colorValue;

  /// 创建时间。
  final DateTime createdAt;

  /// 备注文本，可为空。
  final String? note;
}

/// 可取消任务令牌。
class CancelToken {
  bool _cancelled = false;

  /// 是否已取消。
  bool get isCancelled => _cancelled;

  /// 请求取消；可重复调用。
  void cancel() {
    _cancelled = true;
  }
}

/// 已解析的排版树节点。
abstract interface class EpubNode {}

/// 元素节点（可参与样式计算）。
abstract interface class Element implements EpubNode {}

/// 文本块节点（行分割输入）。
abstract interface class TextBlockNode implements EpubNode {}

/// 计算后的样式。
abstract interface class ComputedStyle {}

/// 文本行布局结果。
abstract interface class TextLayout {}

/// 页码位置（CFI 或内部位置编码）。
abstract interface class Locator {}

/// 一页内容切片。
abstract interface class PageSlice {}
