import 'dart:math' as math;
import 'dart:ui';

import 'style_values.dart';

class ReaderDecorationNineSlice {
  const ReaderDecorationNineSlice({
    this.slice = const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
    this.content = const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
    this.scale = 1,
  });

  final Rect slice;
  final Rect content;
  final double scale;

  double scaleFor(Rect text, Size image) {
    var factor = text.height / (content.height * image.height) * scale;
    final fixedWidth = math.max(0, content.width - slice.width) * image.width;
    final fixedHeight =
        math.max(0, content.height - slice.height) * image.height;
    if (fixedWidth > 0) {
      factor = math.min(factor, text.width / fixedWidth * 0.99);
    }
    if (fixedHeight > 0) {
      factor = math.min(factor, text.height / fixedHeight * 0.99);
    }
    return factor;
  }

  Rect imageRectFor(Rect text, Size image) {
    final factor = scaleFor(text, image);
    return Rect.fromLTRB(
      text.left - content.left * image.width * factor,
      text.top - content.top * image.height * factor,
      text.right + (1 - content.right) * image.width * factor,
      text.bottom + (1 - content.bottom) * image.height * factor,
    );
  }

  Rect centerFor(Size image) => Rect.fromLTRB(
    slice.left * image.width,
    slice.top * image.height,
    slice.right * image.width,
    slice.bottom * image.height,
  );

  ReaderDecorationNineSlice withContent(Rect rect) =>
      ReaderDecorationNineSlice(slice: rect, content: rect, scale: scale);

  Map<String, Object?> toJson() => {
    'slice': _rectJson(slice),
    'content': _rectJson(content),
    'scale': scale,
  };

  static Map<String, double> _rectJson(Rect rect) => {
    'left': rect.left,
    'top': rect.top,
    'right': rect.right,
    'bottom': rect.bottom,
  };

  static ReaderDecorationNineSlice? fromJson(Object? raw) {
    if (raw == null) return null;
    final json = styleObject(raw);
    final slice = _readRect(json['slice']);
    final content = _readRect(json['content']);
    if (slice == null || content == null) {
      return null;
    }
    return ReaderDecorationNineSlice(
      slice: slice,
      content: content,
      scale: styleNumber(json['scale'], fallback: 1, min: 0.25, max: 3),
    );
  }

  static Rect? _readRect(Object? raw) {
    final json = styleObject(raw);
    final edges = [
      for (final name in ['left', 'top', 'right', 'bottom']) json[name],
    ];
    if (edges.any(
      (edge) => edge is! num || !edge.isFinite || edge < 0 || edge > 1,
    )) {
      return null;
    }
    final rect = Rect.fromLTRB(
      (edges[0] as num).toDouble(),
      (edges[1] as num).toDouble(),
      (edges[2] as num).toDouble(),
      (edges[3] as num).toDouble(),
    );
    return rect.width > 0 && rect.height > 0 ? rect : null;
  }
}
