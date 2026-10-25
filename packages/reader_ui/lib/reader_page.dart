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

import 'annotations/annotation.dart';
import 'annotations/annotation_layer.dart';
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
    this.annotations,
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

  /// 标注存储（P4-17）；为 null 时选区菜单不显示高亮/笔记。
  final ReaderAnnotationStore? annotations;

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

  /// 全书标注（P4-18）：打开时加载，标注变更后刷新。
  List<ReaderAnnotation> _annotations = const <ReaderAnnotation>[];

  /// 选区所属章（跨页选区跨翻页时不清，翻章才清）。
  int? _selectionSpineIndex;

  /// 边缘翻页去抖定时器（§63.5：300ms）。
  Timer? _selectionEdgeTimer;

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
    unawaited(_reloadAnnotations());
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

  /// 拖拽产生的页内局部选区 → 全局跨页选区（P4-19）。
  void _applyLocalSelection(ReaderSelection local) {
    final page = _session.page;
    if (page == null || _selection == null) {
      return;
    }
    setState(() {
      _selection = ReaderSelection.spanning(
        start: local.start,
        startPageIndex: page.pageIndex,
        end: local.end,
        endPageIndex: page.pageIndex,
      );
    });
  }

  /// 拖到页边 → 延时 300ms 翻页并扩展选区（§63.5）。
  void _handleSelectionEdgeDrag(bool forward) {
    _selectionEdgeTimer?.cancel();
    _selectionEdgeTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(forward ? _extendSelectionForward() : _extendSelectionBackward());
    });
  }

  Future<void> _extendSelectionForward() async {
    final selection = _selection;
    final page = _session.page;
    if (selection == null || page == null) {
      return;
    }
    final changed = await _session.next();
    if (!changed || !mounted) {
      return;
    }
    final nextPage = _session.page;
    if (nextPage == null) {
      return;
    }
    final boxes = TextHitTester.lineBoxes(nextPage);
    if (boxes.isEmpty) {
      return;
    }
    final last = boxes.last;
    setState(() {
      _selection = ReaderSelection.spanning(
        start: selection.start,
        startPageIndex: selection.startPageIndex,
        end: TextHit(
          lineBox: last,
          charOffset: last.text.length,
          textOffset: last.textOffset + last.text.length,
          atLineStart: false,
          atLineEnd: true,
        ),
        endPageIndex: nextPage.pageIndex,
      );
      _selectionSpineIndex = nextPage.spineIndex;
    });
  }

  Future<void> _extendSelectionBackward() async {
    final selection = _selection;
    final page = _session.page;
    if (selection == null || page == null) {
      return;
    }
    final changed = await _session.previous();
    if (!changed || !mounted) {
      return;
    }
    final prevPage = _session.page;
    if (prevPage == null) {
      return;
    }
    final boxes = TextHitTester.lineBoxes(prevPage);
    if (boxes.isEmpty) {
      return;
    }
    final first = boxes.first;
    setState(() {
      _selection = ReaderSelection.spanning(
        start: TextHit(
          lineBox: first,
          charOffset: 0,
          textOffset: first.textOffset,
          atLineStart: true,
          atLineEnd: false,
        ),
        startPageIndex: prevPage.pageIndex,
        end: selection.end,
        endPageIndex: selection.endPageIndex,
      );
      _selectionSpineIndex = prevPage.spineIndex;
    });
  }

  /// 重新加载全书标注（P4-18）。
  Future<void> _reloadAnnotations() async {
    final store = widget.annotations;
    if (store == null) {
      return;
    }
    final items = await store.list();
    if (!mounted) {
      return;
    }
    setState(() => _annotations = items);
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
      _selectionSpineIndex = page.spineIndex;
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
      _selectionSpineIndex = page.spineIndex;
    });
  }

  /// 选区菜单动作（P4-16）：复制 / 全选 / 取消。
  List<SelectionAction> _selectionActions(
    PageContent page,
    ReaderSelection selection,
  ) => <SelectionAction>[
    if (widget.annotations != null)
      SelectionAction(
        id: 'highlight',
        label: '高亮',
        onTap: () => unawaited(
          _saveAnnotation(page, selection, ReaderAnnotationType.highlight),
        ),
      ),
    if (widget.annotations != null)
      SelectionAction(
        id: 'note',
        label: '笔记',
        onTap: () => unawaited(_addNote(page, selection)),
      ),
    SelectionAction(
      id: 'copy',
      label: '复制',
      onTap: () => unawaited(_copySelection(page, selection)),
    ),
    SelectionAction(id: 'select-all', label: '全选', onTap: () => _selectAll(page)),
    SelectionAction(id: 'dismiss', label: '取消', onTap: _clearSelection),
  ];

  /// 保存高亮/笔记（P4-17）：CFI 区间 + 原文 + 前后文。
  Future<void> _saveAnnotation(
    PageContent page,
    ReaderSelection selection,
    ReaderAnnotationType type, {
    String? note,
  }) async {
    final store = widget.annotations;
    if (store == null) {
      return;
    }
    final cfi = SelectionOps.cfiOf(selection);
    final quote = selection.isMultiPage
        ? SelectionOps.textAcrossPages(await _session.chapterPages(), selection)
        : SelectionOps.textOf(page, selection);
    if (cfi == null || quote.isEmpty) {
      _showToast('当前位置不支持标注');
      return;
    }
    final context = SelectionOps.contextOf(page, selection);
    final created = await store.add(
      type: type,
      startCfi: cfi.start,
      endCfi: cfi.end,
      quote: quote,
      contextBefore: context.before,
      contextAfter: context.after,
      color: type == ReaderAnnotationType.highlight ? 0xFFFFEB3B : null,
      note: note,
    );
    if (!mounted) {
      return;
    }
    if (created != null) {
      unawaited(_reloadAnnotations());
    }
    _clearSelection();
    _showToast(created == null ? '该位置已有标注' : (type == ReaderAnnotationType.note ? '已添加笔记' : '已高亮'));
  }

  /// 输入笔记正文后保存（P4-17）。
  Future<void> _addNote(PageContent page, ReaderSelection selection) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('笔记'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '写点什么…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || note.trim().isEmpty) {
      return;
    }
    await _saveAnnotation(
      page,
      selection,
      ReaderAnnotationType.note,
      note: note.trim(),
    );
  }

  Future<void> _copySelection(PageContent page, ReaderSelection selection) async {
    final text = selection.isMultiPage
        ? SelectionOps.textAcrossPages(
            await _session.chapterPages(),
            selection,
          )
        : SelectionOps.textOf(page, selection);
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
      _selectionSpineIndex = page.spineIndex;
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
    _selectionEdgeTimer?.cancel();
    _selectionEdgeTimer = null;
    if (_selection != null) {
      setState(() {
        _selection = null;
        _selectionSpineIndex = null;
      });
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
    _selectionEdgeTimer?.cancel();
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
    // 页面不在选区范围内（翻章/跳转）→ 下一帧清除；跨页选区范围内保留。
    // 回调里重新取最新状态：边缘翻页会先翻页再扩展选区，两者不能互相打断。
    if (page != null && _selection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final current = _selection;
        final currentPage = _session.page;
        if (current == null || currentPage == null) {
          return;
        }
        final sameSpine =
            _selectionSpineIndex == null ||
            _selectionSpineIndex == currentPage.spineIndex;
        final inRange =
            currentPage.pageIndex >= current.startPageIndex &&
            currentPage.pageIndex <= current.endPageIndex;
        if (!sameSpine || !inRange) {
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
            // 标注装饰层（P4-18）：高亮底色 + 笔记标记，在正文之上、选区之下。
            if (_annotations.isNotEmpty)
              Positioned.fill(
                child: AnnotationLayer(
                  page: page,
                  annotations: _annotations,
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
                  pageIndex: page.pageIndex,
                  selection: _selection!,
                  onChanged: _applyLocalSelection,
                  onEdgeDrag: _handleSelectionEdgeDrag,
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
