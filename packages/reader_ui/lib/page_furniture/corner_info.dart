/// 阅读页四角可显示的信息。
enum ReaderCornerContent {
  none('隐藏'),
  chapterTitle('章节名'),
  bookTitle('书名'),
  chapterPage('章内页码'),
  progress('全书进度'),
  clock('时间'),
  battery('电量'),
  clockAndBattery('时间与电量');

  const ReaderCornerContent(this.label);

  final String label;

  bool get needsClock => this == clock || this == clockAndBattery;
  bool get needsBattery => this == battery || this == clockAndBattery;
}

/// 四角位置，与屏幕上的预览按钮一一对应。
enum ReaderCornerSlot {
  topLeft('左上'),
  topRight('右上'),
  bottomLeft('左下'),
  bottomRight('右下');

  const ReaderCornerSlot(this.label);

  final String label;
}

/// 页眉和页脚的显示偏好；不与正文排版覆盖混用。
class ReaderCornerInfo {
  const ReaderCornerInfo({
    this.topLeft = ReaderCornerContent.chapterTitle,
    this.topRight = ReaderCornerContent.chapterPage,
    this.bottomLeft = ReaderCornerContent.clockAndBattery,
    this.bottomRight = ReaderCornerContent.progress,
  });

  static const defaults = ReaderCornerInfo();

  final ReaderCornerContent topLeft;
  final ReaderCornerContent topRight;
  final ReaderCornerContent bottomLeft;
  final ReaderCornerContent bottomRight;

  bool get hasHeader =>
      topLeft != ReaderCornerContent.none ||
      topRight != ReaderCornerContent.none;
  bool get hasFooter =>
      bottomLeft != ReaderCornerContent.none ||
      bottomRight != ReaderCornerContent.none;

  ReaderCornerContent contentAt(ReaderCornerSlot slot) => switch (slot) {
    ReaderCornerSlot.topLeft => topLeft,
    ReaderCornerSlot.topRight => topRight,
    ReaderCornerSlot.bottomLeft => bottomLeft,
    ReaderCornerSlot.bottomRight => bottomRight,
  };

  ReaderCornerInfo withContent(
    ReaderCornerSlot slot,
    ReaderCornerContent value,
  ) => ReaderCornerInfo(
    topLeft: slot == ReaderCornerSlot.topLeft ? value : topLeft,
    topRight: slot == ReaderCornerSlot.topRight ? value : topRight,
    bottomLeft: slot == ReaderCornerSlot.bottomLeft ? value : bottomLeft,
    bottomRight: slot == ReaderCornerSlot.bottomRight ? value : bottomRight,
  );

  Map<String, String> toJson() => {
    for (final slot in ReaderCornerSlot.values) slot.name: contentAt(slot).name,
  };

  /// 非法值逐项回到默认，避免损坏设置导致整页不可见。
  static ReaderCornerInfo fromJson(Object? json) {
    if (json is! Map) return defaults;
    var result = defaults;
    for (final slot in ReaderCornerSlot.values) {
      final value = ReaderCornerContent.values
          .where((item) => item.name == json[slot.name])
          .firstOrNull;
      if (value != null) result = result.withContent(slot, value);
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderCornerInfo &&
      topLeft == other.topLeft &&
      topRight == other.topRight &&
      bottomLeft == other.bottomLeft &&
      bottomRight == other.bottomRight;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomLeft, bottomRight);
}
