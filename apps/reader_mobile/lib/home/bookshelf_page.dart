import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/annotations/text_value_dialog.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';
import 'package:reader_ui/theme/reader_ink.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'package:reader_core/epub/importer.dart';

import '../library/library_store.dart';
import '../reader/book_opener.dart';
import '../reader/reader_text_warmup.dart';
import '../editing/book_edit_repository.dart';
import '../editing/book_editor_route.dart';
import '../editing/epub_export.dart';
import '../txt/txt_book_service.dart';
import '../txt/txt_chapter_rule_page.dart';
import '../txt/txt_encoding_dialog.dart';
import 'desktop_layout.dart';
import 'desktop_book_interaction.dart';
import 'book_detail_page.dart';
import 'book_detail_sheet.dart';
import 'book_lists_view.dart';
import 'bookshelf_sort.dart';
import 'book_cover_image.dart';
import 'book_cover_stack.dart';
import 'book_stack_tile.dart';
import 'bookshelf_stacks.dart';
import 'tag_stack_settings_sheet.dart';
import 'horizontal_page_switcher.dart';
import '../storage/import_queue.dart';
import '../storage/reading_session_store.dart';
import '../diagnostics/reader_log.dart';
import '../cloud/cloud_import_page.dart';

/// 书架条目及列表显示的阅读记录。
typedef _ShelfItem = ({
  BookEntry entry,
  int? spineIndex,
  String? chapterTitle,
  double readingPercent,
});

const _shelfMinColumns = 3;
const _shelfTargetCardWidth = 192.0;
const _desktopShelfMaxWidth = 1440.0;
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

ThemeData _noFeedback(BuildContext context) {
  final theme = Theme.of(context);
  return usesDesktopLayout(context)
      ? theme.copyWith(
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        )
      : quietInk(theme);
}

