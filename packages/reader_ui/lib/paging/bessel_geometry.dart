import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// 页角模型的几何结果，按 690 报告第 2～4 节重新实现。
class BesselGeometry {
  const BesselGeometry._({
    required this.a,
    required this.f,
    required this.e,
    required this.h,
    required this.c,
    required this.j,
    required this.b,
    required this.k,
    required this.d,
    required this.i,
    required this.top,
    required this.size,
    this.horizontal = false,
  });

  final Offset a, f, e, h, c, j, b, k, d, i;
  final bool top;
  final Size size;

  /// 中心区抓取侧边，其余位置抓取上下页角。
  final bool horizontal;

  /// 在右页缘规范坐标中求解；退化输入返回空，不伪造控制点。
  static BesselGeometry? resolve(
    Size size,
    Offset touch, {
    bool top = false,
    bool horizontal = false,
  }) {
    if (size.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !touch.dx.isFinite ||
        !touch.dy.isFinite) {
      return null;
    }
    if (horizontal) return _edge(size, touch, top);
    final f = Offset(size.width, top ? 0 : size.height);
    final a = Offset(
      (touch.dx - f.dx).abs() < 0.1 ? f.dx - 0.1 : touch.dx,
      (touch.dy - f.dy).abs() < 0.1 ? f.dy + (top ? 0.1 : -0.1) : touch.dy,
    );
    // 控制点可以落在纸面外，由视口裁剪；不能为限制折痕而挪动抓取点。
    return _solve(size, a, f, top);
  }

  static BesselGeometry _edge(Size size, Offset touch, bool top) {
    final fold = (size.width + touch.dx) / 2;
    final bow = math.max(0.0, math.min((size.width - touch.dx) / 8, fold / 8));
    return BesselGeometry._(
      a: touch,
      f: Offset(size.width, touch.dy),
      e: Offset(touch.dx, 0),
      h: Offset(touch.dx, size.height),
      c: Offset(fold, 0),
      j: Offset(fold, size.height),
      b: Offset(touch.dx + bow, 0),
      k: Offset(touch.dx + bow, size.height),
      d: Offset(fold + bow, 0),
      i: Offset(fold + bow, size.height),
      top: top,
      size: size,
      horizontal: true,
    );
  }

  static BesselGeometry? _solve(Size size, Offset a, Offset f, bool top) {
    final g = (a + f) / 2;
    final dx = f.dx - g.dx;
    final dy = f.dy - g.dy;
    if (dx.abs() < 1e-8 || dy.abs() < 1e-8) return null;
    final e = Offset(g.dx - dy * dy / dx, f.dy);
    final h = Offset(f.dx, g.dy - dx * dx / dy);
    final c = Offset(e.dx - (f.dx - e.dx) / 2, f.dy);
    final j = Offset(f.dx, h.dy - (f.dy - h.dy) / 2);
    final b = _intersection(a, e, c, j);
    final k = _intersection(a, h, c, j);
    if (b == null || k == null) return null;
    return BesselGeometry._(
      a: a,
      f: f,
      e: e,
      h: h,
      c: c,
      j: j,
      b: b,
      k: k,
      d: (c + e * 2 + b) / 4,
      i: (j + h * 2 + k) / 4,
      top: top,
      size: size,
    );
  }

  static Offset? _intersection(Offset p, Offset q, Offset r, Offset s) {
    final u = q - p;
    final v = s - r;
    final divisor = u.dx * v.dy - u.dy * v.dx;
    if (divisor.abs() < 1e-8) return null;
    final w = r - p;
    final result = p + u * ((w.dx * v.dy - w.dy * v.dx) / divisor);
    return result.dx.isFinite && result.dy.isFinite ? result : null;
  }

  /// 活动纸正面：两段二次曲线连接抓取点。
  Path frontPath() {
    if (horizontal) {
      return Path()
        ..moveTo(0, 0)
        ..lineTo(b.dx, b.dy)
        ..quadraticBezierTo(e.dx, e.dy, a.dx, a.dy)
        ..quadraticBezierTo(h.dx, h.dy, k.dx, k.dy)
        ..lineTo(0, size.height)
        ..close();
    }
    final path = Path()..moveTo(0, top ? size.height : 0);
    path.lineTo(0, top ? 0 : f.dy);
    path.lineTo(c.dx, c.dy);
    path.quadraticBezierTo(e.dx, e.dy, b.dx, b.dy);
    path.lineTo(a.dx, a.dy);
    path.lineTo(k.dx, k.dy);
    path.quadraticBezierTo(h.dx, h.dy, j.dx, j.dy);
    path.lineTo(f.dx, top ? size.height : 0);
    return path..close();
  }

  /// 候选纸背减去正面；无效路径由绘制层降级。
  Path backPath(Path front) {
    if (horizontal) {
      return Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..quadraticBezierTo(d.dx, d.dy, d.dx, a.dy)
        ..quadraticBezierTo(i.dx, i.dy, j.dx, j.dy)
        ..lineTo(k.dx, k.dy)
        ..quadraticBezierTo(h.dx, h.dy, a.dx, a.dy)
        ..quadraticBezierTo(e.dx, e.dy, b.dx, b.dy)
        ..close();
    }
    return Path.combine(
      PathOperation.difference,
      polygon([a, b, d, i, k]),
      front,
    );
  }

  /// 关于抓取点和原页缘中垂线的反射，按 Canvas 的列主序存储。
  Float64List reflection() {
    final normal = horizontal ? const Offset(1, 0) : (f - a) / (f - a).distance;
    final midpoint = (f + a) / 2;
    final aa = 1 - 2 * normal.dx * normal.dx;
    final bb = -2 * normal.dx * normal.dy;
    final dd = 1 - 2 * normal.dy * normal.dy;
    return Float64List.fromList([
      aa,
      bb,
      0,
      0,
      bb,
      dd,
      0,
      0,
      0,
      0,
      1,
      0,
      midpoint.dx - aa * midpoint.dx - bb * midpoint.dy,
      midpoint.dy - bb * midpoint.dx - dd * midpoint.dy,
      0,
      1,
    ]);
  }

  /// 阴影共用的裁剪辅助点，保持原始常数 7.07。
  Offset get shadowPoint {
    final dy = top ? e.dy - a.dy : a.dy - e.dy;
    final angle = math.pi / 4 - math.atan2(dy, a.dx - e.dx);
    return Offset(
      a.dx + 7.07 * math.cos(angle),
      a.dy + (top ? 1 : -1) * 7.07 * math.sin(angle),
    );
  }

  static Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
}
