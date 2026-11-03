/// 阅读模式；稳定字符串用于持久化，顺序与设置面板一致。
enum PageTurnMode {
  /// 底页固定，活动纸滑出或展开。
  cover('cover', '覆盖'),

  /// 覆盖时底页轻微缩放，形成叠放效果。
  coverStack('coverStack', '堆叠覆盖'),

  /// 二次贝塞尔轮廓与纸背反射。
  simulationBessel('simulationBessel', '贝塞尔仿真'),

  /// 按元素流纵向连续阅读。
  scroll('scroll', '连续滚动'),

  /// 当前页与目标页同步水平移动。
  slideHorizontal('slideHorizontal', '水平滑动'),

  /// 直接切换，供墨水屏和系统减少动画使用。
  none('none', '无动画');

  const PageTurnMode(this.id, this.label);

  /// 存储标识。
  final String id;

  /// 设置面板名称。
  final String label;

  /// 兼容旧设置和损坏值。
  static PageTurnMode fromId(String? id) =>
      values.firstWhere((mode) => mode.id == id, orElse: () => cover);
}
