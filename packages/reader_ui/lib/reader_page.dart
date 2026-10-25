import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/paragraph_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'panels/bookmark_panel.dart';
import 'selection/selection.dart';
import 'selection/selection_menu.dart';
import 'selection/selection_layer.dart';
import 'panels/toc_panel.dart';
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
    this.bookmarks,
    this.onSessionReady,
    this.imageCache,
    this.theme,
    this.overrides,
    this.paragraphCache,
    this.showPageFooter = true,
  });

  /// 章节页来源。
  final ReaderChapterSource source;

  /// 书签存储（P4-13）；为 null 时菜单不显示书签入口。
  final ReaderBookmarkStore? bookmarks;

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

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
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

  /// 目录面板滚动位置（重开时保持，P4-11 验收）。
  final ScrollController _tocScrollController = ScrollController();

  /// 当前页选区（P4-15）；翻页/点菜单时清除。
  ReaderSelection? _selection;

  /// 选区所属页（`spine/page`）：任何翻页（手势/程序/目录跳转）都会清选区。
  String? _selectionPageKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  /// 点屏幕中央：阅读菜单（P4-11 目录；P4-13 书签；P4-21 再补主题/排版）。
  ///
  /// 菜单 / 目录 / 书签在同一 sheet 内切换：真机上先 pop 菜单再开新 sheet 会
  /// 被关闭动画吃掉（表现为点了没反应）。
  Future<void> _openReaderMenu() async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.66,
        child: _ReaderMenuSheet(
          entries: _session.toc,
          currentSpineIndex: _session.progress?.spineIndex ?? 0,
          chapterCount: widget.source.chapterCount,
          scrollController: _tocScrollController,
          bookmarks: widget.bookmarks,
          hasCfi: _session.currentCfi != null,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    if (result is TocEntry) {
      await _session.jumpToChapter(result.spineIndex, title: result.title);
      return;
    }
    if (result == 'add-bookmark') {
      await _addBookmark();
      return;
    }
    if (result is ReaderBookmark) {
      await _session.jumpToCfi(result.cfi, title: result.label);
    }
  }

  /// 添加当前页书签（P4-13）。
  Future<void> _addBookmark() async {
    final store = widget.bookmarks;
    final cfi = _session.currentCfi;
    if (store == null || cfi == null) {
      _showToast('当前位置不支持书签');
      return;
    }
    final progress = _session.progress;
    final spine = progress?.spineIndex ?? 0;
    final page = progress?.pageIndex ?? 0;
    final created = await store.add(
      cfi: cfi,
      spineIndex: spine,
      label: '第 ${spine + 1} 章 · 第 ${page + 1} 页',
    );
    if (!mounted) {
      return;
    }
    _showToast(created == null ? '该位置已有书签' : '已添加书签');
  }

  /// 长按 → 选词（P4-15，§63.2：长按先试词，失败退到连续同类字符段）。
  void _selectWordAt(Offset localPosition) {
    final page = _session.page;
    if (page == null) {
      return;
    }
    final padding = _effectivePadding();
    final hit = TextHitTester.hitTest(
      page,
      localPosition - Offset(padding.left, padding.top),
    );
    if (hit == null || hit.lineBox.text.trim().isEmpty) {
      _clearSelection();
      return;
    }
    setState(() {
      _selection = SelectionOps.wordAt(page, hit);
      _selectionPageKey = '${page.spineIndex}/${page.pageIndex}';
    });
  }

  /// 三击 → 选句（P4-16）。
  void _selectSentenceAt(Offset localPosition) {
    final page = _session.page;
    if (page == null) {
      return;
    }
    final padding = _effectivePadding();
    final hit = TextHitTester.hitTest(
      page,
      localPosition - Offset(padding.left, padding.top),
    );
    if (hit == null || hit.lineBox.text.trim().isEmpty) {
      _clearSelection();
      return;
    }
    setState(() {
      _selection = SelectionOps.sentenceAt(page, hit);
      _selectionPageKey = '${page.spineIndex}/${page.pageIndex}';
    });
  }

  /// 选区菜单动作（P4-16）：复制 / 全选 / 取消。
  List<SelectionAction> _selectionActions(
    PageContent page,
    ReaderSelection selection,
  ) => <SelectionAction>[
    SelectionAction(
      id: 'copy',
      label: '复制',
      onTap: () => unawaited(_copySelection(page, selection)),
    ),
    SelectionAction(id: 'select-all', label: '全选', onTap: () => _selectAll(page)),
    SelectionAction(id: 'dismiss', label: '取消', onTap: _clearSelection),
  ];

  Future<void> _copySelection(PageContent page, ReaderSelection selection) async {
    final text = SelectionOps.textOf(page, selection);
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _clearSelection();
    _showToast('已复制');
  }

  void _selectAll(PageContent page) {
    final boxes = TextHitTester.lineBoxes(page);
    if (boxes.isEmpty) {
      return;
    }
    final first = boxes.first;
    final last = boxes.last;
    setState(() {
      _selectionPageKey = '${page.spineIndex}/${page.pageIndex}';
      _selection = ReaderSelection.normalized(
        TextHit(
          lineBox: first,
          charOffset: 0,
          textOffset: first.textOffset,
          atLineStart: true,
          atLineEnd: false,
        ),
        TextHit(
          lineBox: last,
          charOffset: last.text.length,
          textOffset: last.textOffset + last.text.length,
          atLineStart: false,
          atLineEnd: true,
        ),
      );
    });
  }

  void _clearSelection() {
    if (_selection != null) {
      setState(() => _selection = null);
    }
  }

  void _showToast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  /// 切后台/失去焦点时立即落盘（P4-10）：系统回收不丢最后一次翻页。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_session.flushProgress());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 退出阅读页：恢复系统栏（edge-to-edge），并复位到浅色图标语义。
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    _session.cancelPendingLoads();
    _session.dispose();
    if (_ownsParagraphCache) {
      _paragraphCache.dispose();
    }
    _tocScrollController.dispose();
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
    // 页面换了但选区还在（程序化翻页/目录跳转）→ 下一帧清除。
    if (page != null &&
        _selection != null &&
        _selectionPageKey != '${page.spineIndex}/${page.pageIndex}') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _clearSelection();
        }
      });
    }
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
                    imageRevision: _imageRevision,
                  ),
                ),
              ),
            ),
            ReaderView(
              onPrevious: () {
                _clearSelection();
                unawaited(_session.previous());
              },
              onNext: () {
                _clearSelection();
                unawaited(_session.next());
              },
              onToggleToolbar: () {
                _clearSelection();
                unawaited(_openReaderMenu());
              },
              onLongPressAt: _selectWordAt,
              onDoubleTapAt: _selection == null ? null : _selectWordAt,
              onTripleTapAt: _selection == null ? null : _selectSentenceAt,
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
            // 选区层（P4-15）：高亮 + 起止手柄；只有手柄热区接收手势。
            if (_selection != null) ...[
              Positioned.fill(
                child: SelectionLayer(
                  page: page,
                  selection: _selection!,
                  onChanged: (next) => setState(() => _selection = next),
                ),
              ),
              // 选区菜单（P4-16）：贴在选区上方，不遮挡选区。
              SelectionMenu(
                actions: _selectionActions(page, _selection!),
                anchor: SelectionOps.boundsOf(page, _selection!),
                bounds: size,
              ),
            ],
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
            // 跳章浮层（P4-12，§27.2）：目标章名 + 不确定进度，完成后淡出。
            _JumpLoadingOverlay(title: _session.jumpLoadingTitle),
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
    required this.imageRevision,
  });

  final PageContent page;
  final PagePainter painter;
  final int imageRevision;

  @override
  void paint(Canvas canvas, Size size) {
    // 画布即正文区（Padding 已把画布收窄）；pageSize 必须同步取画布尺寸，
    // 否则块的背景/边框/居中图按整窗宽计算 → 整体右移并压出右缘。
    painter.paint(canvas, page, pageSize: size);
  }

  @override
  bool shouldRepaint(_ReaderPageCustomPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.imageRevision != imageRevision ||
      oldDelegate.painter.background != painter.background;
}

