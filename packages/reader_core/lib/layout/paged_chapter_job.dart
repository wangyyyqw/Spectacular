import 'dart:async';

import '../src/api/models.dart' show CancelToken;
import 'paginator.dart';

/// 可取消、按页增量产出的章节分页任务。
class PagedChapterJob {
  /// 创建并启动任务。
  PagedChapterJob({
    required this.blocks,
    required this.pageHeight,
    this.spineIndex = 0,
    this.topPadding = 0,
    this.tolerance = 2,
  }) : _controller = StreamController<PageContent>() {
    _controller.onCancel = () => _token.cancel();
    _done = _run();
  }

  /// 待分页块。
  final List<PageBlock> blocks;

  /// 页高。
  final double pageHeight;

  /// 章节序号。
  final int spineIndex;

  /// 首页顶部留白。
  final double topPadding;

  /// 浮点容差。
  final double tolerance;

  final CancelToken _token = CancelToken();
  final StreamController<PageContent> _controller;
  late final Future<void> _done;
  double _progress = 0;

  /// 取消令牌。
  CancelToken get token => _token;

  /// 增量页流。
  Stream<PageContent> get pages => _controller.stream;

  /// 完成信号（取消也会结束）。
  Future<void> get done => _done;

  /// 已排字节/总高度比例，0..1。
  double get progress => _progress;

  /// 请求取消；已产出的页保留。
  void cancel() {
    _token.cancel();
  }

  Future<void> _run() async {
    final totalHeight = blocks.fold<double>(
      0,
      (sum, block) => sum + block.height,
    );
    var emittedHeight = 0.0;
    final paginator = Paginator(
      pageHeight: pageHeight,
      topPadding: topPadding,
      tolerance: tolerance,
    );
    final completer = Completer<void>();
    paginator
        .paginate(blocks: blocks, spineIndex: spineIndex, token: _token)
        .listen(
          (page) {
            if (_token.isCancelled) {
              return;
            }
            emittedHeight += page.slices.fold<double>(
              0,
              (sum, slice) => sum + slice.height,
            );
            _progress = totalHeight <= 0
                ? 1
                : (emittedHeight / totalHeight).clamp(0.0, 1.0);
            if (!_controller.isClosed) {
              _controller.add(page);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_controller.isClosed) {
              _controller.addError(error, stackTrace);
            }
          },
          onDone: () {
            // 不等待 close：UI 可能暂停订阅，done 仍应立即完成。
            if (!_controller.isClosed) {
              unawaited(_controller.close());
            }
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
        );
    await completer.future;
  }
}
