/// 全局书签外观；尺寸为逻辑像素，不参与正文排版。
class ReaderBookmarkStyle {
  const ReaderBookmarkStyle({
    this.width = 24,
    this.length = 60,
    this.rightInset = 37,
    this.imageId,
  });

  final double width;
  final double length;
  final double rightInset;
  final String? imageId;

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
  }) => ReaderBookmarkStyle(
    width: width ?? this.width,
    length: length ?? this.length,
    rightInset: rightInset ?? this.rightInset,
    imageId: imageId,
  );

  ReaderBookmarkStyle withImage(String? id) => ReaderBookmarkStyle(
    width: width,
    length: length,
    rightInset: rightInset,
    imageId: id,
  );

  Map<String, Object?> toJson() => {
    'width': width,
    'length': length,
    'rightInset': rightInset,
    'imageId': imageId,
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
    return ReaderBookmarkStyle(
      width: dimension('width', 24, minWidth, maxWidth),
      length: dimension('length', 60, minLength, maxLength),
      rightInset: dimension('rightInset', 37, minRightInset, maxRightInset),
      imageId: image is String && image.startsWith('image:') ? image : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderBookmarkStyle &&
      other.width == width &&
      other.length == length &&
      other.rightInset == rightInset &&
      other.imageId == imageId;

  @override
  int get hashCode => Object.hash(width, length, rightInset, imageId);
}
