import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'reader_session.dart';
import 'reader_view.dart';

/// 最小可运行的阅读页：打开、分页、绘制、翻页与进度恢复。
class ReaderPage extends StatefulWidget {
  /// 创建阅读页。
  const ReaderPage({
    super.key,
    required this.source,
    required this.store,
    required this.bookId,
    this.background = const Color(0xFFFFFFFF),
    this.onSessionReady,
  });

  /// 章节页来源。
  final ReaderChapterSource source;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书籍标识。
  final String bookId;

  /// 页面背景。
  final Color background;

  /// 会话就绪回调（测试/调试）。
  final ValueChanged<ReaderSession>? onSessionReady;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final ReaderSession _session;
  late final PagePainter _painter = PagePainter(background: widget.background);

  @override
  void initState() {
    super.initState();
    _session = ReaderSession(
      source: widget.source,
      store: widget.store,
      bookId: widget.bookId,
    );
    widget.onSessionReady?.call(_session);
    unawaited(_session.open());
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        if (_session.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = _session.error;
        if (error != null) {
          return Center(child: Text('打开失败：$error'));
        }
        final page = _session.page;
        if (page == null) {
          return const Center(child: Text('无内容'));
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _ReaderPageCustomPainter(
                    page: page,
                    painter: _painter,
                    pageSize: size,
                  ),
                ),
                ReaderView(
                  onPrevious: () => unawaited(_session.previous()),
                  onNext: () => unawaited(_session.next()),
                  child: const SizedBox.expand(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ReaderPageCustomPainter extends CustomPainter {
  const _ReaderPageCustomPainter({
    required this.page,
    required this.painter,
    required this.pageSize,
  });

  final PageContent page;
  final PagePainter painter;
  final Size pageSize;

  @override
  void paint(Canvas canvas, Size size) {
    painter.paint(canvas, page, pageSize: pageSize);
  }

  @override
  bool shouldRepaint(_ReaderPageCustomPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.pageSize != pageSize ||
      oldDelegate.painter.background != painter.background;
}
