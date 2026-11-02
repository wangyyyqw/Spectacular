/// 默认高亮颜色。
const int defaultHighlightColor = 0xFFFFEB3B;

/// 标注类型（P4-17，§30.2 / §36.1）。
enum ReaderAnnotationType {
  /// 高亮。
  highlight(0),

  /// 笔记（高亮 + 备注）。
  note(1);

  const ReaderAnnotationType(this.storageValue);

  /// 数据库存储值（annotations.type）。
  final int storageValue;

  /// 由存储值解析；未知值按高亮处理。
  static ReaderAnnotationType fromStorage(int value) =>
      value == note.storageValue ? note : highlight;
}

/// 高亮装饰样式。
enum ReaderAnnotationStyle {
  /// 半透明底色（旧数据默认样式）。
  background(0),

  /// 实线下划线。
  underline(1),

  /// 波浪下划线。
  wavyUnderline(2),

  /// 虚线下划线。
  dashedUnderline(3);

  const ReaderAnnotationStyle(this.storageValue);

  /// 数据库存储值（annotations.style）。
  final int storageValue;

  /// 由存储值解析；空值或未知值按底色处理。
  static ReaderAnnotationStyle fromStorage(int? value) {
    for (final style in values) {
      if (style.storageValue == value) {
        return style;
      }
    }
    return background;
  }
}

/// 标注（P4-17）：CFI 区间 + 颜色 + 备注 + 前后文上下文。
///
/// CFI 是重排后仍能定位的唯一坐标；quote 与前后文用于兜底重定位（P4-20）。
class ReaderAnnotation {
  /// 创建标注。
  const ReaderAnnotation({
    required this.id,
    required this.type,
    required this.startCfi,
    required this.endCfi,
    required this.quote,
    required this.createdAt,
    required this.updatedAt,
    this.contextBefore,
    this.contextAfter,
    this.color,
    this.style = ReaderAnnotationStyle.background,
    this.note,
  });

  /// 唯一标识。
  final String id;

  /// 类型。
  final ReaderAnnotationType type;

  /// 起始 CFI。
  final String startCfi;

  /// 结束 CFI。
  final String endCfi;

  /// 原文引用。
  final String quote;

  /// 前文上下文（约 20 字）。
  final String? contextBefore;

  /// 后文上下文（约 20 字）。
  final String? contextAfter;

  /// 颜色（ARGB）。
  final int? color;

  /// 高亮装饰样式。
  final ReaderAnnotationStyle style;

  /// 笔记正文。
  final String? note;

  /// 创建时间。
  final DateTime createdAt;

  /// 更新时间。
  final DateTime updatedAt;
}

/// 标注存储（P4-17）：阅读页通过它读写标注，app 层用数据库实现。
abstract interface class ReaderAnnotationStore {
  /// 全部标注（按创建时间排序）。
  Future<List<ReaderAnnotation>> list();

  /// 新增标注；同一区间（同类型 + 同起止 CFI）已存在时不重复写入，返回 null。
  Future<ReaderAnnotation?> add({
    required ReaderAnnotationType type,
    required String startCfi,
    required String endCfi,
    required String quote,
    String? contextBefore,
    String? contextAfter,
    int? color,
    ReaderAnnotationStyle style = ReaderAnnotationStyle.background,
    String? note,
  });

  /// 更新类型、颜色、样式或备注。
  Future<void> update(
    String id, {
    ReaderAnnotationType? type,
    int? color,
    ReaderAnnotationStyle? style,
    String? note,
  });

  /// 删除标注。
  Future<void> remove(String id);
}
