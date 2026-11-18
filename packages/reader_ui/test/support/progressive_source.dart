import 'dart:async';

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';

String progressiveCfi(int spine, int page) =>
    'epubcfi(/6/${(spine + 1) * 2}!/4/${(page + 1) * 2}/1:0)';

class ProgressiveTestHandle implements ProgressiveChapterLoadHandle {
  ProgressiveTestHandle(this.priority) {
    result.ignore();
    firstPages.ignore();
  }

  final _first = Completer<List<PageContent>>();
  final _result = Completer<List<PageContent>>();
  final _updates = StreamController<List<PageContent>>.broadcast(sync: true);
  bool cancelled = false;
  bool _complete = false;
  @override
  ChapterLayoutPriority priority;
  @override
  List<PageContent> availablePages = const [];
  @override
  int? pageCount;
  @override
  Future<List<PageContent>> get firstPages => _first.future;
  @override
  Future<List<PageContent>> get result => _result.future;
  @override
  Stream<List<PageContent>> get updates => _updates.stream;
  @override
  bool get isComplete => _complete;
  @override
  void setPriority(ChapterLayoutPriority next) => priority = next;

  void publish(List<PageContent> pages) {
    if (_result.isCompleted) return;
    availablePages = List.unmodifiable(pages);
    if (!_first.isCompleted) {
      priority = ChapterLayoutPriority.background;
      _first.complete(availablePages);
    }
    _updates.add(availablePages);
  }

  void publishPageCount(int count) {
    if (_result.isCompleted) return;
    pageCount = count;
    if (_first.isCompleted) _updates.add(availablePages);
  }

  void complete(List<PageContent> pages) {
    if (_result.isCompleted) return;
    _complete = true;
    pageCount = pages.length;
    availablePages = List.unmodifiable(pages);
    if (!_first.isCompleted) _first.complete(availablePages);
    _result.complete(availablePages);
    _updates.add(availablePages);
    unawaited(_updates.close());
  }

  @override
  void cancel() {
    if (_result.isCompleted) return;
    cancelled = true;
    if (!_first.isCompleted) _first.completeError(const ChapterLoadCancelled());
    _result.completeError(const ChapterLoadCancelled());
    unawaited(_updates.close());
  }
}

/// 页发布和章完成由测试独立控制，暴露把临时尾页误当章尾的行为。
class ProgressiveTestSource
    implements ProgressiveChapterSource, BackgroundLayoutChapterSource {
  ProgressiveTestSource({
    List<int> counts = const [1, 6, 1],
    this.heldSpines = const {1},
    this.initialPages = 1,
  }) : chapters = [
         for (var spine = 0; spine < counts.length; spine++)
           [
             for (var page = 0; page < counts[spine]; page++)
               _page(spine, page),
           ],
       ];

  final Set<int> heldSpines;
  final int initialPages;
  final List<List<PageContent>> chapters;
  final handles = <int, ProgressiveTestHandle>{};
  final requests = <int>[];
  bool backgroundPaused = false;

  @override
  void setBackgroundLayoutPaused(bool paused) => backgroundPaused = paused;

  static PageContent _page(int spine, int index) {
    final style = ComputedStyle(const {
      'font-size': '16px',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: '第 $spine 章第 $index 页正文。',
      style: style,
      maxWidth: 280,
    );
    return PageContent(
      spineIndex: spine,
      pageIndex: index,
      slices: [
        PageBlockSlice(
          block: PageBlock(
            layout: layout,
            style: style,
            startCfi: progressiveCfi(spine, index),
          ),
          startLine: 0,
          endLine: layout.lineCount,
          height: layout.height,
        ),
      ],
      usedHeight: layout.height,
      pageHeight: 200,
      topPadding: 0,
    );
  }

  @override
  int get chapterCount => chapters.length;

  @override
  ProgressiveTestHandle scheduleProgressiveChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    bool retainResult = true,
  }) {
    final existing = handles[spineIndex];
    if (existing != null && !existing.cancelled) return existing;
    requests.add(spineIndex);
    final handle = handles[spineIndex] = ProgressiveTestHandle(priority);
    scheduleMicrotask(() {
      if (heldSpines.contains(spineIndex)) {
        handle.publish(chapters[spineIndex].take(initialPages).toList());
      } else {
        handle.complete(chapters[spineIndex]);
      }
    });
    return handle;
  }

  void publish(int spine, int count) =>
      handles[spine]!.publish(chapters[spine].take(count).toList());
  void publishPageCount(int spine) =>
      handles[spine]!.publishPageCount(chapters[spine].length);
  void complete(int spine) => handles[spine]!.complete(chapters[spine]);

  @override
  ChapterLoadHandle scheduleChapter(
    int spineIndex, {
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    bool retainResult = true,
  }) => scheduleProgressiveChapter(
    spineIndex,
    priority: priority,
    retainResult: retainResult,
  );

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) =>
      scheduleChapter(spineIndex).result;

  @override
  void cancelPendingLayouts() {
    for (final handle in handles.values) {
      handle.cancel();
    }
  }
}