/// 书架页：书籍网格/列表、EPUB 与 TXT 导入、点击进入阅读、长按看详情。
class BookshelfPage extends StatefulWidget {
  /// 创建页面。
  const BookshelfPage({
    super.key,
    required this.library,
    required this.progressStore,
    this.refreshToken = 0,
    this.allowImport = true,
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
  BookSortOrder _sort = BookSortOrder.recent;
  bool _newBooksFirst = true;
  List<String> _pinnedIds = const <String>[];
  List<ShelfGroup> _groups = const <ShelfGroup>[];
  List<String?> _groupOrder = const [];
  Map<String, String> _bookGroups = const <String, String>{};
  List<BookTag> _tags = const [];
  Map<String, Set<String>> _bookTags = const {};
  Map<String, List<String>> _stackTags = const {};
  BookTag? _expandedStack;
  String? _activeGroupId;
  bool _grid = true;
  bool _showTitles = true;
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
    _bookOpener = BookOpener(
      library: widget.library,
      progressStore: widget.progressStore,
    );
    _queue = ImportQueue(widget.library, readFile: widget.readFile)
      ..addListener(_onQueueChanged);
    // 首次加载先等偏好读完，避免书架的排序、置顶和视图在显示后再变一次。
    _preferences = _loadPreferences();
    _reload();
  }

  @override
  void didUpdateWidget(BookshelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      if (!_selectionMode && !_searching && _expandedStack != null)
        const SingleActivator(
          LogicalKeyboardKey.escape,
          includeRepeats: false,
        ): () =>
            setState(() => _expandedStack = null),
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

  /// 读持久化的排序、视图模式与书名显示（settings 表）。
  Future<void> _loadPreferences() async {
    final sort = await widget.library.getSetting(bookshelfSortKey);
    final newBooksFirst = await widget.library.getSetting(
      bookshelfNewBooksFirstKey,
    );
    final grid = await widget.library.getSetting(_viewKey);
    final pinned = await widget.library.getSetting(_pinnedKey);
    final showTitles = await widget.library.getSetting(bookshelfShowTitlesKey);
    final order = await widget.library.getSetting(bookshelfGroupOrderKey);
    List<String?> nextOrder = const [];
    try {
      final decoded = order == null ? null : jsonDecode(order);
      if (decoded is List) nextOrder = decoded.whereType<String?>().toList();
    } on FormatException {
      nextOrder = const [];
    }
    final stackTags = await widget.library.getSetting(bookshelfTagStacksKey);
    final nextStackTags = stackTags == null
        ? <String, List<String>>{}
        : (jsonDecode(stackTags) as Map<String, dynamic>).map(
            (key, value) => MapEntry(key, (value as List).cast<String>()),
          );
    if (!mounted) {
      return;
    }
    final nextSort = BookSortOrder.fromValue(sort);
    final nextNewBooksFirst = newBooksFirst != 'false';
    final nextGrid = grid != 'false';
    final nextShowTitles = showTitles != 'false';
    final nextPinned = pinned == null
        ? const <String>[]
        : (jsonDecode(pinned) as List).cast<String>();
    if (_sort == nextSort &&
        _newBooksFirst == nextNewBooksFirst &&
        _grid == nextGrid &&
        _showTitles == nextShowTitles &&
        listEquals(_groupOrder, nextOrder) &&
        _stackTags.length == nextStackTags.length &&
        nextStackTags.entries.every(
          (entry) => listEquals(_stackTags[entry.key], entry.value),
        ) &&
        listEquals(_pinnedIds, nextPinned)) {
      return;
    }
    setState(() {
      _sort = nextSort;
      _newBooksFirst = nextNewBooksFirst;
      _grid = nextGrid;
      _showTitles = nextShowTitles;
      _groupOrder = nextOrder;
      _pinnedIds = nextPinned;
      _stackTags = nextStackTags;
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

  void _selectGroup(String? id) => setState(() {
    _activeGroupId = id;
    _expandedStack = null;
  });

  List<String?> get _orderedGroupIds {
    final remaining = <String?>{null, for (final group in _groups) group.id};
    return [
      for (final id in _groupOrder)
        if (remaining.remove(id)) id,
      ...remaining,
    ];
  }

  Future<void> _reorderGroups(int oldIndex, int newIndex) async {
    final ids = _orderedGroupIds;
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    setState(() => _groupOrder = ids);
    await widget.library.setSetting(bookshelfGroupOrderKey, jsonEncode(ids));
  }

  Future<void> _configureTagStacks() async {
    final groupId = _activeGroupId;
    final groupName =
        _groups.where((group) => group.id == groupId).firstOrNull?.name ??
        '默认分组';
    final counts = <String, int>{};
    for (final item in _items ?? <_ShelfItem>[]) {
      if (_bookGroups[item.entry.id] != groupId) continue;
      for (final tag in _bookTags[item.entry.id] ?? <String>{}) {
        counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final selected = _stackTags[groupId ?? 'default'] ?? const <String>[];
    final tags = _tags
        .where((tag) => counts.containsKey(tag.id) || selected.contains(tag.id))
        .toList();
    await showReaderDrawer<void>(
      context: context,
      builder: (_) => TagStackSettingsSheet(
        groupName: groupName,
        tags: tags,
        counts: counts,
        selected: selected
            .where((id) => tags.any((tag) => tag.id == id))
            .toList(),
        onSave: (ids) async {
          final next = {..._stackTags, groupId ?? 'default': ids};
          await widget.library.setSetting(
            bookshelfTagStacksKey,
            jsonEncode(next),
          );
          if (mounted) {
            setState(() {
              _stackTags = next;
              _expandedStack = null;
            });
          }
        },
      ),
    );
  }

  int _groupBookCount(ShelfGroup group) => (_items ?? const <_ShelfItem>[])
      .where((item) => _bookGroups[item.entry.id] == group.id)
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
          _expandedStack = null;
          _query = '';
          _searchController.clear();
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
      builder: (_) => ReaderTextValueDialog(
        title: title,
        label: '分组名称',
        hintText: '例如：小说、待读',
        initialValue: initial,
        inputKey: const ValueKey<String>('bookshelf-group-name-field'),
        saveKey: const ValueKey<String>('bookshelf-group-name-confirm'),
        confirmLabel: '确定',
        disableWhenEmpty: true,
        submitOnEnter: true,
        validate: (value) => value.isEmpty ? '请输入分组名称' : null,
      ),
    );
  }

  Future<void> _groupBook(BookEntry entry) async {
    final target =
        await showReaderBottomSheet<({String? groupId, String? name})>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _BookGroupSheet(
            summary: entry.title,
            groups: _groups,
            currentGroupId: _bookGroups[entry.id],
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
          _expandedStack = null;
          _query = '';
          _searchController.clear();
        });
      }
    } on LibraryImportException catch (error, stackTrace) {
      recordAppError('book_group_failed', error, stackTrace: stackTrace);
    }
  }

  Future<void> _manageGroup(ShelfGroup group) async {
    final action = await showReaderDrawer<String>(
      context: context,
      builder: (context) => ReaderSheetForm(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name),
            const SizedBox(height: 2),
            Text(
              '${_groupBookCount(group)} 本书',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ReaderOptionTile(
              leading: const AppIcon(AppGlyph.edit),
              title: '重命名分组',
              trailing: const AppIcon(AppGlyph.chevronRight, size: 18),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            const SizedBox(height: 4),
            ReaderOptionTile(
              leading: const AppIcon(AppGlyph.delete),
              title: '删除分组',
              subtitle: '书籍会移回默认分组',
              destructive: true,
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
      final name = await _promptGroupName(title: '重命名分组', initial: group.name);
      if (name == null) {
        return;
      }
      try {
        await widget.library.renameGroup(group.id, name);
      } on LibraryImportException catch (error, stackTrace) {
        recordAppError('group_rename_failed', error, stackTrace: stackTrace);
      }
      return;
    }
    if (action == 'delete') {
      final confirmed = await showReaderConfirmDialog(
        context: context,
        title: '删除分组「${group.name}」？',
        message: '只删除分组，书籍会移回默认分组，阅读记录保留。',
        confirmLabel: '删除',
        destructive: true,
      );
      if (confirmed) {
        await widget.library.deleteGroup(group.id);
        if (mounted && _activeGroupId == group.id) {
          _selectGroup(null);
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

  /// 置顶书籍按置顶先后排在前面，其余沿用当前排序。
  List<_ShelfItem> _sorted(List<_ShelfItem> items) {
    final positions = {
      for (final (index, item) in items.indexed) item.entry.id: index,
    };
    final sorted = List<_ShelfItem>.of(items)
      ..sort((a, b) {
        final compared = _sort.compare(
          a.entry,
          b.entry,
          newBooksFirst: _newBooksFirst,
        );
        return compared != 0
            ? compared
            : positions[a.entry.id]!.compareTo(positions[b.entry.id]!);
      });
    final byId = {for (final item in sorted) item.entry.id: item};
    final pinnedIds = _pinnedIds.toSet();
    return [
      for (final id in _pinnedIds) ?byId[id],
      for (final item in sorted)
        if (!pinnedIds.contains(item.entry.id)) item,
    ];
  }

  /// 先按关键词与当前分组过滤，再沿用书架排序。
  List<_ShelfItem> _visible(List<_ShelfItem> items, {String? groupId}) {
    final query = _query.trim().toLowerCase();
    final filtered = items.where((item) {
      if (_bookGroups[item.entry.id] != groupId) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return item.entry.title.toLowerCase().contains(query) ||
          item.entry.author.toLowerCase().contains(query);
    });
    final sorted = _sorted(filtered.toList());
    final expanded = _expandedStack;
    if (expanded == null || groupId != _activeGroupId) return sorted;
    final stacks = _tagStacks(sorted, groupId);
    return [
      for (final stack in stacks)
        if (stack.tag?.id == expanded.id ||
            (stack.tag == null &&
                (_bookTags[stack.books.single.entry.id]?.contains(
                      expanded.id,
                    ) ??
                    false)))
          ...stack.books,
    ];
  }

  List<ShelfStack<_ShelfItem>> _tagStacks(
    List<_ShelfItem> books,
    String? groupId,
  ) {
    final byId = {for (final tag in _tags) tag.id: tag};
    return stackBooksByTags(
      books: books,
      bookId: (book) => book.entry.id,
      bookTags: _bookTags,
      tags: [
        for (final id in _stackTags[groupId ?? 'default'] ?? <String>[])
          ?byId[id],
      ],
    );
  }

  @override
  void dispose() {
    widget.library.removeListener(_reload);
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
      if (_batch.any(
        (job) =>
            job.status == ImportStatus.succeeded &&
            job.entry?.importOutcome == BookImportOutcome.added,
      )) {
        setState(() {
          _activeGroupId = null;
          _expandedStack = null;
          _query = '';
          _searchController.clear();
        });
      }
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
    final (books, groups, bookGroups, progress, tags, bookTags) = await (
      widget.library.list(),
      widget.library.listGroups(),
      widget.library.groupAssignments(),
      widget.progressStore.snapshot(),
      widget.library.listTags(),
      widget.library.bookTagAssignments(),
    ).wait;
    final (weights, chapterTitles) = await (
      widget.library.progressWeightsForBooks(books.map((book) => book.id)),
      widget.library.readingChapterTitles({
        for (final book in books)
          if (progress[book.id] case final current?)
            book.id: current.spineIndex,
      }),
    ).wait;
    final items = <_ShelfItem>[];
    for (final book in books) {
      final current = progress[book.id];
      final chapterWeights = weights[book.id];
      final readingPercent = current == null
          ? 0.0
          : current.readingPercent?.clamp(0.0, 1.0) ??
                (chapterWeights != null && chapterWeights.total > 0
                    ? chapterWeights.percentOf(current.spineIndex)
                    : ((current.spineIndex + 1) /
                              (book.spineCount ?? 0).clamp(1, 1 << 30))
                          .clamp(0.0, 1.0));
      items.add((
        entry: book,
        spineIndex: current?.spineIndex,
        chapterTitle: chapterTitles[book.id],
        readingPercent: readingPercent,
      ));
    }
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
        _tags = tags;
        _bookTags = bookTags;
        if (_activeGroupId != null &&
            !groups.any((group) => group.id == _activeGroupId)) {
          _activeGroupId = null;
          _expandedStack = null;
        }
        _selectedIds.removeWhere((id) => !validIds.contains(id));
        if (items.isEmpty) {
          _selectionMode = false;
        }
      });
    }
  }

  /// 首屏最多 12 张封面并发准备完成才允许开屏淡出，堆叠按实际缩放预解码。
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
    final covers = [
      for (final stack in _tagStacks(ordered, null))
        for (final item in stack.books.take(bookStackPreviewCount))
          (
            path: item.entry.coverPath,
            size: bookStackCoverSize(
              Size(cardWidth, cardHeight),
              stack.books.length,
            ),
          ),
    ];
    await Future.wait([
      for (final cover in covers.take(12))
        if (cover.path case final path?)
          _precacheCover(
            path,
            coverDecodeWidth(cover.size.width, media.devicePixelRatio),
            coverDecodeHeight(cover.size.height, media.devicePixelRatio),
          ),
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
      builder: (context) => ReaderSheetForm(
        title: const Text('导入书籍'),
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReaderOptionTile(
              leading: const AppIcon(AppGlyph.folder),
              title: '从本机导入',
              subtitle: '选择 EPUB 或 TXT 文件',
              trailing: const AppIcon(AppGlyph.chevronRight, size: 18),
              onTap: () => Navigator.pop(context, 'local'),
            ),
            const SizedBox(height: 4),
            ReaderOptionTile(
              leading: const AppIcon(AppGlyph.link),
              title: '从网盘导入',
              subtitle: '登录网盘，选择书籍下载到书架',
              trailing: const AppIcon(AppGlyph.chevronRight, size: 18),
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
    final action = await showReaderBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BookDetailSheet(
        entry: entry,
        library: widget.library,
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
          const PopupMenuItem(value: 'update', child: Text('更新 EPUB')),
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
    } else if (action == 'export') {
      await _exportBook(entry);
    } else if (action == 'pin') {
      await _togglePinned(entry);
    }
  }

  Future<void> _exportBook(BookEntry entry) async {
    if (_exportingBook) return;
    _exportingBook = true;
    try {
      final current = await widget.library.bookById(entry.id);
      if (current == null) throw const LibraryImportException('书籍不存在');
      final title = current.title
          .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '_')
          .trim();
      final name = String.fromCharCodes(title.runes.take(64));
      final fileName = '${name.isEmpty ? '未命名书籍' : name}.epub';
      final saved = await EpubExport.saveToDownloads(
        File(current.filePath),
        fileName: fileName,
      );
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

  Future<void> _pickBookUpdate(BookEntry entry) async {
    if (!widget.allowImport) return;
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

  Future<void> _confirmRemove(BookEntry entry) async {
    final confirmed = await showReaderConfirmDialog(
      context: context,
      title: '删除《${entry.title}》',
      message:
          '将删除书籍文件，保留笔记、书评、书单和阅读记录。'
          '已配置同步时会传播到所有设备；仅清理本机副本请使用多设备同步页。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed) {
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
    final confirmed = await showReaderConfirmDialog(
      context: context,
      title: '删除选中的 ${entries.length} 本书？',
      message:
          '将删除书籍文件，保留笔记、书评、书单和阅读记录。'
          '已配置同步时会传播到所有设备；仅清理本机副本请使用多设备同步页。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed) {
      await _removeSelected(entries);
    }
  }

  Future<void> _moveSelectedToGroup() async {
    final entries = _selectedEntries();
    if (entries.isEmpty) {
      return;
    }
    final target =
        await showReaderBottomSheet<({String? groupId, String? name})>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _BookGroupSheet(
            summary: '将 ${entries.length} 本书移入分组',
            groups: _groups,
            showCurrentGroup: false,
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
      await _reload();
      if (!mounted) {
        return;
      }
      setState(() {
        _activeGroupId = groupId;
        _expandedStack = null;
        _query = '';
        _searchController.clear();
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
    return PopScope(
      canPop: !widget.active || _expandedStack == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.active && _expandedStack != null) {
          setState(() => _expandedStack = null);
        }
      },
      child: ExcludeFocus(
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
                    ? _desktopShelfMaxWidth
                    : double.infinity,
              ),
              child: LayoutBuilder(
                builder: (_, bounds) => Scaffold(
                  appBar: _buildAppBar(
                    visible,
                    busy || _pickingFiles,
                    bounds.maxWidth,
                  ),
                  bottomNavigationBar: _selectionMode
                      ? _buildSelectionBar()
                      : null,
                  body: _buildBody(items, visible, busy),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    List<_ShelfItem>? items,
    bool busy,
    double width,
  ) {
    final desktop = usesDesktopLayout(context);
    final roomy = desktop && width >= 640;
    final integratedImport = !roomy;
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: desktop ? 64 : 56,
      titleSpacing: 16,
      title: desktop
          ? Row(
              children: [
                if (roomy) ...[
                  Text('书架', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 24),
                ],
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _buildSearchField(
                        trailingAction: integratedImport
                            ? _buildInlineImportButton(busy)
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : _buildSearchField(trailingAction: _buildInlineImportButton(busy)),
      actions: [
        if (_selectionMode)
          Padding(
            padding: EdgeInsets.only(right: integratedImport ? 12 : 4),
            child: TextButton(
              key: const ValueKey<String>('bookshelf-select-all'),
              onPressed: _removing ? null : () => _toggleSelectAll(items),
              child: Text(_allSelected(items) ? '取消全选' : '全选'),
            ),
          ),
        if (!integratedImport)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: _buildImportButton(busy, extended: roomy)),
          ),
      ],
    );
  }

  Widget _buildInlineImportButton(bool busy) {
    final colors = Theme.of(context).colorScheme;
    return Theme(
      data: _noFeedback(context),
      child: IconButton(
        key: const ValueKey<String>('bookshelf-import'),
        color: colors.onSurfaceVariant,
        tooltip: busy ? '导入中…' : '导入 EPUB / TXT',
        constraints: const BoxConstraints.tightFor(width: 48, height: 44),
        padding: EdgeInsets.zero,
        onPressed: busy || !widget.allowImport ? null : _chooseImport,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const AppIcon(AppGlyph.add, size: 22),
      ),
    );
  }

  Widget _buildImportButton(bool busy, {bool extended = false}) {
    final colors = Theme.of(context).colorScheme;
    if (extended) {
      return FilledButton.tonalIcon(
        key: const ValueKey('bookshelf-import'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          visualDensity: VisualDensity.standard,
        ),
        onPressed: busy || !widget.allowImport ? null : _chooseImport,
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const AppIcon(AppGlyph.add, size: 18),
        label: Text(busy ? '导入中…' : '导入书籍'),
      );
    }
    return ReaderSurfaceIconButton(
      buttonKey: const ValueKey<String>('bookshelf-import'),
      tooltip: busy ? '导入中…' : '导入 EPUB / TXT',
      color: colors.primary,
      circular: true,
      keepDesktopHover: usesDesktopLayout(context),
      onPressed: busy || !widget.allowImport ? null : _chooseImport,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const AppIcon(AppGlyph.add),
    );
  }

  Widget _buildSearchField({Widget? trailingAction}) => ReaderSearchField(
    surfaceKey: const ValueKey('bookshelf-search-surface'),
    fieldKey: const ValueKey<String>('bookshelf-search-field'),
    controller: _searchController,
    focusNode: _searchFocus,
    hintText: '搜索书名或作者',
    onTap: _focusSearch,
    onChanged: (value) => setState(() {
      _query = value;
      if (value.trim().isNotEmpty) _expandedStack = null;
    }),
    prefixIcon: IconButton(
      tooltip: '搜索书架',
      onPressed: _focusSearch,
      icon: AppIcon(
        AppGlyph.search,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
    suffixIcon: !_searching
        ? null
        : IconButton(
            tooltip: '关闭搜索',
            onPressed: _toggleSearch,
            icon: AppIcon(
              AppGlyph.close,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
    trailingAction: trailingAction,
  );

  Widget _buildShelfControls(List<_ShelfItem> items) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('bookshelf-group-toolbar'),
      children: [
        Expanded(
          child: _ShelfGroupBar(
            order: _orderedGroupIds,
            groups: {for (final group in _groups) group.id: group},
            onReorder: _reorderGroups,
            activeGroupId: _activeGroupId,
            onSelect: _selectGroup,
            onManage: _manageGroup,
          ),
        ),
        IconButton(
          key: const ValueKey('bookshelf-tag-stacks'),
          tooltip: '标签堆叠',
          color: colors.onSurfaceVariant,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          onPressed: _selectionMode ? null : _configureTagStacks,
          icon: const AppIcon(
            AppGlyph.bookshelf,
            strokeWidth: _shelfToolbarIconStroke,
          ),
        ),
        Theme(
          data: _noFeedback(context),
          child: IconButton(
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
        _expandedStack == null &&
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
        if (_error == null && items != null) _buildShelfControls(items),
        if (_expandedStack case final tag?)
          Row(
            children: [
              IconButton(
                key: const ValueKey('bookshelf-stack-back'),
                tooltip: '收起堆叠',
                onPressed: () => setState(() => _expandedStack = null),
                icon: const AppIcon(AppGlyph.chevronLeft),
              ),
              Expanded(
                child: Text(
                  '${tag.name} · ${visible?.length ?? 0} 本',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        Expanded(
          child: HorizontalPageSwitcher<String?>(
            gestureKey: const ValueKey('bookshelf-group-pages'),
            items: _orderedGroupIds,
            value: _activeGroupId,
            enabled: canSwipe,
            onChanged: _selectGroup,
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
      if (_expandedStack != null) {
        return ReaderEmptyState(
          icon: AppGlyph.bookshelf,
          title: '这个堆叠已没有书籍',
          action: TextButton(
            onPressed: () => setState(() => _expandedStack = null),
            child: const Text('返回书架'),
          ),
        );
      }
      return _NoMatchesPane(
        query: _query.trim(),
        groupName: groupId != null
            ? _groups.where((group) => group.id == groupId).firstOrNull?.name
            : null,
        onReset: _resetFilters,
      );
    }
    final stacks =
        _selectionMode || _query.trim().isNotEmpty || _expandedStack != null
        ? [
            for (final book in books) ShelfStack(books: [book]),
          ]
        : _tagStacks(books, groupId);
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: _grid
          ? _buildBookGrid(books, stacks)
          : _buildBookList(books, stacks),
    );
  }

  Widget _buildBookGrid(
    List<_ShelfItem> books,
    List<ShelfStack<_ShelfItem>> stacks,
  ) {
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
          itemCount: stacks.length,
          itemBuilder: (context, index) {
            final stack = stacks[index];
            if (stack.tag != null) return _buildTagStack(stack);
            final item = stack.books.single;
            final pinned = _pinnedIds.contains(item.entry.id);
            return _desktopBook(
              _BookCard(
                entry: item.entry,
                pinned: pinned,
                showTitle: _showTitles,
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

  Widget _buildTagStack(ShelfStack<_ShelfItem> stack) => BookStackTile(
    tag: stack.tag!,
    books: [for (final item in stack.books) item.entry],
    grid: _grid,
    onOpen: () => setState(() => _expandedStack = stack.tag),
  );

  ({SliverGridDelegateWithFixedCrossAxisCount delegate, double cardWidth})
  _shelfGridMetrics(double width, TextScaler textScaler) {
    final desktop = usesDesktopLayout(context);
    if (desktop) width = math.min(width, _desktopShelfMaxWidth);
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
            (_showTitles
                ? _shelfTitleGap + textScaler.scale(_shelfTitleHeight)
                : 0),
        mainAxisSpacing: 20,
        crossAxisSpacing: _shelfGridSpacing,
      ),
      cardWidth: cardWidth,
    );
  }

  Widget _buildBookList(
    List<_ShelfItem> books,
    List<ShelfStack<_ShelfItem>> stacks,
  ) {
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
          itemCount: stacks.length,
          separatorBuilder: (_, _) => Padding(
            padding: const EdgeInsets.only(left: 96, right: 4),
            child: SizedBox(
              height: 16,
              child: Align(
                alignment: Alignment.center,
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: .45),
                ),
              ),
            ),
          ),
          itemBuilder: (context, index) {
            final stack = stacks[index];
            if (stack.tag != null) return _buildTagStack(stack);
            final item = stack.books.single;
            return _desktopBook(
              _BookRow(
                item: item,
                pinned: _pinnedIds.contains(item.entry.id),
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
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.error,
          side: BorderSide(
            color: count == 0 || _removing
                ? theme.colorScheme.outlineVariant
                : theme.colorScheme.error.withValues(alpha: .45),
          ),
        ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
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

class _BookGroupSheet extends StatefulWidget {
  const _BookGroupSheet({
    required this.summary,
    required this.groups,
    this.currentGroupId,
    this.showCurrentGroup = true,
  });

  final String summary;
  final List<ShelfGroup> groups;
  final String? currentGroupId;
  final bool showCurrentGroup;

  @override
  State<_BookGroupSheet> createState() => _BookGroupSheetState();
}

class _BookGroupSheetState extends State<_BookGroupSheet> {
  final _controller = TextEditingController();
  late bool _creating = widget.groups.isEmpty;

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
      ListTile(
        key: const ValueKey('bookshelf-book-group-default'),
        contentPadding: EdgeInsets.zero,
        leading: const AppIcon(AppGlyph.folder),
        title: const Text('默认分组'),
        subtitle: widget.showCurrentGroup && widget.currentGroupId == null
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
          subtitle: widget.showCurrentGroup && group.id == widget.currentGroupId
              ? const Text('当前分组')
              : null,
          onTap: () =>
              Navigator.of(context).pop((groupId: group.id, name: null)),
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

class _ShelfGroupBar extends StatefulWidget {
  const _ShelfGroupBar({
    required this.order,
    required this.groups,
    required this.onReorder,
    required this.activeGroupId,
    required this.onSelect,
    required this.onManage,
  });

  final List<String?> order;
  final Map<String, ShelfGroup> groups;
  final ReorderCallback onReorder;
  final String? activeGroupId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<ShelfGroup> onManage;

  @override
  State<_ShelfGroupBar> createState() => _ShelfGroupBarState();
}

class _ShelfGroupBarState extends State<_ShelfGroupBar> {
  Offset? _pressPosition;
  bool _moved = false;
  int? _heldIndex;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _pressPosition = event.position;
        _moved = false;
      },
      onPointerMove: (event) {
        final start = _pressPosition;
        if (start != null && (event.position - start).distance > kTouchSlop) {
          _moved = true;
        }
      },
      child: SizedBox(
        height: 44,
        child: ReorderableListView.builder(
          key: const ValueKey('bookshelf-group-strip'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, _, _) =>
              Material(type: MaterialType.transparency, child: child),
          itemCount: widget.order.length,
          onReorderStart: (index) => _heldIndex = index,
          onReorderEnd: (index) {
            final held = _heldIndex;
            _heldIndex = null;
            if (_moved || held != index || held == null) return;
            final group = widget.groups[widget.order[held]];
            if (group != null) widget.onManage(group);
          },
          onReorderItem: widget.onReorder,
          itemBuilder: (_, index) {
            final id = widget.order[index];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(('shelf-drag', id)),
              index: index,
              child: _tab(id),
            );
          },
        ),
      ),
    );
  }

  Widget _tab(String? id) {
    final group = widget.groups[id];
    return _ShelfGroupTab(
      key: ValueKey('bookshelf-group-${id ?? 'default'}'),
      label: group?.name ?? '默认分组',
      selected: widget.activeGroupId == id,
      onTap: () => widget.onSelect(id),
      onManage: group == null ? null : () => widget.onManage(group),
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
    this.onManage,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onManage;

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
    final colors = theme.colorScheme;
    return Semantics(
      selected: widget.selected,
      button: true,
      onLongPress: widget.onManage,
      child: Theme(
        data: _noFeedback(context),
        child: InkWell(
          onTap: widget.onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.only(right: 20),
            height: 44,
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: widget.selected
                    ? colors.primary
                    : colors.onSurfaceVariant,
                fontWeight: widget.selected
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
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
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onLongPress,
    required this.onSecondaryTap,
  });

  final _ShelfItem item;
  final bool pinned;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final Future<void> Function(BookEntry) onOpen;
  final Future<void> Function(BookEntry) onLongPress;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = item.entry;
    final author = entry.author.trim();
    final colors = theme.colorScheme;
    final metadataStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final chapterLine = item.spineIndex == null
        ? '尚未开始阅读'
        : '已读 · ${item.chapterTitle ?? '第 ${item.spineIndex! + 1} 章'}';
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
    final chapterProgress = Semantics(
      key: ValueKey<String>('book-row-progress-semantics-${entry.id}'),
      container: true,
      label: '全文进度 ${(item.readingPercent * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          key: ValueKey<String>('book-row-progress-${entry.id}'),
          value: item.readingPercent,
          minHeight: 4,
          color: colors.primary.withValues(alpha: .68),
          backgroundColor: colors.outlineVariant.withValues(alpha: .35),
        ),
      ),
    );
    return Semantics(
      selected: selectionMode && selected,
      child: Material(
        color: selectionMode && selected
            ? colors.primaryContainer.withValues(alpha: .42)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selectionMode && selected
              ? BorderSide(color: colors.primary)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('book-row-${entry.id}'),
          canRequestFocus: !usesDesktopLayout(context),
          overlayColor: _bookPressOverlay,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: <Widget>[
                cover,
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.title,
                        key: ValueKey<String>('book-row-title-${entry.id}'),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        author.isEmpty ? '佚名' : author,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: metadataStyle,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chapterLine,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: metadataStyle?.copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      chapterProgress,
                    ],
                  ),
                ),
                if (selectionMode) ...[
                  const SizedBox(width: 10),
                  Checkbox(
                    key: ValueKey<String>('book-row-check-${entry.id}'),
                    value: selected,
                    onChanged: (_) => onSelect(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.allowImport});

  final bool allowImport;

  @override
  Widget build(BuildContext context) => ReaderEmptyState(
    icon: AppGlyph.bookshelf,
    title: allowImport ? '书架还是空的' : '书库暂时不可用',
    subtitle: allowImport ? '点击右上角导入按钮添加第一本书' : '请先重试本地数据库，恢复后再导入书籍',
  );
}

class _NoMatchesPane extends StatelessWidget {
  const _NoMatchesPane({
    required this.query,
    required this.onReset,
    this.groupName,
  });

  final String query;
  final VoidCallback onReset;
  final String? groupName;

  @override
  Widget build(BuildContext context) => ReaderEmptyState(
    icon: AppGlyph.searchOff,
    title: query.isNotEmpty
        ? '没有找到相关书籍'
        : groupName == null
        ? '默认分组还没有书'
        : '这个分组还没有书',
    subtitle: query.isNotEmpty
        ? '没有书名或作者包含“$query”'
        : groupName != null
        ? '在其他分组中选择书籍，再移入「$groupName」'
        : '新导入的书籍会放在这里，也可以从其他分组移回',
    action: query.isEmpty
        ? null
        : OutlinedButton.icon(
            onPressed: onReset,
            icon: const AppIcon(AppGlyph.filterOff, size: 18),
            label: const Text('清除筛选'),
          ),
  );
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
    final colors = Theme.of(context).colorScheme;
    return ReaderEmptyState(
      icon: AppGlyph.error,
      iconColor: colors.error,
      iconContainerColor: colors.errorContainer,
      title: message,
      action: FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.entry,
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
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
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