/// 阅读菜单 sheet（P4-11/P4-13）：菜单 / 目录 / 书签三个视图在同一 sheet
/// 内切换，避免真机上「关掉 sheet 立刻开新 sheet」被关闭动画吞掉。
///
/// 返回：选中的 [TocEntry] / [ReaderBookmark] / `'add-bookmark'`（null = 关闭）。
class _ReaderMenuSheet extends StatefulWidget {
  const _ReaderMenuSheet({
    required this.entries,
    required this.currentSpineIndex,
    required this.chapterCount,
    required this.scrollController,
    required this.bookmarks,
    required this.hasCfi,
  });

  final List<TocEntry> entries;
  final int currentSpineIndex;
  final int chapterCount;
  final ScrollController scrollController;
  final ReaderBookmarkStore? bookmarks;
  final bool hasCfi;

  @override
  State<_ReaderMenuSheet> createState() => _ReaderMenuSheetState();
}

class _ReaderMenuSheetState extends State<_ReaderMenuSheet> {
  int _view = 0; // 0=菜单 1=目录 2=书签
  Future<List<ReaderBookmark>>? _bookmarksFuture;

  void _showView(int view) {
    setState(() {
      _view = view;
      if (view == 2) {
        _bookmarksFuture = widget.bookmarks?.list() ??
            Future<List<ReaderBookmark>>.value(const <ReaderBookmark>[]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_view == 1) {
      return TocPanel(
        entries: widget.entries,
        currentSpineIndex: widget.currentSpineIndex,
        scrollController: widget.scrollController,
        onBack: () => _showView(0),
        onSelect: (entry) => Navigator.of(context).pop(entry),
      );
    }
    if (_view == 2) {
      return FutureBuilder<List<ReaderBookmark>>(
        future: _bookmarksFuture,
        builder: (context, snapshot) {
          final store = widget.bookmarks;
          final items = snapshot.data ?? const <ReaderBookmark>[];
          return BookmarkPanel(
            bookmarks: items,
            onBack: () => _showView(0),
            onSelect: (bookmark) => Navigator.of(context).pop(bookmark),
            onDelete: (bookmark) async {
              await store?.remove(bookmark.id);
              if (mounted) {
                _showView(2);
              }
            },
          );
        },
      );
    }
    final theme = Theme.of(context);
    final tocCount = flattenToc(widget.entries).length;
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Text('阅读菜单', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    '第 ${widget.currentSpineIndex + 1}/${widget.chapterCount} 章',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('目录'),
              subtitle: Text('共 $tocCount 章'),
              onTap: () => _showView(1),
            ),
            if (widget.bookmarks != null)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('添加书签'),
                enabled: widget.hasCfi,
                subtitle: widget.hasCfi ? null : const Text('当前位置不支持书签'),
                onTap: () => Navigator.of(context).pop('add-bookmark'),
              ),
            if (widget.bookmarks != null)
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: const Text('书签'),
                onTap: () => _showView(2),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 跳章浮层（P4-12，§27.2）：目标章名 + 不确定进度转圈，完成后淡出。
class _JumpLoadingOverlay extends StatelessWidget {
  const _JumpLoadingOverlay({required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = title != null;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: visible
            ? ColoredBox(
                key: const ValueKey<String>('reader-jump-loading'),
                color: theme.colorScheme.surface.withValues(alpha: 0.92),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          '正在打开 $title',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
