import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/paragraph_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'reader_session.dart';
import 'reader_view.dart';
import 'theme/reader_theme.dart';
import 'loading_skeleton.dart';

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
    this.theme,
    this.overrides,
    this.paragraphCache,
    this.showPageFooter = true,
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

  /// 页脚页码（P8-10 页家具 6 槽的第一槽；槽模板与设置项后续接入）。
  final bool showPageFooter;

  /// 会话就绪回调（测试/调试）。
  final ValueChanged<ReaderSession>? onSessionReady;

  /// 图片解码缓存（可选）；传入后背景图按需解码并触发重绘。
  final DecodedImageCache? imageCache;

  /// 阅读主题（可选）：背景色与正文色成对定义（P2-23）。
  final ReaderTheme? theme;

  /// 阅读器设置覆盖（可选）：字号/行高/对齐/页边距（P2-22/P2-24）。
  final ReaderOverrides? overrides;

  /// 行段落缓存（可选）：注入后重排会清空旧段落（P2-30）。
  final ParagraphCache? paragraphCache;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final ReaderSession _session;
  late final ParagraphCache _paragraphCache =
      widget.paragraphCache ?? ParagraphCache(maxEntries: 256);
  late final bool _ownsParagraphCache = widget.paragraphCache == null;
  late PagePainter _painter = _buildPainter();

  PagePainter _buildPainter() => PagePainter(
    background: widget.theme?.background ?? widget.background,
    imageLookup: widget.imageCache?.lookup,
    textColor: widget.theme?.text,
    paragraphCache: _paragraphCache,
  );

  /// 设置与主题合并后的有效覆盖（主题补正文/背景色，设置优先）。
  ReaderOverrides _effectiveOverrides() {
    final base = widget.overrides ?? const ReaderOverrides();
    final theme = widget.theme;
    if (theme == null) {
      return base;
    }
    return base.copyWith(
      textColor: base.textColor ?? theme.text,
      backgroundColor: base.backgroundColor ?? theme.background,
    );
  }

  /// 页边距：设置优先，其次 ReaderPage.padding。
  EdgeInsets _effectivePadding() {
    final edges = widget.overrides?.padding;
    final base = edges == null
        ? widget.padding
        : EdgeInsets.fromLTRB(edges.left, edges.top, edges.right, edges.bottom);
    // 全面屏（edge-to-edge）下系统手势区不参与 MediaQuery.padding，
    // 用 viewPadding 兜住，避免正文最后一行压到手势条下方（P2-36 真机）。
    final bottomInset = MediaQuery.maybeViewPaddingOf(context)?.bottom ?? 0;
    if (bottomInset <= 0) {
      return base;
    }
    return base + EdgeInsets.only(bottom: bottomInset);
  }

  /// 已预取过的页键（spine*100000 + pageIndex），避免重复预取。
  int _prefetchedPageKey = -1;

  /// 图片缓存版本号，解码完成后触发重绘。
  int _imageRevision = 0;

  /// 上一次布局的正文区尺寸（旋转/窗口变化检测，P2-31）。
  Size? _lastContentSize;

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

  /// 尺寸变化（旋转/窗口缩放）时通知会话重排并恢复位置（P2-31）。
  void _scheduleContentSize(Size pageSize) {
    final padding = _effectivePadding();
    final content = Size(
      pageSize.width - padding.horizontal,
      pageSize.height - padding.vertical,
    );
    if (content.width <= 0 || content.height <= 0) {
      return;
    }
    if (_lastContentSize == content) {
      return;
    }
    _lastContentSize = content;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          _session.applyContentSize(
            width: content.width,
            height: content.height,
          ),
        );
      }
    });
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
    // 沉浸模式（P8-10 收尾）：阅读页隐藏状态栏与导航栏，退出时恢复。
    // sticky：边缘下滑可临时唤出系统栏，几秒后自动隐藏。
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      ),
    );
    _session = ReaderSession(
      source: widget.source,
      store: widget.store,
      bookId: widget.bookId,
    );
    widget.onSessionReady?.call(_session);
    unawaited(
      _session.open().then(
        (_) => _session.applyOverrides(_effectiveOverrides()),
      ),
    );
  }

  @override
  void didUpdateWidget(ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme != widget.theme ||
        oldWidget.background != widget.background ||
        oldWidget.imageCache != widget.imageCache) {
      setState(() => _painter = _buildPainter());
    }
    if (oldWidget.overrides != widget.overrides) {
      // 重排：旧段落缓存全部失效（P2-30）。
      _paragraphCache.clear();
    }
    if (oldWidget.overrides != widget.overrides ||
        oldWidget.theme != widget.theme) {
      unawaited(_session.applyOverrides(_effectiveOverrides()));
    }
  }

  @override
  void dispose() {
    // 退出阅读页：恢复系统栏（edge-to-edge），并复位到浅色图标语义。
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    _session.cancelPendingLoads();
    _session.dispose();
    if (_ownsParagraphCache) {
      _paragraphCache.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        // 背景铺满窗口（P8-10 收尾）：加载骨架/错误态/正文页统一以主题
        // 背景色打底，避免 padding 外区域透出窗口黑底。
        return ColoredBox(
          color: widget.theme?.background ?? widget.background,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildBody(context),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final page = _session.page;
    if (page == null) {
      final error = _session.error;
      if (error != null) {
        return Center(
          key: const ValueKey<String>('reader-error'),
          child: Text('打开失败：$error'),
        );
      }
      if (_session.loading) {
        return ReaderLoadingSkeleton(
          progress: _session.bookProgress > 0 ? _session.bookProgress : null,
        );
      }
      return const Center(
        key: ValueKey<String>('reader-empty'),
        child: Text('无内容'),
      );
    }
    return LayoutBuilder(
      key: ValueKey<String>('reader-page-${page.spineIndex}-${page.pageIndex}'),
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _schedulePrefetch(page, size.width - _effectivePadding().horizontal);
        _scheduleContentSize(size);
        return Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: _effectivePadding(),
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
            // 页脚页码（P8-10 页家具 6 槽第一槽）。
            if (widget.showPageFooter)
              Positioned(
                left: widget.padding.horizontal / 2,
                right: widget.padding.horizontal / 2,
                bottom: 4,
                child: IgnorePointer(
                  child: Text(
                    '第${page.spineIndex + 1}/${widget.source.chapterCount}章 '
                    '· ${page.pageIndex + 1}/${_session.chapterPageCount}页',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: (widget.theme?.text ?? const Color(0xFF757575))
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            // 翻页/重排时保留旧页，只在顶部显示细进度条（P2-27）。
            if (_session.loading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _session.bookProgress > 0
                      ? _session.bookProgress
                      : null,
                ),
              ),
          ],
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
