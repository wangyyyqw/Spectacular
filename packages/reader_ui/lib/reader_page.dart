import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_cache.dart';
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
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.onSessionReady,
    this.imageCache,
  });

  /// 章节页来源。
  final ReaderChapterSource source;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书籍标识。
  final String bookId;

  /// 页面背景。
  final Color background;

  /// 正文区外边距。
  final EdgeInsets padding;

  /// 会话就绪回调（测试/调试）。
  final ValueChanged<ReaderSession>? onSessionReady;

  /// 图片解码缓存（可选）；传入后背景图按需解码并触发重绘。
  final DecodedImageCache? imageCache;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final ReaderSession _session;
  late final PagePainter _painter = PagePainter(
    background: widget.background,
    imageLookup: widget.imageCache?.lookup,
  );

  /// 已预取过的页键（spine*100000 + pageIndex），避免重复预取。
  int _prefetchedPageKey = -1;

  /// 图片缓存版本号，解码完成后触发重绘。
  int _imageRevision = 0;

  /// 预取本页引用的背景图；解码完成后 setState，占位替换为真图。
  void _prefetchPageImages(PageContent page, double displayWidth) {
    final cache = widget.imageCache;
    if (cache == null) {
      return;
    }
    final urls = <String>{
      for (final slice in page.slices)
        if (slice.block.style?.backgroundImage != null)
          slice.block.style!.backgroundImage!,
    };
    if (urls.isEmpty) {
      return;
    }
    final before = cache.revision;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    unawaited(
      cache
          .prefetch(urls, displayWidth: displayWidth, devicePixelRatio: ratio)
          .then((_) {
            if (!mounted || cache.revision == before) {
              return;
            }
            setState(() => _imageRevision = cache.revision);
          }),
    );
  }

  void _schedulePrefetch(PageContent page, double displayWidth) {
    final key = page.spineIndex * 100000 + page.pageIndex;
    if (_prefetchedPageKey == key) {
      return;
    }
    _prefetchedPageKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prefetchPageImages(page, displayWidth);
      }
    });
  }

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
            _schedulePrefetch(page, size.width - widget.padding.horizontal);
            return Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: widget.padding,
                  child: ClipRect(
                    child: CustomPaint(
                      painter: _ReaderPageCustomPainter(
                        page: page,
                        painter: _painter,
                        pageSize: size,
                        imageRevision: _imageRevision,
                      ),
                    ),
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
    required this.imageRevision,
  });

  final PageContent page;
  final PagePainter painter;
  final Size pageSize;
  final int imageRevision;

  @override
  void paint(Canvas canvas, Size size) {
    painter.paint(canvas, page, pageSize: pageSize);
  }

  @override
  bool shouldRepaint(_ReaderPageCustomPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.pageSize != pageSize ||
      oldDelegate.imageRevision != imageRevision ||
      oldDelegate.painter.background != painter.background;
}
