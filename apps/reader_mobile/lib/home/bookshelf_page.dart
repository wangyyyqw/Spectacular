import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'package:reader_core/epub/importer.dart';

import '../book_source/book_source_models.dart';
import '../book_source/online_book_controller.dart';
import '../book_source/online_book_detail_page.dart';
import '../book_source/online_chapter_request.dart';
import '../book_source/online_epub_export.dart';
import '../book_source/online_epub_metadata.dart';
import '../library/library_store.dart';
import '../rea_micro/rea_micro_controller.dart';
import '../rea_micro/rea_micro_models.dart';
import '../rea_micro/rea_micro_public_reading_page.dart';
import '../reader/book_opener.dart';
import '../reader/reader_text_warmup.dart';
import '../editing/book_edit_repository.dart';
import '../editing/book_editor_route.dart';
import '../txt/txt_book_service.dart';
import '../txt/txt_chapter_rule_page.dart';
import '../txt/txt_encoding_dialog.dart';
import 'desktop_layout.dart';
import 'desktop_book_interaction.dart';
import 'book_import_conflict_dialog.dart';
import 'book_detail_page.dart';
import 'book_detail_sheet.dart';
import 'book_lists_view.dart';
import 'bookshelf_sort.dart';
import 'book_cover_image.dart';
import 'book_search_bar.dart';
import 'reading_insights.dart';
import '../storage/import_queue.dart';
import '../storage/reading_session_store.dart';
import '../diagnostics/reader_log.dart';
import '../cloud/cloud_import_page.dart';

/// 书架条目及列表显示的阅读记录。
typedef _ShelfItem = ({
  BookEntry entry,
  int? spineIndex,
  Duration duration,
  int? onlineSpineIndex,
  int? onlineSpineCount,
  bool isOnline,
});

typedef _OnlineShelfProgress = ({
  int? spineIndex,
  int? chapterCount,
  bool finished,
  bool isOnline,
});
typedef _OnlineStoredProgress = ({
  int spineIndex,
  String? chapterIdentity,
  bool finished,
});

const _shelfMinColumns = 3;
const _shelfTargetCardWidth = 192.0;
const _desktopShelfCoverWidth = 160.0;
const _desktopShelfListWidth = 920.0;
const _shelfGridPadding = 16.0;
const _shelfGridSpacing = 16.0;
const _shelfCoverAspectRatio = 3 / 4;
const _shelfTitleGap = 6.0;
const _shelfTitleHeight = 20.0;
const _shelfToolbarIconStroke = 1.3;
const _pinnedCoverShadowOpacity = .42;
final _bookPressOverlay = WidgetStateProperty.resolveWith<Color?>(
  (states) => states.contains(WidgetState.pressed) ? Colors.transparent : null,
);

ThemeData _noFeedback(BuildContext context) => Theme.of(context).copyWith(
  splashFactory: NoSplash.splashFactory,
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: usesDesktopLayout(context) ? null : Colors.transparent,
  focusColor: usesDesktopLayout(context) ? null : Colors.transparent,
);

/// 书架页：书籍网格/列表、EPUB 与 TXT 导入、点击进入阅读、长按看详情。
class BookshelfPage extends StatefulWidget {
  /// 创建页面。
  const BookshelfPage({
    super.key,
    required this.library,
    required this.progressStore,
    this.refreshToken = 0,
    this.allowImport = true,
    this.onReadingFinished,
    this.reaMicro,
    this.onlineBooks,
    this.bookOpener,
    this.active = true,
    this.onInitialCoversReady,
    this.pickEpubFiles = _pickWithFilePicker,
    this.readFile = _readFile,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 阅读进度存储（进阅读页用）。
  final ReaderProgressStore progressStore;

  /// 外部切换页面时递增，用于重新读取排序设置。
  final int refreshToken;

  /// 临时模式暂停新增与更新导入，避免将内存内容误认为已保存。
  final bool allowImport;

  /// 阅读会话落盘并关闭阅读页后通知，供阅微自动同步。
  final VoidCallback? onReadingFinished;

  /// 阅微控制器；用于读取离线音色目录。
  final ReaMicroController? reaMicro;

  /// 在线书源控制器；用于搜索、下载与更新关联书籍。
  final OnlineBookController? onlineBooks;

  final BookOpener? bookOpener;

  /// 页面是否处于当前分栏；桌面快捷键只响应活动页。
  final bool active;

  /// 当前排序的前 12 本封面准备好、可见封面绘制后回调。
  final VoidCallback? onInitialCoversReady;

  /// 选文件入口（默认 file_picker 多选；测试注入）。
  final Future<List<String>> Function() pickEpubFiles;

  /// 读取文件字节（默认 dart:io；测试注入以便在 FakeAsync 中同步返回）。
  final Future<Uint8List> Function(String path) readFile;

  static Future<Uint8List> _readFile(String path) => File(path).readAsBytes();

  static Future<List<String>> _pickWithFilePicker() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['epub', 'txt'],
    );
    return <String>[
      for (final file in files)
        if (file.path != null) file.path!,
    ];
  }

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  static const _viewKey = 'bookshelf.grid';
  static const _pinnedKey = 'bookshelf.pinned';

  List<_ShelfItem>? _items;

