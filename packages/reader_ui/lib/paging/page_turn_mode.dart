/// 覆盖、滑动和一屏滚动的过渡时长；拖动收尾按剩余距离和速度缩短。
const Duration pageTurnAnimationDuration = Duration(milliseconds: 280);

/// 接续使用单一逐行接力时钟；拖动与点击都沿同一进度收尾。
const Duration continuationPageTurnDuration = Duration(milliseconds: 620);

/// 阅读模式；稳定字符串用于持久化，顺序与设置面板一致。
enum PageTurnMode {
  /// 底页固定，活动纸滑出或展开。
  cover('cover', '覆盖'),

  /// 覆盖时底页低速跟随，形成两页重叠的搓纸视差。
  coverStack('coverStack', '堆叠覆盖'),

  /// 二次贝塞尔轮廓与纸背反射。
  simulationBessel('simulationBessel', '贝塞尔仿真'),

  /// 固定 UV 的圆柱卷曲，带纸背与明暗。
  simulation3d('simulation3d', '3D（旧版）'),

  /// 与旧版共享圆柱模型和手势时钟，保留独立的阅读设置标识。
  simulation3dNext('simulation3dNext', '3D（新版）'),

  /// 按文本行或竖排列的空间位置错峰横移，旧内容先退出、新内容随后进入。
  continuation('continuation', '接续'),

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

  /// 两个 3D 入口使用相同的绘制、触摸与资源准备流程。
  bool get is3d => this == simulation3d || this == simulation3dNext;

  /// 兼容旧设置和损坏值。
  static PageTurnMode fromId(String? id) =>
      values.firstWhere((mode) => mode.id == id, orElse: () => cover);
}
