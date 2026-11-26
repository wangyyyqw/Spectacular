/// 全局书签外观与下拉开关；尺寸为逻辑像素，不参与正文排版。
class ReaderBookmarkStyle {
  const ReaderBookmarkStyle({
    this.width = 24,
    this.length = 60,
    this.rightInset = 37,
    this.imageId,
    this.pullEnabled = true,
    this.color,
  });

  final double width;
  final double length;
  final double rightInset;
  final String? imageId;
  final bool pullEnabled;
  final int? color;

  static const minWidth = 12.0;
  static const maxWidth = 96.0;
  static const minLength = 24.0;
  static const maxLength = 200.0;
  static const minRightInset = 0.0;
  static const maxRightInset = 160.0;

  ReaderBookmarkStyle copyWith({
    double? width,
    double? length,
    double? rightInset,
    bool? pullEnabled,
    int? color,
  }) => ReaderBookmarkStyle(
    width: width ?? this.width,
    length: length ?? this.length,
    rightInset: rightInset ?? this.rightInset,
    imageId: imageId,
    pullEnabled: pullEnabled ?? this.pullEnabled,
    color: color ?? this.color,
  );

  ReaderBookmarkStyle withImage(String? id) => ReaderBookmarkStyle(
    width: width,
    length: length,
    rightInset: rightInset,
    imageId: id,
    pullEnabled: pullEnabled,
    color: color,
  );

  ReaderBookmarkStyle withColor(int? value) => ReaderBookmarkStyle(
    width: width,
    length: length,
    rightInset: rightInset,
    imageId: imageId,
    pullEnabled: pullEnabled,
    color: value,
  );

  Map<String, Object?> toJson() => {
    'width': width,
    'length': length,
    'rightInset': rightInset,
    'imageId': imageId,
    'pullEnabled': pullEnabled,
    'color': color,
  };

  factory ReaderBookmarkStyle.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const ReaderBookmarkStyle();
    double dimension(String key, double fallback, double min, double max) {
      final value = json[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    final image = json['imageId'];
    final pullEnabled = json['pullEnabled'];
    final color = json['color'];
    return ReaderBookmarkStyle(
      width: dimension('width', 24, minWidth, maxWidth),
      length: dimension('length', 60, minLength, maxLength),
      rightInset: dimension('rightInset', 37, minRightInset, maxRightInset),
      imageId: image is String && image.startsWith('image:') ? image : null,
      pullEnabled: pullEnabled is bool ? pullEnabled : true,
      color: color is int && color >= 0 && color <= 0xffffffff ? color : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderBookmarkStyle &&
      other.width == width &&
      other.length == length &&
      other.rightInset == rightInset &&
      other.imageId == imageId &&
      other.pullEnabled == pullEnabled &&
      other.color == color;

  @override
  int get hashCode =>
      Object.hash(width, length, rightInset, imageId, pullEnabled, color);
}
