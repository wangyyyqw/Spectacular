import 'dart:async';

import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';

import '../reader_session.dart';

/// 内容预排独立于图片解码和位图捕获，翻页暂停后继续同一章节作业。
class ChapterPreloadController {
  ChapterPreloadController(this.session, {required this.onFirstPage});

  final ReaderSession session;
  final void Function() onFirstPage;
  Timer? _timer;
  PageContent? _page;
  int _generation = -1;
  int _token = 0;
  bool _paused = true;
  bool _started = false;
  bool _closed = false;
  PageContent? firstPage;

  void update({required bool paused}) {
    if (_closed) return;
    session.setBackgroundLayoutPaused(paused);
    _paused = paused;
    final page = session.page;
    if (!identical(page, _page) || _generation != session.generation) {
      _timer?.cancel();
      _timer = null;
      _token += 1;
      _page = page;
      _generation = session.generation;
      _started = false;
      firstPage = null;
    }
    if (paused ||
        page == null ||
        session.loading ||
        session.jumpLoadingTitle != null) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_started || _timer != null) return;
    final token = _token;
    _timer = Timer(const Duration(milliseconds: 100), () {
      _timer = null;
      unawaited(_prepare(page, token));
    });
  }

  Future<void> _prepare(PageContent page, int token) async {
    if (!_current(page, token)) return;
    _started = true;
    var retry = false;
    try {
      await session.preparseNextChapter(
        shouldContinue: () => _current(page, token),
      );
      if (!_current(page, token)) return;
      final first = await session.prefetchTurnChapter(
        true,
        idle: true,
        shouldContinue: () => _current(page, token),
      );
      if (first == null || !_current(page, token)) return;
      if (!identical(firstPage, first)) {
        firstPage = first;
        onFirstPage();
      }
      // 首页可显示不代表长章总数已就绪；持续观察余章，抢占取消后在空闲时重试。
      await session.completeChapterPreload(first.spineIndex);
    } on ChapterLoadCancelled {
      retry = true;
    } catch (_) {
      // 后台失败留给下一次空闲重试，实际翻页仍走正式加载入口。
    } finally {
      if (token == _token) {
        _started =
            firstPage != null &&
            session.isChapterComplete(firstPage!.spineIndex);
        if (retry && _current(page, token)) update(paused: false);
      }
    }
  }

  bool _current(PageContent page, int token) =>
      !_closed &&
      !_paused &&
      token == _token &&
      _generation == session.generation &&
      identical(page, session.page) &&
      !session.loading &&
      session.jumpLoadingTitle == null;

  void dispose() {
    _closed = true;
    _timer?.cancel();
  }
}
