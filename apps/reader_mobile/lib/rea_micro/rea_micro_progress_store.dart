import 'package:reader_ui/reader_session.dart';

/// 在阅读进度成功落盘后通知阅微同步器。
///
/// 只有底层存储确认保存后才更新待上报状态；被旧内容修订拒绝的位置不会
/// 覆盖云端较新的进度。
class ReaMicroTrackingProgressStore implements ReaderProgressStore {
  /// 创建跟踪存储。
  ReaMicroTrackingProgressStore(this._delegate, this._onSaved);

  final ReaderProgressStore _delegate;
  final Future<void> Function(String bookId, ReaderProgress progress) _onSaved;

  /// 在线阅读使用独立位置存储时保留同一保存通知，避免绕过同步队列。
  ReaderProgressStore withDelegate(ReaderProgressStore delegate) =>
      ReaMicroTrackingProgressStore(delegate, _onSaved);

  @override
  Future<ReaderProgress?> load(String bookId) => _delegate.load(bookId);

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    await _delegate.save(bookId, progress);
    await _onSaved(bookId, progress);
  }

  @override
  Future<void> clear(String bookId) => _delegate.clear(bookId);

  @override
  Future<Map<String, ReaderProgress>> snapshot() => _delegate.snapshot();
}
