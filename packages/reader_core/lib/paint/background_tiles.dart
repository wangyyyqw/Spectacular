import 'dart:math' as math;
import 'dart:ui';

import '../css/background_values.dart';

typedef _Interval = ({double start, double end});
typedef _TileAxis = ({double start, double step, int count});

// 坐标由 double 计算；转为循环计数前，仅接受其能精确表示的整数范围。
const _maximumExactCount = 9007199254740991;

/// 图片和渐变共用的瓦片几何；定位区与最终绘制区可分别传入。
///
/// [intrinsicSize] 缺省表示渐变没有固有尺寸或比例。返回惰性序列，避免
/// 普通重复背景额外分配完整矩形列表；计数循环不会因浮点步长停滞。
Iterable<Rect> backgroundTileRects(
  Rect bounds,
  CssBackgroundLayer layer, {
  Rect? paintingBounds,
  Size? intrinsicSize,
}) sync* {
  final painting = paintingBounds ?? bounds;
  if (!_validRect(bounds) || !_validRect(painting)) return;
  final original = _initialTileSize(bounds.size, layer.size, intrinsicSize);
  if (!_validSize(original)) return;
  final tile = _roundTileSize(original, bounds.size, layer, intrinsicSize);
  if (!_validSize(tile)) return;
  final axes = _tileAxes(bounds, painting, layer, tile);
  if (axes == null) return;
  final (x, y) = axes;
  if (x.count == 0 || y.count == 0) return;
  for (final top in _axisCoordinates(y)) {
    for (final left in _axisCoordinates(x)) {
      final rect = Rect.fromLTWH(left, top, tile.width, tile.height);
      if (!_validRect(rect)) return;
      yield rect;
    }
  }
}

Iterable<double> _axisCoordinates(_TileAxis axis) sync* {
  var previous = double.negativeInfinity;
  for (var index = 0; index < axis.count; index++) {
    final value = axis.start + index * axis.step;
    if (!value.isFinite || value <= previous) return;
    previous = value;
    yield value;
  }
}

bool _validSize(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;

bool _validRect(Rect rect) => rect.isFinite && _validSize(rect.size);

Size _initialTileSize(Size area, CssBackgroundSize size, Size? intrinsic) {
  final natural = intrinsic ?? area;
  if (!_validSize(natural)) return Size.zero;
  switch (size.mode) {
    case CssBackgroundSizeMode.auto:
      return natural;
    case CssBackgroundSizeMode.cover:
    case CssBackgroundSizeMode.contain:
      final x = area.width / natural.width;
      final y = area.height / natural.height;
      final scale = size.mode == CssBackgroundSizeMode.cover
          ? math.max(x, y)
          : math.min(x, y);
      return natural * scale;
    case CssBackgroundSizeMode.explicit:
      final width = size.width?.resolve(area.width);
      final height = size.height?.resolve(area.height);
      if (width != null && height != null) return Size(width, height);
      if (width != null) {
        return Size(
          width,
          intrinsic == null
              ? area.height
              : width * natural.height / natural.width,
        );
      }
      if (height != null) {
        return Size(
          intrinsic == null
              ? area.width
              : height * natural.width / natural.height,
          height,
        );
      }
      return natural;
  }
}

Size _roundTileSize(
  Size tile,
  Size area,
  CssBackgroundLayer layer,
  Size? intrinsic,
) {
  final roundX = layer.repeat.x == CssBackgroundRepeatMode.round;
  final roundY = layer.repeat.y == CssBackgroundRepeatMode.round;
  var width = roundX ? _roundedLength(tile.width, area.width) : tile.width;
  var height = roundY ? _roundedLength(tile.height, area.height) : tile.height;
  if (intrinsic != null) {
    if (roundX && !roundY && layer.size.autoHeight) {
      height *= width / tile.width;
    }
    if (roundY && !roundX && layer.size.autoWidth) {
      width *= height / tile.height;
    }
  }
  return Size(width, height);
}

double _roundedLength(double length, double available) {
  final ratio = available / length;
  if (!ratio.isFinite) return 0;
  return available / math.max(1, ratio.roundToDouble());
}

(_TileAxis, _TileAxis)? _tileAxes(
  Rect bounds,
  Rect painting,
  CssBackgroundLayer layer,
  Size tile,
) {
  final x = _axisTiles(
    mode: layer.repeat.x,
    length: tile.width,
    offset: layer.position.x.resolve(bounds.width - tile.width) ?? 0,
    origin: (start: bounds.left, end: bounds.right),
    painting: (start: painting.left, end: painting.right),
  );
  final y = _axisTiles(
    mode: layer.repeat.y,
    length: tile.height,
    offset: layer.position.y.resolve(bounds.height - tile.height) ?? 0,
    origin: (start: bounds.top, end: bounds.bottom),
    painting: (start: painting.top, end: painting.bottom),
  );
  return x == null || y == null ? null : (x, y);
}

_TileAxis? _axisTiles({
  required CssBackgroundRepeatMode mode,
  required double length,
  required double offset,
  required _Interval origin,
  required _Interval painting,
}) {
  if (!offset.isFinite) return null;
  final available = origin.end - origin.start;
  final fitting = available / length;
  final single =
      mode == CssBackgroundRepeatMode.noRepeat ||
      (mode == CssBackgroundRepeatMode.space && fitting < 2);
  if (single) {
    final start = origin.start + offset;
    final visible = start < painting.end && start + length > painting.start;
    return (start: start, step: 0, count: visible ? 1 : 0);
  }
  if (!fitting.isFinite) return null;
  final step = mode == CssBackgroundRepeatMode.space
      ? (available - length) / (fitting.floorToDouble() - 1)
      : length;
  // repeat 延续已有相位口径；space 贴边，round 在缩放后应用定位。
  final anchor = switch (mode) {
    CssBackgroundRepeatMode.repeat => origin.start - offset % length,
    CssBackgroundRepeatMode.space => origin.start,
    _ => origin.start + offset % length,
  };
  return _repeatedAxis(anchor, step, length, painting);
}

_TileAxis? _repeatedAxis(
  double anchor,
  double step,
  double length,
  _Interval painting,
) {
  if (!anchor.isFinite || !step.isFinite || step <= 0) return null;
  final shift = (painting.start - anchor) / step;
  if (!shift.isFinite) return null;
  var start = anchor + shift.floorToDouble() * step;
  if (!start.isFinite) return null;
  if (start + length <= painting.start) start += step;
  final count = (painting.end - start) / step;
  if (!count.isFinite || count > _maximumExactCount) return null;
  return (start: start, step: step, count: math.max(0, count.ceil()));
}
