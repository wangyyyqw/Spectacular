import 'dart:ui' show Rect;

/// 浮动方向。
enum FloatSide { left, right }

/// 一个浮动元素在文档坐标中占据的区域（P3-12，技术方案 §48.1 阅微模型）。
class BoxOccupied {
  const BoxOccupied({
    required this.rect,
    required this.baseline,
    required this.side,
  });

  /// 占据矩形（文档坐标：y 相对当前分页流起点）。
  final Rect rect;

  /// 所属行基线，用于同基线合并。
  final double baseline;

  /// 左浮 / 右浮。
  final FloatSide side;

  @override
  String toString() =>
      'BoxOccupied(${side.name} $rect baseline=$baseline)';
}

/// 浮动占用模型：按高度区间记录左右被占宽度，支撑绕排约束查询与
/// 分页切分（P3-12；P3-13 的 createPlaceholders 与 P3-15 跨页衔接
/// 在此之上实现）。
class FloatOccupancy {
  /// 创建空模型。
  FloatOccupancy();

  final List<BoxOccupied> _items = <BoxOccupied>[];

  /// 当前占用项（声明顺序，只读视图）。
  List<BoxOccupied> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  /// 登记一个浮动占用。
  void insert(BoxOccupied item) {
    _items.add(item);
  }

  /// 移除与 [rect] 相交的占用项（float 清除/元素移出流时用）。
  void removeIntersecting(Rect rect) {
    _items.removeWhere((item) => item.rect.overlaps(rect));
  }

  /// 清空。
  void clear() {
    _items.clear();
  }

  /// 某侧浮动的最大底边（无则 0）——clear 语义的推移目标（§48.3 第 3 条）。
  double maxBottom(FloatSide side) {
    var bottom = 0.0;
    for (final item in _items) {
      if (item.side == side && item.rect.bottom > bottom) {
        bottom = item.rect.bottom;
      }
    }
    return bottom;
  }

  /// 移除某侧底边不超过 [y] 的占用（clear 满足后这些浮动不再约束
  /// 后续内容，§48.3 第 3 条）。
  void removeSatisfiedBelow(double y, FloatSide side) {
    _items.removeWhere(
      (item) => item.side == side && item.rect.bottom <= y,
    );
  }

  /// 跨页浮动切分（P3-15，§48.4）：按页高逐页切分占用。
  ///
  /// [entry] 是首页入页时的占用（容器测量产物）；返回每页入页时的
  /// 占用表——下一页以裁剪后的剩余重新登记（y 归零，§48.1「占位元素
  /// 在分页时被切开」）。页数超出浮动存活范围后为空表（全宽恢复）。
  static List<FloatOccupancy> sliceAcrossPages(
    FloatOccupancy entry,
    List<double> pageHeights,
  ) {
    final pages = <FloatOccupancy>[entry];
    var current = entry;
    for (var i = 0; i < pageHeights.length - 1; i++) {
      final (:next, :consumed) = current.take(pageHeights[i]);
      pages.add(next);
      current = next;
    }
    return pages;
  }

  /// 区间 [top, bottom) 与矩形相交判定（贴边不相交）。
  static bool _spans(Rect rect, double top, double bottom) =>
      rect.top < bottom && rect.bottom > top;

  /// 区间内左浮动的最大右边缘（即左侧被占宽度）。
  double occupiedLeftAt(double top, double bottom) {
    var width = 0.0;
    for (final item in _items) {
      if (item.side == FloatSide.left &&
          _spans(item.rect, top, bottom) &&
          item.rect.right > width) {
        width = item.rect.right;
      }
    }
    return width;
  }

  /// 区间内右浮动的最小左边缘到容器右缘的距离（即右侧被占宽度）。
  double occupiedRightAt(double top, double bottom, double containerWidth) {
    var width = 0.0;
    for (final item in _items) {
      if (item.side == FloatSide.right &&
          _spans(item.rect, top, bottom) &&
          containerWidth - item.rect.left > width) {
        width = containerWidth - item.rect.left;
      }
    }
    return width;
  }

  /// 区间内可用于内容的宽度约束。
  double contentWidthAt(
    double top,
    double bottom,
    double containerWidth,
  ) {
    final width = containerWidth -
        occupiedLeftAt(top, bottom) -
        occupiedRightAt(top, bottom, containerWidth);
    return width > 0 ? width : 0;
  }

  /// 从 [y] 起向下、[side] 侧还有多高被浮动占据（clear 语义与跨页
  /// 重登记用）：返回该侧所有触及 y 以下的浮动的最大底边 - y（负值
  /// 归零）。
  double clearanceBelow(double y, FloatSide side) {
    var bottom = y;
    for (final item in _items) {
      if (item.side == side && item.rect.bottom > bottom) {
        bottom = item.rect.bottom;
      }
    }
    final value = bottom - y;
    return value > 0 ? value : 0;
  }

  /// 分页切分（P3-13 takePlaceholders 的模型侧）：本页消耗
  /// [consumedHeight] 后，返回 (下一页续用的占用, 本页已用尽的占用)。
  ///
  /// 跨页的浮动被「切开」：剩余部分在 [next] 里按同 x/宽度、高度裁剪
  /// 后续用（与文本按行切分同构，§48.1）。
  ({FloatOccupancy next, List<BoxOccupied> consumed}) take(
    double consumedHeight,
  ) {
    final next = FloatOccupancy();
    final consumed = <BoxOccupied>[];
    for (final item in _items) {
      final remainingTop = item.rect.top + consumedHeight;
      if (remainingTop >= item.rect.bottom) {
        consumed.add(item); // 本页用尽。
        continue;
      }
      next._items.add(
        BoxOccupied(
          rect: Rect.fromLTRB(
            item.rect.left,
            0,
            item.rect.right,
            item.rect.bottom - remainingTop,
          ),
          baseline: 0,
          side: item.side,
        ),
      );
    }
    return (next: next, consumed: consumed);
  }
}
