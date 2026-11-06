import 'decoration_style.dart';
export 'decoration_style.dart';

/// 手工添加的文字装饰，使用与阅读标注相同的内容锚点。
class ReaderDecoration {
  /// 创建装饰记录。
  const ReaderDecoration({
    required this.id,
    required this.startCfi,
    required this.endCfi,
    required this.quote,
    required this.style,
    required this.createdAt,
    required this.updatedAt,
    this.contextBefore,
    this.contextAfter,
    this.anchorData,
    this.relocationStatus,
    this.relocationReason,
    this.currentQuote,
  });

  /// 唯一标识。
  final String id;

  /// 原文起点。
  final String startCfi;

  /// 原文终点。
  final String endCfi;

  /// 原始引用。
  final String quote;

  /// 前文证据。
  final String? contextBefore;

  /// 后文证据。
  final String? contextAfter;

  /// 内容锚点 JSON。
  final String? anchorData;

  /// 迁移验证状态。
  final String? relocationStatus;

  /// 迁移失败原因。
  final String? relocationReason;

  /// 当前版本引用。
  final String? currentQuote;

  /// 样式。
  final ReaderDecorationStyle style;

  /// 创建时间。
  final DateTime createdAt;

  /// 更新时间。
  final DateTime updatedAt;

  /// 待修复装饰不参与绘制。
  bool get needsRelocation =>
      relocationStatus != null &&
      relocationStatus != 'verified' &&
      relocationStatus != 'relocated';
}

/// 宿主提供的装饰持久化接口。
abstract interface class ReaderDecorationStore {
  /// 当前书全部手工装饰。
  Future<List<ReaderDecoration>> list();

  /// 同区间更新样式，否则新建。
  Future<ReaderDecoration?> add({
    required String startCfi,
    required String endCfi,
    required String quote,
    required ReaderDecorationStyle style,
    String? contextBefore,
    String? contextAfter,
  });

  /// 修改样式。
  Future<void> update(String id, {required ReaderDecorationStyle style});

  /// 删除记录。
  Future<void> remove(String id);

  /// 关联用户重新选择的原文位置。
  Future<void> relocate(
    String id, {
    required String startCfi,
    required String endCfi,
  });
}
