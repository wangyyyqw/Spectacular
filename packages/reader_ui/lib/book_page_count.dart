/// 全书实际计页任务的状态；阅读百分比独立计算。
enum BookPageCountStatus { idle, running, paused, complete }

/// 一套完整排版配置下的累计页数快照。
class BookPageCountState {
  BookPageCountState({
    required this.layoutKey,
    required this.completedPages,
    required this.completedChapters,
    required this.totalChapters,
    required this.status,
    Iterable<int> failedSpines = const <int>[],
  }) : failedSpines = Set<int>.unmodifiable(failedSpines);

  final String layoutKey;
  final int completedPages;
  final int completedChapters;
  final int totalChapters;
  final BookPageCountStatus status;
  final Set<int> failedSpines;

  bool get isComplete =>
      status == BookPageCountStatus.complete &&
      completedChapters == totalChapters &&
      failedSpines.isEmpty;

  String get label =>
      isComplete ? '全书 $completedPages 页' : '已排 $completedPages 页';

  @override
  bool operator ==(Object other) =>
      other is BookPageCountState &&
      other.layoutKey == layoutKey &&
      other.completedPages == completedPages &&
      other.completedChapters == completedChapters &&
      other.totalChapters == totalChapters &&
      other.status == status &&
      other.failedSpines.length == failedSpines.length &&
      other.failedSpines.containsAll(failedSpines);

  @override
  int get hashCode => Object.hash(
    layoutKey,
    completedPages,
    completedChapters,
    totalChapters,
    status,
    Object.hashAllUnordered(failedSpines),
  );
}
