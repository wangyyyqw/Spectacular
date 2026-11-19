import '../annotations/annotation.dart';
import 'style_values.dart';

class ReaderDecorationHighlight {
  const ReaderDecorationHighlight({
    this.style = ReaderAnnotationStyle.background,
    this.color = defaultHighlightColor,
    this.opacity,
    this.strokeWidth = 1.8,
    this.joinLines = false,
  });

  final ReaderAnnotationStyle style;
  final int color;
  final double? opacity;
  final double strokeWidth;
  final bool joinLines;

  double get effectiveOpacity => opacity ?? style.defaultOpacity;

  Map<String, Object?> toJson() => {
    'style': style.name,
    'color': color,
    if (opacity != null) 'opacity': opacity,
    'strokeWidth': strokeWidth,
    'joinLines': joinLines,
  };

  ReaderDecorationHighlight withValues(Map<String, Object?> values) =>
      fromJson({...toJson(), ...values})!;

  static ReaderDecorationHighlight? fromJson(Object? raw) {
    final json = styleObject(raw);
    final style = ReaderAnnotationStyle.values
        .where((item) => item.name == json['style'])
        .firstOrNull;
    if (style == null) return null;
    return ReaderDecorationHighlight(
      style: style,
      color: styleColor(json['color']) ?? defaultHighlightColor,
      opacity: json['opacity'] == null
          ? null
          : styleNumber(
              json['opacity'],
              fallback: style.defaultOpacity,
              min: 0,
              max: 1,
            ),
      strokeWidth: styleNumber(
        json['strokeWidth'],
        fallback: 1.8,
        min: 0.5,
        max: 6,
      ),
      joinLines: json['joinLines'] == true,
    );
  }
}
