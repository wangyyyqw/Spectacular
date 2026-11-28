import 'dart:math' as math;

import 'package:flutter/material.dart';

typedef CoverTitleLine = ({String text, Rect bounds});

/// OCR 命中的书名区域，以原图宽高的比例保存。
class CoverTitleFocus {
  const CoverTitleFocus({required this.imageSize, required this.titleBounds});

  final Size imageSize;
  final Rect titleBounds;

  Map<String, Object> toJson() => {
    'width': imageSize.width,
    'height': imageSize.height,
    'left': titleBounds.left,
    'top': titleBounds.top,
    'right': titleBounds.right,
    'bottom': titleBounds.bottom,
  };

  static CoverTitleFocus? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final values = [
      value['width'],
      value['height'],
      value['left'],
      value['top'],
      value['right'],
      value['bottom'],
    ];
    if (values.any((item) => item is! num || !item.isFinite)) return null;
    final imageSize = Size(
      (values[0] as num).toDouble(),
      (values[1] as num).toDouble(),
    );
    final bounds = Rect.fromLTRB(
      (values[2] as num).toDouble(),
      (values[3] as num).toDouble(),
      (values[4] as num).toDouble(),
      (values[5] as num).toDouble(),
    );
    if (!imageSize.width.isFinite ||
        !imageSize.height.isFinite ||
        imageSize.isEmpty ||
        bounds.isEmpty ||
        bounds.left < 0 ||
        bounds.top < 0 ||
        bounds.right > 1 ||
        bounds.bottom > 1) {
      return null;
    }
    return CoverTitleFocus(imageSize: imageSize, titleBounds: bounds);
  }
}

String normalizeCoverTitle(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]', unicode: true),
  '',
);

/// 查找完整书名或至少半数书名字符组成的相邻识别行。
Rect? findCoverTitleBounds(String title, Iterable<CoverTitleLine> source) {
  final normalizedTitle = normalizeCoverTitle(title);
  if (normalizedTitle.isEmpty) return null;
  final lines = source.where((line) => line.text.trim().isNotEmpty).toList()
    ..sort((a, b) {
      final vertical = a.bounds.top.compareTo(b.bounds.top);
      return vertical == 0 ? a.bounds.left.compareTo(b.bounds.left) : vertical;
    });

  Rect? bestBounds;
  var bestScore = 0.0;
  var bestArea = double.infinity;
  for (var start = 0; start < lines.length; start++) {
    var candidate = '';
    Rect? bounds;
    final endLimit = math.min(lines.length, start + 4);
    for (var end = start; end < endLimit; end++) {
      final line = lines[end];
      candidate += normalizeCoverTitle(line.text);
      bounds = bounds == null
          ? line.bounds
          : bounds.expandToInclude(line.bounds);
      if (candidate.isEmpty) continue;

      var score = 0.0;
      if (candidate.contains(normalizedTitle)) {
        score = normalizedTitle.length / candidate.length;
      } else if (normalizedTitle.length >= 3 &&
          normalizedTitle.contains(candidate) &&
          candidate.length >=
              math.max(3, (normalizedTitle.length * .5).ceil())) {
        score = candidate.length / normalizedTitle.length;
      }
      final area = bounds.width * bounds.height;
      if (score > 0 &&
          (score > bestScore || (score == bestScore && area < bestArea))) {
        bestScore = score;
        bestArea = area;
        bestBounds = bounds;
      }
    }
  }
  return bestBounds;
}

/// 按原图比例布局封面，在不露底的范围内优先保留书名。
({Size imageSize, Offset translation}) coverTitleFocusPlacement({
  required CoverTitleFocus focus,
  required Size coverSize,
  required Path clipPath,
  required Offset regionCenter,
  required double rotation,
}) {
  if (focus.imageSize.isEmpty || coverSize.isEmpty) {
    return (imageSize: coverSize, translation: Offset.zero);
  }
  final inverse = Matrix4.rotationZ(-rotation)
    ..translateByDouble(-regionCenter.dx, -regionCenter.dy, 0, 1);
  final visible = clipPath.transform(inverse.storage);
  final bounds = visible.getBounds();
  var scale = math.max(
    coverSize.width / focus.imageSize.width,
    coverSize.height / focus.imageSize.height,
  );
  if (!bounds.isEmpty) {
    scale = math.max(
      scale,
      math.max(
        bounds.width / focus.imageSize.width,
        bounds.height / focus.imageSize.height,
      ),
    );
  }
  final baseSize = focus.imageSize * scale;
  var best = (imageSize: baseSize, translation: Offset.zero);
  if (bounds.isEmpty) return best;
  var bestSamples = -1;
  var bestZoom = 1.0;
  var bestDistance = double.infinity;
  // 保留原大小；放大只在书名可见比例改善时使用。有限候选避免逐像素搜索，
  // 每张最多 3 × 7 × 7 × 64 次 contains，不把 OCR 后续变成持续帧计算。
  for (final zoom in const [1.0, 1.175, 1.35]) {
    final size = baseSize * zoom;
    final title = Rect.fromLTRB(
      (focus.titleBounds.left - .5) * size.width,
      (focus.titleBounds.top - .5) * size.height,
      (focus.titleBounds.right - .5) * size.width,
      (focus.titleBounds.bottom - .5) * size.height,
    );
    final xs = _focusAxisCandidates(
      size.width,
      title.left,
      title.right,
      bounds.left,
      bounds.right,
    );
    final ys = _focusAxisCandidates(
      size.height,
      title.top,
      title.bottom,
      bounds.top,
      bounds.bottom,
    );
    for (final x in xs) {
      for (final y in ys) {
        final translation = Offset(x, y);
        final moved = title.shift(translation);
        final samples = _visibleTitleSamples(visible, moved);
        final distance = (moved.center - bounds.center).distanceSquared;
        if (samples > bestSamples ||
            (samples == bestSamples &&
                zoom == bestZoom &&
                distance < bestDistance)) {
          best = (imageSize: size, translation: translation);
          bestSamples = samples;
          bestZoom = zoom;
          bestDistance = distance;
        }
      }
    }
  }
  return best;
}

Iterable<double> _focusAxisCandidates(
  double extent,
  double titleStart,
  double titleEnd,
  double visibleStart,
  double visibleEnd,
) {
  var min = visibleEnd - extent / 2;
  var max = visibleStart + extent / 2;
  // 把整个可见区域留在原图内，并保留最多四分之一像素的旋转采样余量。
  final inset = math.min(.25, (max - min) / 2);
  min += inset;
  max -= inset;
  return {
    min,
    max,
    for (final value in [
      0.0,
      (min + max) / 2,
      (visibleStart + visibleEnd - titleStart - titleEnd) / 2,
      visibleStart - titleStart,
      visibleEnd - titleEnd,
    ])
      value.clamp(min, max).toDouble(),
  };
}

int _visibleTitleSamples(Path visible, Rect title) {
  var hits = 0;
  // 等面积格点估计书名可见比例；安全边界由上方精确的平移区间保证。
  for (var row = 0; row < 8; row++) {
    for (var column = 0; column < 8; column++) {
      if (visible.contains(
        Offset(
          title.left + (column + .5) * title.width / 8,
          title.top + (row + .5) * title.height / 8,
        ),
      )) {
        hits++;
      }
    }
  }
  return hits;
}
