import 'package:flutter/painting.dart';

/// 页边距（P8-10 边距调节器）：上下各拆成「外（安全区）/ 内（正文）」两段。
///
/// 外段对应状态栏/挖孔与手势条区域，内段是正文自己的留白。两段都允许调到 0，
/// 因此可以做出「正文铺进安全区」的全屏效果；也允许把外段调大，把正文整体
/// 从系统栏下推。
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

  /// 上边距合计。
  double get top => topOuter + topInner;

  /// 下边距合计。
  double get bottom => bottomInner + bottomOuter;

  /// 转成 Padding 用的四边。
  EdgeInsets toPadding() =>
      EdgeInsets.fromLTRB(left, top, right, bottom);

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
  int get hashCode => Object.hash(
    left,
    right,
    topOuter,
    topInner,
    bottomInner,
    bottomOuter,
  );

  @override
  String toString() =>
      'ReaderMargins(左右 $left/$right, 上外 $topOuter+内 $topInner, '
      '下外 $bottomOuter+内 $bottomInner)';
}
