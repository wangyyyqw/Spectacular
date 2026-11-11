import 'package:flutter/painting.dart';

/// 页边距（P8-10 边距调节器）：上下各拆成「外（页眉页脚外侧）/ 内（正文侧）」
/// 两段。
///
/// 上外段是屏幕边界到页眉的距离，上内段是页眉到正文的距离；下内、下外分别
/// 是正文到页脚、页脚到屏幕边界的距离。两段都允许调到 0，因此可以做出正文
/// 铺进安全区的全屏效果。
class ReaderMargins {
  /// 创建页边距。
  const ReaderMargins({
    required this.left,
    required this.right,
    required this.topOuter,
    required this.topInner,
    required this.bottomInner,
    required this.bottomOuter,
  });

  /// 由安全区与常规边距生成默认值（首次进入阅读页用）。
  factory ReaderMargins.defaults({
    double safeTop = 0,
    double safeBottom = 0,
    double side = 20,
    double inner = 12,
  }) {
    return ReaderMargins(
      left: side,
      right: side,
      topOuter: safeTop,
      topInner: inner,
      bottomInner: inner,
      bottomOuter: safeBottom,
    );
  }

  /// 左右边距。
  final double left;
  final double right;

  /// 上外（状态栏/挖孔区留白）。
  final double topOuter;

  /// 上内（正文顶部留白）。
  final double topInner;

  /// 下内（正文底部留白）。
  final double bottomInner;

  /// 下外（手势条区留白）。
  final double bottomOuter;

  /// 上边距合计（不含页眉自身高度）。
  double get top => topOuter + topInner;

  /// 下边距合计（不含页脚自身高度）。
  double get bottom => bottomInner + bottomOuter;

  /// 页眉页脚外侧留白：屏幕边界到页眉、页脚或左右正文边界的距离。
  EdgeInsets toOuterPadding() =>
      EdgeInsets.fromLTRB(left, topOuter, right, bottomOuter);

  /// 正文四边；[showFurniture] 为 true 时给页眉页脚自身高度让位。
  EdgeInsets toBodyPadding({
    required bool showFurniture,
    double headerHeight = 0,
    double footerHeight = 0,
  }) {
    final topFurniture = showFurniture ? headerHeight : 0.0;
    final bottomFurniture = showFurniture ? footerHeight : 0.0;
    return EdgeInsets.fromLTRB(
      left,
      topOuter + topFurniture + topInner,
      right,
      bottomOuter + bottomFurniture + bottomInner,
    );
  }

  /// 不包含页眉页脚自身高度的合计边距。
  EdgeInsets toPadding() => EdgeInsets.fromLTRB(left, top, right, bottom);

  /// 复制并覆盖若干项。
  ReaderMargins copyWith({
    double? left,
    double? right,
    double? topOuter,
    double? topInner,
    double? bottomInner,
    double? bottomOuter,
  }) {
    return ReaderMargins(
      left: left ?? this.left,
      right: right ?? this.right,
      topOuter: topOuter ?? this.topOuter,
      topInner: topInner ?? this.topInner,
      bottomInner: bottomInner ?? this.bottomInner,
      bottomOuter: bottomOuter ?? this.bottomOuter,
    );
  }

  /// 序列化（持久化用）。
  Map<String, Object?> toJson() => <String, Object?>{
    'left': left,
    'right': right,
    'topOuter': topOuter,
    'topInner': topInner,
    'bottomInner': bottomInner,
    'bottomOuter': bottomOuter,
  };

  /// 反序列化；缺字段或非法值退回 [defaults]。
  static ReaderMargins? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    double read(String key, double fallback) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    return ReaderMargins(
      left: read('left', 20),
      right: read('right', 20),
      topOuter: read('topOuter', 0),
      topInner: read('topInner', 12),
      bottomInner: read('bottomInner', 12),
      bottomOuter: read('bottomOuter', 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderMargins &&
      other.left == left &&
      other.right == right &&
      other.topOuter == topOuter &&
      other.topInner == topInner &&
      other.bottomInner == bottomInner &&
      other.bottomOuter == bottomOuter;

  @override
  int get hashCode =>
      Object.hash(left, right, topOuter, topInner, bottomInner, bottomOuter);

  @override
  String toString() =>
      'ReaderMargins(左右 $left/$right, 上外 $topOuter+内 $topInner, '
      '下外 $bottomOuter+内 $bottomInner)';
}