  late final BookOpener _bookOpener;
  late final ImportQueue _queue;
  final List<ImportJob> _batch = <ImportJob>[];
  int _reportedJobs = 0;
  String? _error;
  ImportJob? _encodingJob;
  List<String> _pinnedIds = const <String>[];
  List<ShelfGroup> _groups = const <ShelfGroup>[];
  Map<String, String> _bookGroups = const <String, String>{};
  String? _activeGroupId;
  bool _grid = true;
  bool _gridShowTitles = true;
  bool _listDividers = true;
  bool _newestFirst = false;
  bool _autoUpdateFirst = false;
  bool _allAsGroup = false;
  String _defaultGroupName = '默认';
  Map<String, Map<String, Object?>> _onlineUpdates = const {};
  Set<String> _finishedBooks = const {};
  bool _searching = false;
  bool _selectionMode = false;
  bool _removing = false;
  bool _pickingFiles = false;
  bool _exportingBook = false;
  String _query = '';
  final Set<String> _selectedIds = <String>{};
  String? _selectionAnchor;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'bookshelf-search');
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'bookshelf-keyboard');
  Future<void>? _reloadTask;
  bool _reloadRequested = false;
  Future<void>? _preferences;
  int _coverPreloadGeneration = 0;

  @override
  void initState() {
    super.initState();
    try {
      // 正式性能探针直接从书架启动；这里兜底预热，确保其他启动入口也能
      // 在打开书籍前完成字体解析，且不给首帧留下一次性布局成本。
      warmUpReaderTextRendering();
    } catch (error, stack) {
      debugPrint('reader text warm-up failed: $error\n$stack');
    }
    widget.library.addListener(_reload);
    widget.onlineBooks?.addListener(_reload);
    _bookOpener =
        widget.bookOpener ??
        BookOpener(
          library: widget.library,
          progressStore: widget.progressStore,
          onlineBooks: widget.onlineBooks,
          onReadingFinished: widget.onReadingFinished,
          loadTtsVoices: widget.reaMicro == null ? null : _loadTtsVoices,
        );
    _queue = ImportQueue(
      widget.library,
      readFile: widget.readFile,
      onConflict: (conflict) => mounted
          ? chooseBookImport(context, conflict)
          : Future.value(BookImportChoice.cancel),
    )..addListener(_onQueueChanged);
    // 首次加载先等偏好读完，避免书架的排序、置顶和视图在显示后再变一次。
    _preferences = _loadPreferences();
    _reload();
  }

  Future<List<ReaMicroTtsVoice>> _loadTtsVoices() async {
    final controller = widget.reaMicro;
    if (controller == null) return const <ReaMicroTtsVoice>[];
    try {
      final catalog = await controller.fetchTtsCatalog();
      return catalog.voices;
    } catch (_) {
      return const <ReaMicroTtsVoice>[];
    }
  }

  @override
  void didUpdateWidget(BookshelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onlineBooks != widget.onlineBooks) {
      oldWidget.onlineBooks?.removeListener(_reload);
      widget.onlineBooks?.addListener(_reload);
      _reload();
    }
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadPreferences();
    }
    if (widget.active &&
        (!oldWidget.active || oldWidget.refreshToken != widget.refreshToken)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _keyboardFocus.requestFocus();
      });
    }
  }

  KeyEventResult _handleShelfKey(FocusNode node, KeyEvent event) {
    if (!widget.active || ModalRoute.isCurrentOf(context) == false) {
      return KeyEventResult.ignored;
    }
    final command = Theme.of(context).platform == TargetPlatform.macOS;
    final editingText =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    final bindings = <ShortcutActivator, VoidCallback>{
      if (usesDesktopLayout(context) && !editingText) ...{
        SingleActivator(
          LogicalKeyboardKey.keyA,
          meta: command,
          control: !command,
          includeRepeats: false,
        ): _selectVisibleBooks,
        if (_selectionMode && _selectedIds.isNotEmpty)
          SingleActivator(
            command ? LogicalKeyboardKey.backspace : LogicalKeyboardKey.delete,
            meta: command,
            includeRepeats: false,
          ): () =>
              unawaited(_confirmBatchRemove()),
      },
      if (!_selectionMode) ...{
        SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: command,
          control: !command,
          includeRepeats: false,
        ): _focusSearch,
        SingleActivator(
          LogicalKeyboardKey.keyO,
          meta: command,
          control: !command,
          includeRepeats: false,
        ): () =>
            _import(),
      },
      if (_selectionMode || _searching)
        const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
            _selectionMode ? _exitSelectionMode : _toggleSearch,
    };
    for (final binding in bindings.entries) {
      if (!binding.key.accepts(event, HardwareKeyboard.instance)) continue;
      binding.value();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focusSearch() {
    if (!_searching) setState(() => _searching = true);
    _searchFocus.requestFocus();
  }

  /// 读持久化的书架视图与书名显示（settings 表）。
  Future<void> _loadPreferences() async {
    final grid = await widget.library.getSetting(_viewKey);
    final pinned = await widget.library.getSetting(_pinnedKey);
    final showTitles = await widget.library.getSetting(bookshelfShowTitlesKey);
    final gridShowTitles = await widget.library.getSetting(
      bookshelfGridShowTitlesKey,
    );
    final listDividers = await widget.library.getSetting(
      bookshelfListDividersKey,
    );
    final newestFirst = await widget.library.getSetting(
      bookshelfNewestFirstKey,
    );
    final autoUpdateFirst = await widget.library.getSetting(
      bookshelfAutoUpdateFirstKey,
    );
    final allAsGroup = await widget.library.getSetting(bookshelfAllAsGroupKey);
    final defaultGroupName = await widget.library.getSetting(
      bookshelfDefaultGroupNameKey,
    );
    if (!mounted) {
      return;
    }
    final nextGrid = grid != 'false';
    final nextShowTitles = (gridShowTitles ?? showTitles) != 'false';
    final nextDividers = listDividers != 'false';
    final nextNewest = newestFirst == 'true';
    final nextAutoUpdate = autoUpdateFirst == 'true';
    final nextAllAsGroup = allAsGroup == 'true';
    final nextDefaultName = defaultGroupName ?? '默认';
    final nextPinned = pinned == null
        ? const <String>[]
        : (jsonDecode(pinned) as List).cast<String>();
    if (_grid == nextGrid &&
        _gridShowTitles == nextShowTitles &&
        _listDividers == nextDividers &&
        _newestFirst == nextNewest &&
        _autoUpdateFirst == nextAutoUpdate &&
        _allAsGroup == nextAllAsGroup &&
        _defaultGroupName == nextDefaultName &&
        listEquals(_pinnedIds, nextPinned)) {
      return;
    }
    setState(() {
      _grid = nextGrid;
      _gridShowTitles = nextShowTitles;
      _listDividers = nextDividers;
      _newestFirst = nextNewest;
      _autoUpdateFirst = nextAutoUpdate;
      _allAsGroup = nextAllAsGroup;
      _defaultGroupName = nextDefaultName;
      _pinnedIds = nextPinned;
    });
  }

  Future<void> _toggleView() async {
    final grid = !_grid;
    setState(() => _grid = grid);
    await widget.library.setSetting(_viewKey, '$grid');
  }

  Future<void> _togglePinned(BookEntry entry) async {
    final pinned = List<String>.of(_pinnedIds);
    if (!pinned.remove(entry.id)) pinned.insert(0, entry.id);
    await widget.library.setSetting(_pinnedKey, jsonEncode(pinned));
    if (mounted) setState(() => _pinnedIds = pinned);
  }

  void _toggleGroup(String id) {
    setState(() {
      _activeGroupId = _activeGroupId == id ? null : id;
    });
  }

  int _groupBookCount(String? groupId) => (_items ?? const <_ShelfItem>[])
      .where((item) => _bookGroups[item.entry.id] == groupId)
      .length;

  Future<void> _createGroup({
    Set<String> initialBookIds = const <String>{},
  }) async {
    final name = await _promptGroupName(title: '新建分组');
    if (name == null || !mounted) return;
    try {
      final group = await widget.library.createGroup(name);
      if (initialBookIds.isNotEmpty) {
        await widget.library.setBooksGroup(initialBookIds, groupId: group.id);
      }
      await _reload();
      if (mounted) {
        setState(() {
          _activeGroupId = group.id;
          _query = '';
          _selectionMode = false;
          _selectedIds.clear();
        });
      }
    } on LibraryImportException catch (error, stackTrace) {
      recordAppError('group_create_failed', error, stackTrace: stackTrace);
    }
  }

  Future<String?> _promptGroupName({
    required String title,
    String initial = '',
  }) {
    return showReaderDialog<String>(
      context: context,
      builder: (_) => _GroupNameDialog(title: title, initial: initial),
    );
  }

  Future<void> _groupBook(BookEntry entry) async {
    final target =
        await showReaderBottomSheet<
          ({String? groupId, String? name})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _BookGroupSheet(
            summary: entry.title,
            groups: _groups,
            currentGroupId: _bookGroups[entry.id],
            defaultGroupName: _allAsGroup ? _defaultGroupName : null,
          ),
        );
    if (target == null || !mounted) return;
    try {
      final groupId = target.name != null
          ? (await widget.library.createGroup(target.name!)).id
          : target.groupId;
      await widget.library.setBooksGroup([entry.id], groupId: groupId);
      await _reload();
      if (mounted) {
        setState(() {
          _activeGroupId = groupId;
          _query = '';
        });
      }
    } on LibraryImportException catch (error, stackTrace) {
      recordAppError('book_group_failed', error, stackTrace: stackTrace);
    }
  }

  Future<void> _manageGroup(ShelfGroup? group) async {
    final groupName = group?.name ?? _defaultGroupName;
    final action = await showReaderBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(groupName),
              subtitle: Text('${_groupBookCount(group?.id)} 本书'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const AppIcon(AppGlyph.edit),
              title: const Text('重命名分组'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            if (group != null) ListTile(
              leading: AppIcon(
                AppGlyph.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除分组',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('书籍会保留在书架中'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'rename') {
      final name = await _promptGroupName(title: '重命名分组', initial: groupName);
      if (name == null) {
        return;
      }
      try {
        if (group == null) {
          await widget.library.setSetting(bookshelfDefaultGroupNameKey, name);
          if (mounted) setState(() => _defaultGroupName = name);
        } else {
          await widget.library.renameGroup(group.id, name);
        }
      } on LibraryImportException catch (error, stackTrace) {
        recordAppError('group_rename_failed', error, stackTrace: stackTrace);
      }
      return;
    }
    if (action == 'delete' && group != null) {
      final confirmed = await showReaderDialog<bool>(
        context: context,
        builder: (context) => ReaderFrostedAlertDialog(
          title: Text('删除分组「${group.name}」？'),
          content: const Text('书籍会保留在书架中，只删除分组。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.library.deleteGroup(group.id);
        if (mounted && _activeGroupId == group.id) {
          setState(() => _activeGroupId = null);
        }
      }
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
    if (!_searching) {
      _keyboardFocus.requestFocus();
    } else {
      _searchFocus.requestFocus();
    }
  }

  void _resetFilters() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = false;
      _query = '';
      _activeGroupId = null;
    });
  }

  void _startSelection([BookEntry? entry]) {
    _keyboardFocus.requestFocus();
    setState(() {
      _selectionMode = true;
      _selectedIds.clear();
      _selectionAnchor = entry?.id;
      if (entry != null) _selectedIds.add(entry.id);
    });
  }

  void _exitSelectionMode() {
    if (_removing) {
      return;
    }
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
      _selectionAnchor = null;
    });
    _keyboardFocus.requestFocus();
  }

  void _toggleSelected(String id) {
    if (_removing) {
      return;
    }
    setState(() {
      _selectionAnchor = id;
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _selectVisibleBooks() {
    if (_removing || _items == null) return;
    final visible = _visible(_items!, groupId: _activeGroupId);
    if (visible.isEmpty) return;
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..addAll(visible.map((item) => item.entry.id));
      _selectionAnchor = visible.first.entry.id;
    });
  }

  void _selectDesktopBook(BookEntry entry, List<_ShelfItem> books) {
    if (_removing) return;
    final keyboard = HardwareKeyboard.instance;
    final anchor = books.indexWhere(
      (item) => item.entry.id == _selectionAnchor,
    );
    final target = books.indexWhere((item) => item.entry.id == entry.id);
    if (keyboard.isShiftPressed && anchor >= 0 && target >= 0) {
      final additive = Theme.of(context).platform == TargetPlatform.macOS
          ? keyboard.isMetaPressed
          : keyboard.isControlPressed;
      setState(() {
        _selectionMode = true;
        if (!additive) _selectedIds.clear();
        _selectedIds.addAll(
          books
              .sublist(math.min(anchor, target), math.max(anchor, target) + 1)
              .map((item) => item.entry.id),
        );
      });
    } else {
      _selectionMode = true;
      _toggleSelected(entry.id);
    }
  }

  Future<void> _activateBook(BookEntry entry, List<_ShelfItem> books) async {
    final keyboard = HardwareKeyboard.instance;
    final command = Theme.of(context).platform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (usesDesktopLayout(context) &&
        (_selectionMode || command || keyboard.isShiftPressed)) {
      _selectDesktopBook(entry, books);
    } else if (_selectionMode) {
      _toggleSelected(entry.id);
    } else {
      await _open(entry);
    }
  }

  Widget _desktopBook(Widget child, BookEntry entry, List<_ShelfItem> books) =>
      usesDesktopLayout(context)
      ? DesktopBookInteraction(
          key: ValueKey('desktop-book-${entry.id}'),
          onActivate: () => unawaited(_activateBook(entry, books)),
          onSelect: () => _selectDesktopBook(entry, books),
          onMenu: (position) => unawaited(_openBookMenu(entry, position)),
          child: child,
        )
      : child;

  bool _allSelected(List<_ShelfItem>? items) {
    final entries = items ?? const <_ShelfItem>[];
    return entries.isNotEmpty &&
        entries.every((item) => _selectedIds.contains(item.entry.id));
  }

  void _toggleSelectAll(List<_ShelfItem>? items) {
    if (_removing) {
      return;
    }
    final entries = items ?? const <_ShelfItem>[];
    final allSelected = _allSelected(entries);
    setState(() {
      _selectedIds.clear();
      if (!allSelected) {
        _selectedIds.addAll(entries.map((item) => item.entry.id));
      }
    });
  }

  /// 置顶书籍按置顶先后排在前面，其余沿用库中最近阅读顺序。
  List<_ShelfItem> _sorted(List<_ShelfItem> items) {
    final sorted = List<_ShelfItem>.of(items);
    // “新导入图书放到最上面”是显式开关，默认最近打开顺序完全交给
    // LibraryStore。这里使用稳定排序，保证同一导入时间的相对顺序不变。
    if (_newestFirst) {
      final originalOrder = <String, int>{
        for (var index = 0; index < sorted.length; index++)
          sorted[index].entry.id: index,
      };
      sorted.sort((a, b) {
        final result = b.entry.addedAt.compareTo(a.entry.addedAt);
        if (result != 0) return result;
        return originalOrder[a.entry.id]!.compareTo(originalOrder[b.entry.id]!);
      });
    }
    // 更新检查可以临时提升在线书；用户在检查后重新打开的书仍按最近
    // 阅读顺序置顶，避免更新标记冻结正常的阅读排序。
    if (_autoUpdateFirst && _onlineUpdates.isNotEmpty) {
      final originalOrder = <String, int>{
        for (var index = 0; index < sorted.length; index++)
          sorted[index].entry.id: index,
      };
      int priority(_ShelfItem item) {
        final lastReadAt = item.entry.lastReadAt?.millisecondsSinceEpoch ?? 0;
        final update = _onlineUpdates[item.entry.id];
        if (update?['updated'] != true) return lastReadAt;
        final updatedAt =
            update?['updatedAt'] as int? ?? update?['checkedAt'] as int? ?? 0;
        return updatedAt > lastReadAt ? updatedAt : lastReadAt;
      }

      sorted.sort((a, b) {
        final byPriority = priority(b).compareTo(priority(a));
        if (byPriority != 0) return byPriority;
        return originalOrder[a.entry.id]!.compareTo(originalOrder[b.entry.id]!);
      });
    }
    final byId = {for (final item in sorted) item.entry.id: item};
    return [
      for (final id in _pinnedIds) ?byId[id],
      for (final item in sorted)
        if (!_pinnedIds.contains(item.entry.id)) item,
    ];
  }

  /// 先按关键词与当前分组过滤，再沿用书架排序。
  List<_ShelfItem> _visible(List<_ShelfItem> items, {String? groupId}) {
    final query = _query.trim().toLowerCase();
    final filtered = items.where((item) {
      if (_allAsGroup &&
          groupId == null &&
          _bookGroups[item.entry.id] != null) {
        return false;
      }
      if (groupId != null && _bookGroups[item.entry.id] != groupId) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return item.entry.title.toLowerCase().contains(query) ||
          item.entry.author.toLowerCase().contains(query);
    });
    return _sorted(filtered.toList());
  }

  @override
  void dispose() {
    widget.library.removeListener(_reload);
    widget.onlineBooks?.removeListener(_reload);
    _searchController.dispose();
    _searchFocus.dispose();
    _keyboardFocus.dispose();
    _queue
      ..removeListener(_onQueueChanged)
      ..dispose();
    super.dispose();
  }

  /// 队列变化：刷新进度；一批任务全部结束时汇总提示。
  void _onQueueChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    if (!_queue.isIdle || _batch.length == _reportedJobs) {
      return;
    }
    _reportedJobs = _batch.length;
    _showImportSummary();
  }

  void _showImportSummary() {
    final succeeded = _batch
        .where((job) => job.status == ImportStatus.succeeded)
        .length;
    ImportJob? failed;
    for (final job in _batch) {
      if (job.status == ImportStatus.failed) {
        failed = job;
        break;
      }
    }
    final cancelled = _batch
        .where((job) => job.status == ImportStatus.cancelled)
        .length;
    if (succeeded > 0) {
      recordAppEvent('book_import_completed');
    }
    if (failed != null) {
      _showImportFailure(failed);
    } else if (succeeded == 0 && cancelled > 0) {
      recordAppEvent('book_import_cancelled');
    }
  }

  void _showImportFailure(ImportJob failed) {
    if (failed.encodingCandidates.isNotEmpty) {
      setState(() {
        _encodingJob = failed;
        _error = failed.error ?? '请选择正文显示正确的 TXT 编码';
      });
      return;
    }
    final friendly = EpubRejectionMessages.forCode(
      failed.errorCode,
      failed.error ?? '',
    );
    final message = '${friendly.title}。${friendly.suggestion}';
    if (failed.errorCode == 'E_DUPLICATE' ||
        failed.updateBookId != null ||
        failed.errorCode == 'E_REVISION_CONFLICT' ||
        failed.errorCode == 'E_STALE_REVISION') {
      // 重复导入不影响现有书架，用户可以直接打开原书。
      recordAppError('book_import_rejected', StateError(message));
    } else {
      setState(() => _error = message);
    }
  }

  Future<void> _retryEncoding() async {
    final job = _encodingJob;
    if (job == null) return;
    final encoding = await chooseTxtEncoding(context, job.encodingCandidates);
    if (encoding == null || !mounted) return;
    setState(() {
      _error = null;
      _encodingJob = null;
      _reportedJobs = 0;
    });
    _queue.retry(job.id, encoding: encoding);
  }

  Future<void> _reload() {
    _reloadRequested = true;
    return _reloadTask ??= _drainReloads();
  }

  Future<void> _drainReloads() async {
    try {
      while (mounted && _reloadRequested) {
        _reloadRequested = false;
        await _reloadOnce();
      }
    } finally {
      _reloadTask = null;
    }
  }

  Future<void> _reloadOnce() async {
    final firstLoad = _items == null;
    if (firstLoad) {
      // 视图模式决定封面解码宽度，首屏预解码前先拿到已保存的偏好。
      try {
        await (_preferences ?? Future<void>.value());
      } catch (error, stackTrace) {
        // 偏好读取失败时按默认设置显示书架，不阻塞书籍列表。
        recordAppError(
          'bookshelf_preferences_failed',
          error,
          stackTrace: stackTrace,
        );
      }
    }
    // 并发读取后一次更新书架快照。
    final (
      books,
      groups,
      bookGroups,
      progress,
      durations,
      finished,
      updates,
    ) = await (
      widget.library.list(),
      widget.library.listGroups(),
      widget.library.groupAssignments(),
      widget.progressStore.snapshot(),
      widget.library.bookReadingDurations(),
      widget.library.finishedBookIds(),
      widget.library.getSetting(bookshelfOnlineUpdatesKey),
    ).wait;
    Map<String, Map<String, Object?>> onlineUpdates = const {};
    if (updates != null && updates.isNotEmpty) {
      try {
        final decoded = jsonDecode(updates) as Map<String, dynamic>;
        onlineUpdates = {
          for (final entry in decoded.entries)
            if (entry.value is Map)
              entry.key: (entry.value as Map).cast<String, Object?>(),
        };
      } on Object {
        onlineUpdates = const {};
      }
    }
    // 没有在线书源控制器时，书架只展示本地 EPUB；不要为了确认每本
    // 普通书是否带有在线元数据而逐本打开 EPUB，保持首屏加载路径。
    final onlineProgress = widget.onlineBooks == null
        ? <_OnlineShelfProgress>[
            for (final book in books)
              (
                spineIndex: progress[book.id]?.spineIndex,
                chapterCount: book.spineCount,
                finished: progress[book.id]?.finished == true,
                isOnline: false,
              ),
          ]
        : await Future.wait<_OnlineShelfProgress>([
            for (final book in books)
              _readOnlineShelfProgress(book, progress[book.id]),
          ]);
    final items = <_ShelfItem>[
      for (final (index, book) in books.indexed)
        (
          entry: book,
          spineIndex: progress[book.id]?.spineIndex,
          duration: durations[book.id] ?? Duration.zero,
          onlineSpineIndex: onlineProgress[index].spineIndex,
          onlineSpineCount: onlineProgress[index].chapterCount,
          isOnline: onlineProgress[index].isOnline,
        ),
    ];
    if (firstLoad) {
      // 开屏保持遮挡；布局确定后立即按实际显示宽度预解码前 12 本封面。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_preloadCovers());
      });
    }
    if (mounted) {
      final validIds = <String>{for (final item in items) item.entry.id};
      setState(() {
        _items = items;
        _groups = groups;
        _bookGroups = bookGroups;
        _finishedBooks = {
          ...finished,
          for (final (index, book) in books.indexed)
            if (onlineProgress[index].finished) book.id,
        };
        _onlineUpdates = onlineUpdates;
        if (_activeGroupId != null &&
            !groups.any((group) => group.id == _activeGroupId)) {
          _activeGroupId = null;
        }
        _selectedIds.removeWhere((id) => !validIds.contains(id));
        if (items.isEmpty) {
          _selectionMode = false;
        }
      });
    }
  }

  Future<_OnlineShelfProgress> _readOnlineShelfProgress(
    BookEntry entry,
    ReaderProgress? localProgress,
  ) async {
    OnlineEpubMetadata? metadata;
    try {
      metadata = await OnlineEpubMetadata.read(widget.library, entry);
    } on Object {
      metadata = null;
    }
    final indexed = metadata;
    final chapterCount = indexed?.chapters.length;
    if (indexed == null || chapterCount == null || chapterCount <= 0) {
      final onlineProgress = await _readOnlineProgress(entry.id);
      return (
        spineIndex: localProgress?.spineIndex ?? onlineProgress?.spineIndex,
        chapterCount: entry.spineCount,
        finished:
            localProgress?.finished == true || onlineProgress?.finished == true,
        isOnline: widget.onlineBooks?.sourceForBook(entry.id) != null,
      );
    }
    final onlineProgress = await _readOnlineProgress(entry.id);
    final localIndex = await _onlineChapterIndexForSpine(
      entry,
      indexed,
      localProgress?.spineIndex,
    );
    final onlineIndex = _onlineChapterIndex(indexed, onlineProgress);
    return (
      spineIndex: indexed.requiresOnlineReading
          ? onlineIndex
          : localIndex ?? onlineIndex,
      chapterCount: chapterCount,
      finished:
          localProgress?.finished == true || onlineProgress?.finished == true,
      isOnline: true,
    );
  }

  Future<_OnlineStoredProgress?> _readOnlineProgress(String bookId) async {
    final raw = await widget.library.getSetting(
      'online_reading_progress:$bookId',
    );
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map || value['spine'] is! num) return null;
      return (
        spineIndex: (value['spine'] as num).toInt(),
        chapterIdentity: value['chapterIdentity'] as String?,
        finished: value['finished'] == true,
      );
    } on Object {
      // 损坏的在线进度不阻塞书架，回退到普通 EPUB 进度。
      return null;
    }
  }

  int? _onlineChapterIndex(
    OnlineEpubMetadata metadata,
    _OnlineStoredProgress? progress,
  ) {
    if (progress == null) return null;
    final identity = progress.chapterIdentity;
    if (identity != null && identity.isNotEmpty) {
      final match = metadata.chapters.indexWhere(
        (chapter) =>
            onlineChapterIdentity(chapter.toChapter(0, metadata.detailUrl)) ==
            identity,
      );
      if (match >= 0) return match;
    }
    final index = progress.spineIndex;
    return index >= 0 && index < metadata.chapters.length ? index : null;
  }

  Future<int?> _onlineChapterIndexForSpine(
    BookEntry entry,
    OnlineEpubMetadata metadata,
    int? spineIndex,
  ) async {
    if (spineIndex == null) return null;
    try {
      final identity = await metadata.chapterIdentityForSpine(
        widget.library,
        entry,
        spineIndex,
      );
      if (identity == null) return null;
      final match = metadata.chapters.indexWhere(
        (chapter) =>
            onlineChapterIdentity(chapter.toChapter(0, metadata.detailUrl)) ==
            identity,
      );
      return match < 0 ? null : match;
    } on Object {
      return null;
    }
  }

  /// 首批 12 本封面与显示共用缓存，其余封面按需解码。
  Future<void> _preloadCovers() async {
    final items = _items;
    if (items == null || !mounted) return;
    final ordered = _visible(items);
    final generation = ++_coverPreloadGeneration;
    final media = MediaQuery.of(context);
    final width = context.size?.width ?? media.size.width;
    final cardWidth = _grid
        ? _shelfGridMetrics(width, media.textScaler).cardWidth
        : 66.0;
    final cardHeight = _grid ? cardWidth / _shelfCoverAspectRatio : 88.0;
    final decodeWidth = coverDecodeWidth(cardWidth, media.devicePixelRatio);
    final decodeHeight = coverDecodeHeight(cardHeight, media.devicePixelRatio);
    await Future.wait([
      for (final item in ordered.take(12))
        if (item.entry.coverPath case final path?)
          _precacheCover(path, decodeWidth, decodeHeight),
    ]);
    // 图像解码成功后还需让占位组件完成替换，不能只在 Future 完成时揭开书架。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _coverPreloadGeneration) return;
    widget.onInitialCoversReady?.call();
  }

  Future<void> _precacheCover(String path, int decodeWidth, int decodeHeight) =>
      precacheImage(
        coverImageProvider(path, decodeWidth, decodeHeight: decodeHeight),
        context,
        onError: (error, stackTrace) => recordAppError(
          'bookshelf_cover_preload_failed',
          error,
          stackTrace: stackTrace,
        ),
      );

  /// 多选 EPUB/TXT 入队：后台串行导入，UI 不阻塞。
  Future<void> _chooseImport() async {
    if (!widget.allowImport || _pickingFiles || _queue.isBusy) return;
    final choice = await showReaderDrawer<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const AppIcon(AppGlyph.folder),
              title: const Text('从本机导入'),
              subtitle: const Text('选择 EPUB 或 TXT 文件'),
              onTap: () => Navigator.pop(context, 'local'),
            ),
            ListTile(
              leading: const AppIcon(AppGlyph.link),
              title: const Text('从网盘导入'),
              subtitle: const Text('登录网盘，选择书籍下载到书架'),
              onTap: () => Navigator.pop(context, 'cloud'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || !widget.allowImport) return;
    if (choice == 'local') await _import();
    if (choice == 'cloud' && mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CloudImportPage(library: widget.library),
        ),
      );
    }
  }

  Future<void> _import() async {
    if (!widget.allowImport || _pickingFiles || _queue.isBusy) return;
    setState(() => _pickingFiles = true);
    // ignore: avoid_print
    print('[import] 开始选择文件');
    if (mounted) {
      recordAppEvent('book_import_picker_opened');
    }
    List<String> paths;
    try {
      paths = await widget.pickEpubFiles();
    } catch (error) {
      // ignore: avoid_print
      print('[import] 选择文件失败：$error');
      if (mounted) {
        setState(() => _error = '选择文件失败：$error');
      }
      return;
    } finally {
      if (mounted) setState(() => _pickingFiles = false);
    }
    // ignore: avoid_print
    print('[import] 选中 ${paths.length} 个文件');
    if (paths.isEmpty || !mounted || !widget.allowImport) {
      return;
    }
    setState(() {
      _error = null;
      _encodingJob = null;
      _batch.clear();
      _reportedJobs = 0;
    });
    for (final path in paths) {
      try {
        _batch.add(
          _queue.enqueuePath(
            path,
            fallbackTitle: path.split(Platform.pathSeparator).last,
          ),
        );
      } catch (error) {
        if (mounted) {
          setState(() => _error = '读取文件失败：$error');
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _open(BookEntry entry) => _bookOpener.open(context, entry);

  /// 长按卡片：快捷详情面板；可继续进入完整详情页或删除。
  Future<void> _openBookDetail(BookEntry entry) async {
    final sessions =
        widget.library.readingSessionStore()?.list() ??
        Future<List<ReadingSession>>.value(const <ReadingSession>[]);
    final (progress, durations, readingSessions) = await (
      widget.progressStore.load(entry.id),
      widget.library.bookReadingDurations(),
      sessions,
    ).wait;
    if (!mounted) return;
    final reaMicroLink = widget.reaMicro?.links[entry.id];
    final publicLink =
        reaMicroLink != null &&
            reaMicroLink.cloudBookId > 0 &&
            reaMicroLink.publisherId > 0
        ? reaMicroLink
        : null;
    final publisherNameFuture = publicLink?.publisherName.trim().isEmpty == true
        ? widget.reaMicro!.resolveLinkedPublisherName(entry.id)
        : null;
    final onlineSource = widget.onlineBooks?.sourceForBook(entry.id);
    final onlineLink = widget.onlineBooks?.links[entry.id];
    final action = await showReaderBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BookDetailSheet(
        entry: entry,
        library: widget.library,
        onlineSourceName: onlineSource?.name,
        onOpenOnlineSource: onlineSource == null || onlineLink == null
            ? null
            : () {
                final book = onlineLink.bookFor(onlineSource);
                Navigator.of(context).pop();
                unawaited(
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => OnlineBookDetailPage(
                        controller: widget.onlineBooks!,
                        source: onlineSource,
                        book: book,
                        onRead: _bookOpener.openOnline,
                      ),
                    ),
                  ),
                );
              },
        linkedPublisherName: publicLink?.publisherName,
        linkedPublisherNameFuture: publisherNameFuture,
        progress: progress,
        readingDuration: durations[entry.id] ?? Duration.zero,
        readingSessions: readingSessions,
        pinned: _pinnedIds.contains(entry.id),
      ),
    );
    if (!mounted) {
      return;
    }
    await _applyBookAction(entry, action);
  }

  Future<void> _openBookMenu(BookEntry entry, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(position);
    final canRechapter = await TxtBookService(widget.library)
        .canRechapter(entry)
        .catchError((Object _) => false);
    if (!mounted) return;
    final action = await showMenu<String>(
      context: context,
      requestFocus: true,
      position: RelativeRect.fromRect(
        local & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'open', child: Text('开始阅读')),
        if (usesDesktopLayout(context))
          PopupMenuItem(
            value: 'edit',
            enabled:
                widget.library.supportsPersistence &&
                entry.contentRevision != null,
            child: const Text('编辑 EPUB'),
          ),
        const PopupMenuItem(value: 'detail', child: Text('书籍详情')),
        if (widget.onlineBooks?.sourceForBook(entry.id) != null &&
            widget.onlineBooks?.links[entry.id] != null)
          PopupMenuItem(
            value: 'online-source',
            child: Text(
              '在线来源：${widget.onlineBooks!.sourceForBook(entry.id)!.name}',
            ),
          ),
        PopupMenuItem(
          value: 'pin',
          child: Text(_pinnedIds.contains(entry.id) ? '取消置顶' : '置顶'),
        ),
        const PopupMenuItem(value: 'export', child: Text('导出 EPUB')),
        if (canRechapter)
          const PopupMenuItem(value: 'chapters', child: Text('章节正则')),
        const PopupMenuItem(value: 'multi-select', child: Text('选择多本书')),
        const PopupMenuItem(value: 'create-group', child: Text('分组')),
        if (widget.allowImport)
          PopupMenuItem(
            value: 'update',
            child: Text(
              widget.onlineBooks?.sourceForBook(entry.id) != null
                  ? '更新'
                  : '更新 EPUB',
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            '删除本书',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
    if (mounted) await _applyBookAction(entry, action);
  }

  Future<void> _applyBookAction(BookEntry entry, String? action) async {
    if (action == 'online-source') {
      final controller = widget.onlineBooks;
      final source = controller?.sourceForBook(entry.id);
      final link = controller?.links[entry.id];
      if (controller == null || source == null || link == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => OnlineBookDetailPage(
            controller: controller,
            source: source,
            book: link.bookFor(source),
            onRead: _bookOpener.openOnline,
          ),
        ),
      );
      return;
    }
    if (action == 'chapters') {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              TxtChapterRulePage(entry: entry, library: widget.library),
        ),
      );
      if (mounted) await _reload();
      return;
    }
    if (action == 'edit') {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => BookEditorRoute(
            repository: BookEditRepository(widget.library),
            bookId: entry.id,
            sourcePath: entry.filePath,
            contentRevision: entry.contentRevision!,
            title: entry.title,
          ),
        ),
      );
      if (mounted) await _reload();
      return;
    }
    if (action == 'open') {
      await _open(entry);
      return;
    }
    if (action == 'detail') {
      await showReaderDrawer<void>(
        context: context,
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .9,
          child: BookDetailPage(
            entry: entry,
            library: widget.library,
            progressStore: widget.progressStore,
            loadFinishedReview: widget.reaMicro?.loadFinishedReview,
            saveFinishedReview: widget.reaMicro?.saveFinishedReview,
            inDrawer: true,
          ),
        ),
      );
      if (mounted) {
        await _reload();
      }
    } else if (action == 'delete') {
      await _confirmRemove(entry);
    } else if (action == 'update') {
      await _pickBookUpdate(entry);
    } else if (action == 'create-group') {
      await _groupBook(entry);
    } else if (action == 'booklists') {
      await showBookListMembership(
        context,
        library: widget.library,
        bookId: entry.id,
      );
    } else if (action == 'multi-select') {
      _startSelection(entry);
    } else if (action == 'reamicro-link') {
      await _openReaMicroPublicReading(entry);
    } else if (action == 'export') {
      await _exportBook(entry);
    } else if (action == 'pin') {
      await _togglePinned(entry);
    }
  }

  Future<void> _exportBook(BookEntry entry) async {
    if (_exportingBook) return;
    _exportingBook = true;
    final title = entry.title
        .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '_')
        .trim();
    final name = String.fromCharCodes(title.runes.take(64));
    final fileName = '${name.isEmpty ? '未命名书籍' : name}.epub';
    try {
      final saved = await OnlineEpubExport.save(entry, fileName);
      if (mounted) {
        recordAppEvent(
          saved ? 'book_export_completed' : 'book_export_cancelled',
        );
      }
    } on Object catch (error, stackTrace) {
      recordAppError('book_export_failed', error, stackTrace: stackTrace);
    } finally {
      _exportingBook = false;
    }
  }

  Future<void> _openReaMicroPublicReading(BookEntry entry) async {
    final controller = widget.reaMicro;
    if (controller == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('阅微功能暂不可用')));
      return;
    }
    if (!controller.signedIn) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先登录阅微账号')));
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            ReaMicroPublicReadingPage(controller: controller, book: entry),
      ),
    );
  }

  Future<void> _pickBookUpdate(BookEntry entry) async {
    if (!widget.allowImport) return;
    final controller = widget.onlineBooks;
    final source = controller?.sourceForBook(entry.id);
    if (controller != null && source != null) {
      await _updateFromOnlineSource(controller, entry, source);
      return;
    }
    try {
      final paths = await widget.pickEpubFiles();
      if (!mounted || paths.isEmpty || !widget.allowImport) return;
      if (paths.length != 1) {
        recordAppEvent('book_update_requires_single_epub');
        return;
      }
      if (!paths.single.toLowerCase().endsWith('.epub')) {
        recordAppEvent('book_update_requires_epub');
        return;
      }
      setState(() {
        _batch.clear();
        _reportedJobs = 0;
        _error = null;
      });
      _batch.add(_queue.enqueuePath(paths.single, updateBookId: entry.id));
      setState(() {});
    } catch (error, stackTrace) {
      recordAppError('book_update_failed', error, stackTrace: stackTrace);
    }
  }

  Future<void> _updateFromOnlineSource(
    OnlineBookController controller,
    BookEntry entry,
    BookSource source,
  ) async {
    if (!widget.allowImport) return;
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: Text('从 ${source.name} 获取最新章节'),
        content: Text(
          '将检查《${entry.title}》的最新目录；逐章书会下载全本正文，已下载的书只获取新增章节。已有阅读进度、书签与笔记会保留。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('online-update-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('获取最新章节'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final updated = await controller.updateBook(
        entry,
        progressStore: widget.progressStore,
      );
      if (!mounted) return;
      final skipped = controller.lastSkippedChapters;
      final added = controller.lastAddedChapters;
      final message = added == 0
          ? '《${updated.title}》已是最新章节'
          : controller.lastUpdateWasCatalogOnly
          ? '《${updated.title}》目录已更新，新增 $added 章'
          : skipped > 0
          ? '《${updated.title}》已更新，跳过 $skipped 章'
          : '《${updated.title}》已获取 $added 章最新章节';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await _reload();
    } on BookSourceException catch (error) {
      if (!mounted) return;
      final message = error.code == 'ONLINE_CANCELLED'
          ? '已取消更新'
          : '更新失败：${error.message}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新失败：$error')));
    }
  }

  Future<void> _confirmRemove(BookEntry entry) async {
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: Text('删除《${entry.title}》'),
        content: const Text(
          '将删除书籍文件，保留笔记、书评、书单和阅读记录。'
          '已配置同步时会传播到所有设备；仅清理本机副本请使用多设备同步页。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.library.remove(entry.id);
    }
  }

  List<BookEntry> _selectedEntries() => <BookEntry>[
    for (final item in _items ?? const <_ShelfItem>[])
      if (_selectedIds.contains(item.entry.id)) item.entry,
  ];

  Future<void> _confirmBatchRemove() async {
    final entries = _selectedEntries();
    if (entries.isEmpty || _removing) {
      return;
    }
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: Text('删除选中的 ${entries.length} 本书？'),
        content: const Text(
          '将删除书籍文件，保留笔记、书评、书单和阅读记录。'
          '已配置同步时会传播到所有设备；仅清理本机副本请使用多设备同步页。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _removeSelected(entries);
    }
  }

  Future<void> _moveSelectedToGroup() async {
    final entries = _selectedEntries();
    if (entries.isEmpty) {
      return;
    }
    final target =
        await showReaderBottomSheet<
          ({String? groupId, String? name})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _BookGroupSheet(
            summary: '将 ${entries.length} 本书移入分组',
            groups: _groups,
            allowUngroup: true,
            defaultGroupName: _allAsGroup ? _defaultGroupName : null,
          ),
        );
    if (!mounted || target == null) {
      return;
    }
    final ids = <String>[for (final entry in entries) entry.id];
    try {
      final groupId = target.name != null
          ? (await widget.library.createGroup(target.name!)).id
          : target.groupId;
      await widget.library.setBooksGroup(ids, groupId: groupId);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      recordAppEvent('books_group_updated');
    } on LibraryImportException catch (error, stackTrace) {
      recordAppError(
        'books_group_update_failed',
        error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _removeSelected(List<BookEntry> entries) async {
    setState(() => _removing = true);
    var removed = 0;
    final failedIds = <String>[];
    for (final entry in entries) {
      try {
        await widget.library.remove(entry.id);
        removed++;
      } catch (_) {
        failedIds.add(entry.id);
      }
    }
    if (!mounted) {
      return;
    }
    await _reload();
    if (!mounted) return;
    setState(() {
      _removing = false;
      _selectedIds
        ..clear()
        ..addAll(failedIds);
      if (failedIds.isEmpty) {
        _selectionMode = false;
      }
    });
    final message = switch ((removed, failedIds.length)) {
      (0, _) => '删除失败，请稍后重试',
      (_, 0) => '已删除 $removed 本书',
      (final done, final failed) => '已删除 $done 本，$failed 本删除失败',
    };
    if (failedIds.isEmpty) {
      recordAppEvent('books_remove_completed');
    } else {
      recordAppError('books_remove_partial_failure', StateError(message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final busy = _queue.isBusy;
    final visible = items == null
        ? null
        : _visible(items, groupId: _activeGroupId);
    return ExcludeFocus(
      excluding: !widget.active,
      child: Focus(
        focusNode: _keyboardFocus,
        autofocus: widget.active,
        onKeyEvent: _handleShelfKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: usesDesktopLayout(context)
                  ? desktopBookPageMaxWidth
                  : double.infinity,
            ),
            child: LayoutBuilder(
              builder: (_, bounds) => Scaffold(
                appBar: _buildAppBar(busy || _pickingFiles, bounds.maxWidth),
                bottomNavigationBar: _selectionMode
                    ? _buildSelectionBar()
                    : null,
                body: _buildBody(items, visible, busy),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool busy, double width) => bookSearchBar(
    context,
    section: '书架',
    keyPrefix: 'bookshelf',
    availableWidth: width,
    controller: _searchController,
    focusNode: _searchFocus,
    onTap: _focusSearch,
    onSearch: _focusSearch,
    searchLabel: '搜索书架',
    onChanged: (value) => setState(() => _query = value),
    clearButton: !_searching ? null : IconButton(
      tooltip: '关闭搜索', onPressed: _toggleSearch, icon: const AppIcon(AppGlyph.close),
    ),
    actionKey: const ValueKey('bookshelf-import'),
    actionLabel: busy ? '导入中…' : '导入 EPUB / TXT',
    desktopAction: busy ? '导入中…' : '导入书籍',
    onAction: busy || !widget.allowImport ? null : _chooseImport,
    actionIcon: busy ? const SizedBox.square(
      dimension: 18, child: CircularProgressIndicator(strokeWidth: 2),
    ) : const AppIcon(AppGlyph.add),
  );

  Widget _buildShelfControls(List<_ShelfItem> items) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('bookshelf-group-toolbar'),
      children: [
        Expanded(
          child: _ShelfGroupBar(
            groups: _groups,
            activeGroupId: _activeGroupId,
            onToggle: _toggleGroup,
            onShowAll: () => setState(() => _activeGroupId = null),
            onManage: _manageGroup,
            allAsGroup: _allAsGroup,
            defaultGroupName: _defaultGroupName,
            onManageDefault: () => _manageGroup(null),
          ),
        ),
        if (_selectionMode)
          IconButton(
            key: const ValueKey('bookshelf-select-all'),
            tooltip: _allSelected(items) ? '取消全选' : '全选',
            onPressed: _removing ? null : () => _toggleSelectAll(items),
            icon: AppIcon(
              _allSelected(items) ? AppGlyph.check : AppGlyph.multiSelect,
              strokeWidth: _shelfToolbarIconStroke,
            ),
          ),
        if (!_selectionMode)
          Theme(
            data: _noFeedback(context),
            child: IconButton(
              key: const ValueKey('bookshelf-view-style'),
              tooltip: _grid ? '列表视图' : '网格视图',
              color: colors.onSurfaceVariant,
              disabledColor: Theme.of(context).disabledColor,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              padding: EdgeInsets.zero,
              onPressed: _toggleView,
              icon: AppIcon(
                _grid ? AppGlyph.listView : AppGlyph.gridView,
                strokeWidth: _shelfToolbarIconStroke,
              ),
            ),
          ),
        Theme(
          data: _noFeedback(context),
          child: IconButton(
            key: const ValueKey('bookshelf-multi-select'),
            tooltip: _selectionMode ? '退出多选' : '多选',
            color: colors.onSurfaceVariant,
            disabledColor: Theme.of(context).disabledColor,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            padding: EdgeInsets.zero,
            onPressed: _removing
                ? null
                : _selectionMode
                ? _exitSelectionMode
                : items.isEmpty
                ? null
                : _startSelection,
            icon: AppIcon(
              _selectionMode ? AppGlyph.close : AppGlyph.multiSelect,
              strokeWidth: _shelfToolbarIconStroke,
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody(
    List<_ShelfItem>? items,
    List<_ShelfItem>? visible,
    bool busy,
  ) {
    final canSwipe =
        !_selectionMode &&
        _error == null &&
        items != null &&
        _groups.isNotEmpty;
    return Column(
      children: [
        if (busy)
          _ImportBanner(
            queue: _queue,
            onCancel: () {
              final job = _queue.activeJob;
              if (job != null) {
                _queue.cancel(job.id);
              }
            },
          ),
        if (_error == null && visible != null) _buildShelfControls(visible),
        Expanded(
          child: _ShelfGroupPages(
            groupIds: [null, for (final group in _groups) group.id],
            groupId: _activeGroupId,
            enabled: canSwipe,
            onChanged: (id) => setState(() => _activeGroupId = id),
            builder: (id) => _ShelfBodyTransition(
              groupId: id,
              groupIndex: 0,
              grid: _grid,
              animate: !_selectionMode && _error == null && items != null,
              child: _buildLibraryBody(
                items,
                id == _activeGroupId
                    ? visible
                    : items == null
                    ? null
                    : _visible(items, groupId: id),
                groupId: id,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryBody(
    List<_ShelfItem>? items,
    List<_ShelfItem>? visible, {
    String? groupId,
  }) {
    if (_error != null) {
      return _ErrorPane(
        message: _error!,
        retryLabel: _encodingJob == null ? '重试' : '选择编码并重试',
        onRetry: !widget.allowImport
            ? null
            : _encodingJob == null
            ? _import
            : _retryEncoding,
      );
    }
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return _EmptyPane(allowImport: widget.allowImport);
    }
    final books = visible!;
    if (books.isEmpty) {
      return _NoMatchesPane(
        query: _query.trim(),
        groupName: groupId == null
            ? (_allAsGroup ? _defaultGroupName : null)
            : _groups.where((group) => group.id == groupId).firstOrNull?.name,
        onReset: _allAsGroup && _query.trim().isEmpty ? null : _resetFilters,
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        final online = widget.onlineBooks;
        if (online != null) {
          await online.refreshShelfOnlineUpdates();
        }
        await _reload();
      },
      child: _grid ? _buildBookGrid(books) : _buildBookList(books),
    );
  }

  Widget _buildBookGrid(List<_ShelfItem> books) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          key: const ValueKey<String>('bookshelf-grid'),
          padding: EdgeInsets.fromLTRB(
            _shelfGridPadding,
            4,
            _shelfGridPadding,
            _selectionMode ? 160 : 96,
          ),
          gridDelegate: _shelfGridMetrics(
            constraints.maxWidth,
            MediaQuery.textScalerOf(context),
          ).delegate,
          itemCount: books.length,
          itemBuilder: (context, index) {
            final item = books[index];
            final pinned = _pinnedIds.contains(item.entry.id);
            return _desktopBook(
              _BookCard(
                entry: item.entry,
                pinned: pinned,
                isOnline: item.isOnline,
                showTitle: _gridShowTitles,
                selectionMode: _selectionMode,
                selected: _selectedIds.contains(item.entry.id),
                onSelect: () => _activateBook(item.entry, books),
                onOpen: (entry) => _activateBook(entry, books),
                onLongPress: _openBookDetail,
                onSecondaryTap: (position) =>
                    _openBookMenu(item.entry, position),
              ),
              item.entry,
              books,
            );
          },
        );
      },
    );
  }

  ({SliverGridDelegateWithFixedCrossAxisCount delegate, double cardWidth})
  _shelfGridMetrics(double width, TextScaler textScaler) {
    final desktop = usesDesktopLayout(context);
    if (desktop) width = math.min(width, desktopBookPageMaxWidth);
    final available = width - _shelfGridPadding * 2;
    // 桌面以封面上限增列，避免向下取整后把多余空间重新放大到封面。
    final columns = desktop
        ? math.max(
            1,
            ((available + _shelfGridSpacing) /
                    (_desktopShelfCoverWidth + _shelfGridSpacing))
                .ceil(),
          )
        : math.max(
            _shelfMinColumns,
            (available + _shelfGridSpacing) ~/
                (_shelfTargetCardWidth + _shelfGridSpacing),
          );
    final cardWidth = (available - _shelfGridSpacing * (columns - 1)) / columns;
    return (
      delegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent:
            cardWidth / _shelfCoverAspectRatio +
            (_gridShowTitles
                ? _shelfTitleGap + textScaler.scale(_shelfTitleHeight)
                : 0),
        mainAxisSpacing: 20,
        crossAxisSpacing: _shelfGridSpacing,
      ),
      cardWidth: cardWidth,
    );
  }

  Widget _buildBookList(List<_ShelfItem> books) {
    return LayoutBuilder(
      builder: (_, bounds) {
        final inset = usesDesktopLayout(context)
            ? math.max(16.0, (bounds.maxWidth - _desktopShelfListWidth) / 2)
            : 16.0;
        return ListView.separated(
          key: const ValueKey<String>('bookshelf-list'),
          padding: EdgeInsets.fromLTRB(
            inset,
            8,
            inset,
            _selectionMode ? 160 : 96,
          ),
          itemCount: books.length,
          separatorBuilder: (_, _) => SizedBox(
            height: 1,
            child: _listDividers ? const Divider(height: 1) : null,
          ),
          itemBuilder: (context, index) {
            final item = books[index];
            return _desktopBook(
              _BookRow(
                item: item,
                pinned: _pinnedIds.contains(item.entry.id),
                showTitle: true,
                isOnline: item.isOnline,
                finished: _finishedBooks.contains(item.entry.id),
                onlineUpdate: _onlineUpdates[item.entry.id],
                selectionMode: _selectionMode,
                selected: _selectedIds.contains(item.entry.id),
                onSelect: () => _activateBook(item.entry, books),
                onOpen: (entry) => _activateBook(entry, books),
                onLongPress: _openBookDetail,
                onSecondaryTap: (position) =>
                    _openBookMenu(item.entry, position),
              ),
              item.entry,
              books,
            );
          },
        );
      },
    );
  }

  Widget _buildSelectionBar() {
    final theme = Theme.of(context);
    final count = _selectedIds.length;
    final buttons = [
      OutlinedButton.icon(
        key: const ValueKey('bookshelf-batch-create-group'),
        onPressed: count == 0 || _removing
            ? null
            : () => _createGroup(initialBookIds: Set<String>.of(_selectedIds)),
        icon: const AppIcon(AppGlyph.folderAdd, size: 18),
        label: const Text('新建分组'),
      ),
      OutlinedButton.icon(
        key: const ValueKey('bookshelf-batch-group'),
        onPressed: count == 0 || _removing ? null : _moveSelectedToGroup,
        icon: const AppIcon(AppGlyph.folderMove, size: 18),
        label: const Text('分组'),
      ),
      OutlinedButton.icon(
        key: const ValueKey('bookshelf-batch-delete'),
        onPressed: count == 0 || _removing ? null : _confirmBatchRemove,
        icon: _removing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const AppIcon(AppGlyph.delete, size: 18),
        label: Text(_removing ? '删除中' : '删除'),
      ),
    ];
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: OutlinedButtonTheme(
            data: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                minimumSize: const Size(0, 44),
                visualDensity: VisualDensity.standard,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            child: LayoutBuilder(
              builder: (_, bounds) {
                final desktop = usesDesktopLayout(context);
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final wide = desktop && bounds.maxWidth >= 640 * scale;
                final countLabel = Text(
                  count == 0 ? '请选择书籍' : '已选 $count 本',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
                if (wide) {
                  return Row(
                    children: [
                      countLabel,
                      const Spacer(),
                      for (final button in buttons)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: button,
                        ),
                    ],
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    countLabel,
                    const SizedBox(height: 8),
                    if (bounds.maxWidth >= 300 * scale)
                      Row(
                        children: [
                          for (final (index, button) in buttons.indexed) ...[
                            if (index > 0) const SizedBox(width: 8),
                            Expanded(child: button),
                          ],
                        ],
                      )
                    else
                      Wrap(spacing: 8, runSpacing: 8, children: buttons),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 分组整页随手势平移，松手后补完切换或回到原位。
class _ShelfGroupPages extends StatefulWidget {
  const _ShelfGroupPages({
    required this.groupIds,
    required this.groupId,
    required this.enabled,
    required this.onChanged,
    required this.builder,
  });

  final List<String?> groupIds;
  final String? groupId;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  final Widget Function(String?) builder;

  @override
  State<_ShelfGroupPages> createState() => _ShelfGroupPagesState();
}

class _ShelfGroupPagesState extends State<_ShelfGroupPages>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late String? _displayId;
  final _offset = ValueNotifier<double>(0);
  double _from = 0;
  double _to = 0;
  double _distance = 0;
  double _width = 1;
  int _direction = 0;
  int? _targetIndex;

  @override
  void initState() {
    super.initState();
    _displayId = widget.groupId;
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          final t = Curves.easeOutCubic.transform(_controller.value);
          _offset.value = _from + (_to - _from) * t;
        });
  }

  @override
  void didUpdateWidget(_ShelfGroupPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled ||
        !listEquals(oldWidget.groupIds, widget.groupIds) ||
        !widget.groupIds.contains(_displayId)) {
      _controller.stop();
      _displayId = widget.groupId;
      _offset.value = 0;
      _direction = 0;
      _targetIndex = null;
    } else if (oldWidget.groupId != widget.groupId &&
        _displayId != widget.groupId) {
      _controller.stop();
      final previous = widget.groupIds.indexOf(_displayId);
      final next = widget.groupIds.indexOf(widget.groupId);
      _direction = (next - previous).sign;
      _offset.value = 0;
      _settle(true, targetIndex: next);
    }
  }

  int get _neighborIndex => widget.groupIds.indexOf(_displayId) + _direction;

  void _dragUpdate(DragUpdateDetails details) {
    if (_controller.isAnimating) return;
    _distance += details.primaryDelta ?? 0;
    final direction = _distance < 0 ? 1 : -1;
    final next = widget.groupIds.indexOf(_displayId) + direction;
    final nextDirection = next >= 0 && next < widget.groupIds.length
        ? direction
        : 0;
    if (_direction != nextDirection) {
      setState(() => _direction = nextDirection);
    }
    _offset.value = _direction == 0 ? 0 : (_distance / _width).clamp(-1.0, 1.0);
  }

  void _dragEnd(DragEndDetails details) {
    if (_controller.isAnimating) return;
    final velocity = details.primaryVelocity ?? 0;
    final commit =
        _direction != 0 &&
        (_distance.abs() >= 48 ||
            (_distance.abs() >= 20 && velocity.abs() >= 400));
    _settle(commit);
  }

  Future<void> _settle(bool commit, {int? targetIndex}) async {
    _targetIndex = targetIndex;
    final target = commit
        ? widget.groupIds[targetIndex ?? _neighborIndex]
        : _displayId;
    _from = _offset.value;
    _to = commit ? -_direction.toDouble() : 0;
    if (!MediaQuery.disableAnimationsOf(context) && _from != _to) {
      try {
        await _controller.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _displayId = target;
      _offset.value = 0;
      _direction = 0;
    });
    if (commit && widget.groupId != target) widget.onChanged(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth;
      Widget page(String? id, double offset, {required bool active}) =>
          AnimatedBuilder(
            key: ValueKey(('bookshelf-group-page', id)),
            animation: _offset,
            builder: (_, child) => FractionalTranslation(
              translation: Offset(_offset.value + offset, 0),
              child: child,
            ),
            // 手势和补间只更新平移；筛选、封面构建与绘制复用本次页面。
            child: ExcludeFocus(
              excluding: !active,
              child: ExcludeSemantics(
                excluding: !active,
                child: IgnorePointer(
                  ignoring: !active,
                  child: HeroMode(
                    enabled: active,
                    child: RepaintBoundary(child: widget.builder(id)),
                  ),
                ),
              ),
            ),
          );
      return GestureDetector(
        key: const ValueKey('bookshelf-group-pages'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: widget.enabled
            ? (_) {
                if (!_controller.isAnimating) {
                  _distance = 0;
                  _targetIndex = null;
                }
              }
            : null,
        onHorizontalDragUpdate: widget.enabled ? _dragUpdate : null,
        onHorizontalDragEnd: widget.enabled ? _dragEnd : null,
        onHorizontalDragCancel: widget.enabled
            ? () {
                if (!_controller.isAnimating) _settle(false);
              }
            : null,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              page(_displayId, 0, active: _direction == 0),
              if (_direction != 0)
                page(
                  widget.groupIds[_targetIndex ?? _neighborIndex],
                  _direction.toDouble(),
                  active: false,
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// 网格与列表视图切换保持轻微纵移淡入。
class _ShelfBodyTransition extends StatefulWidget {
  const _ShelfBodyTransition({
    required this.groupId,
    required this.groupIndex,
    required this.grid,
    required this.animate,
    required this.child,
  });

  final String? groupId;
  final int groupIndex;
  final bool grid;
  final bool animate;
  final Widget child;

  @override
  State<_ShelfBodyTransition> createState() => _ShelfBodyTransitionState();
}

class _ShelfBodyTransitionState extends State<_ShelfBodyTransition> {
  double _groupDirection = 0;
  double _viewDirection = 0;

  @override
  void didUpdateWidget(_ShelfBodyTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId || oldWidget.grid != widget.grid) {
      _groupDirection = (widget.groupIndex - oldWidget.groupIndex).sign
          .toDouble();
      _viewDirection = oldWidget.grid == widget.grid
          ? 0
          : widget.grid
          ? -1
          : 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.animate && !MediaQuery.disableAnimationsOf(context);
    final key = ValueKey((widget.groupId, widget.grid));
    return ClipRect(
      child: AnimatedSwitcher(
        duration: animate ? const Duration(milliseconds: 200) : Duration.zero,
        // 旧条目创建于加载期也保留退出时长，减少动态效果时不展示旧层。
        reverseDuration: const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        layoutBuilder: (current, previous) =>
            _layoutLayers(current, animate ? previous : const []),
        transitionBuilder: (child, animation) =>
            _transitionContent(child, animation, key),
        child: KeyedSubtree(key: key, child: widget.child),
      ),
    );
  }

  Widget _transitionContent(
    Widget child,
    Animation<double> animation,
    Key currentKey,
  ) {
    final page = RepaintBoundary(child: child);
    final direction = child.key == currentKey
        ? _groupDirection
        : -_groupDirection;
    final viewDirection = child.key == currentKey
        ? _viewDirection
        : -_viewDirection;
    final content = direction == 0
        ? AnimatedBuilder(
            animation: animation,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, viewDirection * 12 * (1 - animation.value)),
              child: child,
            ),
            child: page,
          )
        : SlideTransition(
            position: Tween(
              begin: Offset(direction * .1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: page,
          );
    return FadeTransition(opacity: animation, child: content);
  }

  Widget _layoutLayers(Widget? current, List<Widget> previous) => Stack(
    fit: StackFit.expand,
    children: [
      for (final child in previous)
        ExcludeFocus(
          child: ExcludeSemantics(
            child: IgnorePointer(child: HeroMode(enabled: false, child: child)),
          ),
        ),
      ?current,
    ],
  );
}

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      Navigator.of(context).pop(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReaderFrostedAlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey<String>('bookshelf-group-name-field'),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: '分组名称',
          hintText: '例如：小说、待读',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey<String>('bookshelf-group-name-confirm'),
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _BookGroupSheet extends StatefulWidget {
  const _BookGroupSheet({
    required this.summary,
    required this.groups,
    this.currentGroupId,
    this.defaultGroupName,
    this.allowUngroup = false,
  });

  final String summary;
  final List<ShelfGroup> groups;
  final String? currentGroupId;
  final String? defaultGroupName;
  final bool allowUngroup;

  @override
  State<_BookGroupSheet> createState() => _BookGroupSheetState();
}

class _BookGroupSheetState extends State<_BookGroupSheet> {
  final _controller = TextEditingController();
  late bool _creating = widget.groups.isEmpty && widget.defaultGroupName == null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _create() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((groupId: null, name: name));
  }

  Widget _createForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: const ValueKey('bookshelf-group-create-name'),
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: '分组名称',
          hintText: '例如：小说、待读',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _create(),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            key: const ValueKey('bookshelf-group-create-confirm'),
            onPressed: _controller.text.trim().isEmpty ? null : _create,
            child: const Text('创建并移入'),
          ),
        ],
      ),
    ],
  );

  Widget _groupOptions() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.defaultGroupName case final defaultName?)
        ListTile(
          key: const ValueKey('bookshelf-group-pick-default'),
          contentPadding: EdgeInsets.zero,
          leading: const AppIcon(AppGlyph.folder),
          title: Text(defaultName),
          subtitle: !widget.allowUngroup && widget.currentGroupId == null
              ? const Text('当前分组')
              : null,
          onTap: () => Navigator.of(context).pop((groupId: null, name: null)),
        ),
      for (final group in widget.groups)
        ListTile(
          key: ValueKey('bookshelf-book-group-${group.id}'),
          contentPadding: EdgeInsets.zero,
          leading: const AppIcon(AppGlyph.folder),
          title: Text(group.name),
          subtitle: group.id == widget.currentGroupId
              ? const Text('当前分组')
              : null,
          onTap: () =>
              Navigator.of(context)
                  .pop((groupId: group.id, name: null)),
        ),
      if (widget.allowUngroup && widget.defaultGroupName == null)
        ListTile(
          key: const ValueKey('bookshelf-group-pick-none'),
          contentPadding: EdgeInsets.zero,
          leading: const AppIcon(AppGlyph.folderOff),
          title: const Text('移出分组'),
          onTap: () =>
              Navigator.of(context)
                  .pop((groupId: null, name: null)),
        ),
      const Divider(),
      ListTile(
        key: const ValueKey('bookshelf-book-group-new'),
        contentPadding: EdgeInsets.zero,
        leading: const AppIcon(AppGlyph.folderAdd),
        title: const Text('新建分组'),
        onTap: () => setState(() => _creating = true),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        key: const ValueKey('bookshelf-book-group-sheet'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('图书分组', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                widget.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              if (_creating) _createForm() else _groupOptions(),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ShelfGroupBar extends StatelessWidget {
  const _ShelfGroupBar({
    required this.groups,
    required this.activeGroupId,
    required this.onToggle,
    required this.onShowAll,
    required this.onManage,
    required this.allAsGroup,
    required this.defaultGroupName,
    required this.onManageDefault,
  });

  final List<ShelfGroup> groups;
  final String? activeGroupId;
  final ValueChanged<String> onToggle;
  final VoidCallback onShowAll;
  final ValueChanged<ShelfGroup> onManage;
  final bool allAsGroup;
  final String defaultGroupName;
  final VoidCallback onManageDefault;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            _ShelfGroupTab(
              key: const ValueKey<String>('bookshelf-group-all'),
              label: allAsGroup ? defaultGroupName : '全部',
              selected: activeGroupId == null,
              onTap: onShowAll,
              onLongPress: allAsGroup ? onManageDefault : null,
            ),
            for (final group in groups)
              _ShelfGroupTab(
                key: ValueKey<String>('bookshelf-group-${group.id}'),
                label: group.name,
                selected: group.id == activeGroupId,
                onTap: () => onToggle(group.id),
                onLongPress: () => onManage(group),
              ),
          ],
        ),
      ),
    );
  }
}

/// 分组采用文字页签，让书封面成为书架的视觉重点。
class _ShelfGroupTab extends StatefulWidget {
  const _ShelfGroupTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_ShelfGroupTab> createState() => _ShelfGroupTabState();
}

class _ShelfGroupTabState extends State<_ShelfGroupTab> {
  @override
  void didUpdateWidget(_ShelfGroupTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            alignment: .5,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: widget.selected,
      button: true,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          margin: const EdgeInsets.only(right: 20),
          height: 44,
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: widget.selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// 导入进度条：当前任务名 + 进度 + 取消（P4-03）。
class _ImportBanner extends StatelessWidget {
  const _ImportBanner({required this.queue, required this.onCancel});

  final ImportQueue queue;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final job = queue.activeJob;
    final theme = Theme.of(context);
    final label = job == null
        ? '等待导入（排队 ${queue.pendingCount} 本）'
        : '正在导入：${job.fallbackTitle ?? '书籍'}'
              '${queue.pendingCount > 0 ? '（排队 ${queue.pendingCount} 本）' : ''}';
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: job?.progress),
                ],
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('取消')),
          ],
        ),
      ),
    );
  }
}

/// 列表中的封面、书名与阅读记录。
class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.item,
    required this.pinned,
    required this.showTitle,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onLongPress,
    required this.onSecondaryTap,
    this.onlineUpdate,
    this.isOnline = false,
    this.finished = false,
  });

  final _ShelfItem item;
  final bool pinned;
  final bool showTitle;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final Future<void> Function(BookEntry) onOpen;
  final Future<void> Function(BookEntry) onLongPress;
  final ValueChanged<Offset> onSecondaryTap;
  final Map<String, Object?>? onlineUpdate;
  final bool isOnline;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = item.entry;
    final author = entry.author.trim();
    final metadataStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cover = Hero(
      tag: bookCoverHeroTag(entry.id),
      transitionOnUserGestures: true,
      child: BookCoverImage(
        key: const ValueKey<String>('book-row-cover'),
        book: entry,
        width: 66,
        height: 88,
        showShadow: true,
        shadowOpacity: pinned ? _pinnedCoverShadowOpacity : .12,
      ),
    );
    final trailing = <Widget>[
      if (!isOnline && entry.readabilityLevel >= 2)
        Tooltip(
          message: entry.readabilityLevel >= 3
              ? '结构异常：进度与目录可能不可靠'
              : '部分内容降级：目录或资源缺失',
          child: AppIcon(
            AppGlyph.warning,
            color: theme.colorScheme.error,
            size: 18,
          ),
        ),
      if (selectionMode)
        Checkbox(
          key: ValueKey<String>('book-row-check-${entry.id}'),
          value: selected,
          onChanged: (_) => onSelect(),
          visualDensity: VisualDensity.compact,
        ),
    ];
    return Semantics(
      selected: selectionMode && selected,
      child: InkWell(
        key: ValueKey<String>('book-row-${entry.id}'),
        canRequestFocus: !usesDesktopLayout(context),
        overlayColor: _bookPressOverlay,
        onTap: () {
          if (selectionMode) {
            onSelect();
          } else {
            onOpen(entry);
          }
        },
        onLongPress: () {
          if (selectionMode) {
            onSelect();
          } else {
            onLongPress(entry);
          }
        },
        onSecondaryTapUp: selectionMode
            ? null
            : (details) => onSecondaryTap(details.globalPosition),
        child: Ink(
          color: selectionMode && selected
              ? theme.colorScheme.surfaceContainerLow
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              cover,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (showTitle) ...[
                      Text(
                        entry.title,
                        key: ValueKey<String>('book-row-title-${entry.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      author.isEmpty ? '未知作者' : author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metadataStyle,
                    ),
                    if (isOnline && !finished) ...[
                      Text(
                        '已读 ${formatReadingDuration(item.duration)} · ${_readingChapterCount(item.onlineSpineIndex, item.onlineSpineCount)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metadataStyle,
                      ),
                      Text(
                        _onlineUpdateLabel(onlineUpdate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metadataStyle,
                      ),
                    ] else if (isOnline && finished) ...[
                      Text(
                        '已读 ${formatReadingDuration(item.duration)}',
                        style: metadataStyle,
                      ),
                      Text(
                        formatReadingChapters(
                          item.onlineSpineIndex,
                          item.onlineSpineCount,
                        ),
                        style: metadataStyle,
                      ),
                    ] else ...[
                      Text(
                        '已读 ${formatReadingDuration(item.duration)}',
                        style: metadataStyle,
                      ),
                      Text(
                        formatReadingChapters(
                          item.spineIndex,
                          entry.spineCount,
                        ),
                        style: metadataStyle,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                ...trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _onlineUpdateLabel(Map<String, Object?>? update) {
    if (update == null) return '尚未检查更新 · 最新章节未知';
    final millis = update['updatedAt'] as int?;
    final title = (update['latestChapter'] as String? ?? '').trim();
    final elapsed = millis == null
        ? '更新时间未知'
        : _relativeShelfTime(DateTime.fromMillisecondsSinceEpoch(millis));
    return '$elapsed · ${title.isEmpty ? '最新章节未知' : title}';
  }
}

String _relativeShelfTime(DateTime date) {
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inDays >= 1) return '${elapsed.inDays} 天前';
  if (elapsed.inHours >= 1) return '${elapsed.inHours} 小时前';
  return '${math.max(1, elapsed.inMinutes)} 分钟前';
}

String _readingChapterCount(int? spineIndex, int? spineCount) {
  final total = spineCount ?? 0;
  final current = ((spineIndex ?? -1) + 1).clamp(0, total);
  return '$current/$total 章';
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.allowImport});

  final bool allowImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(
            AppGlyph.bookshelf,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            allowImport ? '书架还是空的' : '书库暂时不可用',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            allowImport ? '点击右上角导入按钮添加第一本书' : '请先重试本地数据库，恢复后再导入书籍',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NoMatchesPane extends StatelessWidget {
  const _NoMatchesPane({
    required this.query,
    required this.onReset,
    this.groupName,
  });

  final String query;
  final VoidCallback? onReset;
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              AppGlyph.searchOff,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              query.isNotEmpty
                  ? '没有找到相关书籍'
                  : groupName == null
                  ? '没有符合筛选条件的书'
                  : '这个分组还没有书',
              style: theme.textTheme.titleMedium,
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '没有书名或作者包含“$query”',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ] else if (groupName != null) ...[
              const SizedBox(height: 4),
              Text(
                '在其他分组选择书籍，再移入「$groupName」',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (onReset != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onReset,
                icon: const AppIcon(AppGlyph.filterOff),
                label: Text(query.isNotEmpty || groupName == null ? '清除筛选' : '查看全部书籍'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.message,
    required this.onRetry,
    this.retryLabel = '重试',
  });

  final String message;
  final Future<void> Function()? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              AppGlyph.error,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.entry,
    required this.isOnline,
    required this.pinned,
    required this.showTitle,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onLongPress,
    required this.onSecondaryTap,
  });

  final BookEntry entry;
  final bool isOnline;
  final bool pinned;
  final bool showTitle;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final Future<void> Function(BookEntry) onOpen;
  final Future<void> Function(BookEntry) onLongPress;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = Hero(
      tag: bookCoverHeroTag(entry.id),
      transitionOnUserGestures: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BookCoverImage(
            book: entry,
            showShadow: true,
            shadowOpacity: pinned ? _pinnedCoverShadowOpacity : .12,
          ),
          if (selectionMode)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: selected
                      ? theme.colorScheme.primary.withAlpha(36)
                      : Colors.transparent,
                ),
              ),
            ),
          if (selectionMode)
            Positioned(
              top: 6,
              left: 6,
              child: _BookSelectionMark(
                key: ValueKey<String>('book-selected-${entry.id}'),
                selected: selected,
              ),
            ),
        ],
      ),
    );
    return InkWell(
      key: ValueKey<String>('book-card-${entry.id}'),
      canRequestFocus: !usesDesktopLayout(context),
      borderRadius: BorderRadius.circular(4),
      overlayColor: _bookPressOverlay,
      onTap: () {
        if (selectionMode) {
          onSelect();
        } else {
          onOpen(entry);
        }
      },
      onLongPress: () {
        if (selectionMode) {
          onSelect();
        } else {
          onLongPress(entry);
        }
      },
      onSecondaryTapUp: selectionMode
          ? null
          : (details) => onSecondaryTap(details.globalPosition),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            key: const ValueKey<String>('book-card-cover'),
            aspectRatio: _shelfCoverAspectRatio,
            child: cover,
          ),
          if (showTitle) ...[
            const SizedBox(height: _shelfTitleGap),
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(_shelfTitleHeight),
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  entry.title,
                  key: ValueKey<String>('book-card-title-${entry.id}'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selectionMode && selected
                        ? theme.colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BookSelectionMark extends StatelessWidget {
  const _BookSelectionMark({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      label: selected ? '已选择' : '未选择',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surface.withAlpha(232),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        ),
        child: selected
            ? AppIcon(
                AppGlyph.check,
                size: 18,
                color: theme.colorScheme.onPrimary,
              )
            : null,
      ),
    );
  }
}
