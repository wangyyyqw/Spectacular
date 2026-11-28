import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../library/library_store.dart';
import '../txt/txt_book_service.dart';
import '../txt/txt_chapter_rule_page.dart';
import 'book_cover_image.dart';
import 'book_lists_view.dart';
import 'book_rating.dart';
import 'book_reading_chart.dart';
import 'reading_insights.dart';
import 'reading_metric.dart';
import 'finish_book_sheet.dart';
import '../storage/book_review_store.dart';
import '../storage/drift_progress_store.dart';
import '../storage/reading_session_store.dart';
import '../diagnostics/reader_log.dart';

/// 用户选择的封面图片。
typedef CoverSelection = ({Uint8List bytes, String extension});

/// 封面选择入口，测试可注入。
typedef CoverPicker = Future<CoverSelection?> Function();

/// 图书详情页：编辑资料、更换封面并为书籍打标签。
class BookDetailPage extends StatefulWidget {
  /// 创建详情页。
  const BookDetailPage({
    super.key,
    required this.entry,
    required this.library,
    this.pickCover = _pickCoverImage,
    this.sessionStore,
    this.progressStore,
    this.reviewStore,
    this.inDrawer = false,
  });

  /// 打开页面时的书籍条目。
  final BookEntry entry;

  /// 书库存储。
  final LibraryStore library;

  /// 封面选择入口。
  final CoverPicker pickCover;

  /// 可注入的阅读会话存储；为空时使用书库数据库实现。
  final ReadingSessionStore? sessionStore;

  /// 阅读进度存储；传入后才能标记读完。
  final ReaderProgressStore? progressStore;

  /// 可注入的书评存储；为空时使用书库数据库实现。
  final BookReviewStore? reviewStore;

  /// 从书架打开时展示为抽屉，保留直接打开完整页面的能力。
  final bool inDrawer;

  static Future<CoverSelection?> _pickCoverImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) {
      return null;
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      return null;
    }
    var extension =
        file.extension?.toLowerCase() ??
        p.extension(file.name).replaceFirst('.', '').toLowerCase();
    if (extension == 'jpeg') {
      extension = 'jpg';
    }
    return (bytes: bytes, extension: extension.isEmpty ? 'jpg' : extension);
  }

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  late BookEntry _entry = widget.entry;
  late final TextEditingController _titleController = TextEditingController(
    text: widget.entry.title,
  );
  late final TextEditingController _authorController = TextEditingController(
    text: widget.entry.author,
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.entry.description);
  final FocusNode _descriptionFocusNode = FocusNode();
  final TextEditingController _tagController = TextEditingController();

  List<BookTag> _tags = const <BookTag>[];
  Set<String> _selectedTagIds = <String>{};
  _BookReadingStats _readingStats = const _BookReadingStats.empty();
  ReaderProgress? _progress;
  BookReview? _review;
  Future<int?>? _fileSize;
  int? _characterCount;
  bool _loading = true;
  bool _saving = false;
  bool _changingCover = false;
  bool _savingTags = false;
  bool _canRechapter = false;
  String? _loadError;
  String? _writeError;

  BookReviewStore? get _reviewStore =>
      widget.reviewStore ?? widget.library.reviewStore();

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onDraftChanged);
    _authorController.addListener(_onDraftChanged);
    _descriptionController.addListener(_onDraftChanged);
    _tagController.addListener(_onDraftChanged);
    _load();
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_onDraftChanged)
      ..dispose();
    _authorController
      ..removeListener(_onDraftChanged)
      ..dispose();
    _descriptionController
      ..removeListener(_onDraftChanged)
      ..dispose();
    _descriptionFocusNode.dispose();
    _tagController
      ..removeListener(_onDraftChanged)
      ..dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _loadDetails();
    } catch (error, stackTrace) {
      recordAppError('book_detail_load_failed', error, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '图书详情加载失败';
        });
      }
    }
  }

  Future<void> _loadDetails() async {
    final entry = await widget.library.bookById(_entry.id);
    final tags = await widget.library.listTags();
    final selected = await widget.library.bookTags(_entry.id);
    final characterCount = await _loadCharacterCount(_entry.id);
    final sessionStore =
        widget.sessionStore ?? widget.library.readingSessionStore();
    final sessions =
        await (sessionStore?.list() ??
            Future<List<ReadingSession>>.value(const <ReadingSession>[]));
    final progress = await widget.progressStore?.load(_entry.id);
    final reviewStore = _reviewStore;
    final reviews =
        await (reviewStore?.snapshot() ??
            Future<Map<String, BookReview>>.value(
              const <String, BookReview>{},
            ));
    if (!mounted) {
      return;
    }
    if (entry == null) {
      setState(() {
        _loading = false;
        _loadError = '书籍不存在或已从书架移除';
      });
      return;
    }
    _titleController.text = entry.title;
    _authorController.text = entry.author;
    _descriptionController.text = entry.description;
    setState(() {
      _entry = entry;
      _fileSize = widget.library.supportsPersistence
          ? _bookFileSize(entry.filePath)
          : null;
      _characterCount = characterCount;
      _tags = tags;
      _selectedTagIds = <String>{for (final tag in selected) tag.id};
      _readingStats = _BookReadingStats.fromSessions(
        sessions.where((session) => session.bookId == entry.id).toList(),
        DateTime.now(),
      );
      _progress = progress;
      _review = reviews[entry.id];
      _loading = false;
      _loadError = null;
    });
    unawaited(_loadChapterRuleAvailability(entry));
  }

  Future<void> _loadChapterRuleAvailability(BookEntry entry) async {
    final canRechapter = await TxtBookService(widget.library)
        .canRechapter(entry)
        .catchError((Object _) => false);
    if (mounted) setState(() => _canRechapter = canRechapter);
  }

  bool get _hasMetadataChanges =>
      _titleController.text.trim() != _entry.title ||
      _authorController.text.trim() != _entry.author ||
      _descriptionController.text.trim() != _entry.description;

  bool get _writingBook => _saving || _changingCover || _savingTags;

  Future<void> _saveMetadata() async {
    if (_writingBook) {
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      _showMessage('书名不能为空', isWriteError: true);
      return;
    }
    setState(() {
      _saving = true;
      _writeError = null;
    });
    try {
      final entry = await widget.library.updateBookMetadata(
        _entry.id,
        title: _titleController.text,
        author: _authorController.text,
        description: _descriptionController.text,
      );
      await _refreshBookEntry(entry);
      if (!mounted) {
        return;
      }
      _titleController.text = entry.title;
      _authorController.text = entry.author;
      _descriptionController.text = entry.description;
      _showMessage('图书资料已保存');
    } on LibraryImportException catch (error) {
      _showMessage(error.message, isWriteError: true);
    } catch (error, stackTrace) {
      recordAppError(
        'book_metadata_save_failed',
        error,
        stackTrace: stackTrace,
      );
      _showMessage('图书资料保存失败，输入已保留，请重试', isWriteError: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _changeCover() async {
    if (_writingBook) {
      return;
    }
    CoverSelection? selection;
    try {
      selection = await widget.pickCover();
    } catch (_) {
      _showMessage('选择封面失败，请重试', isWriteError: true);
      return;
    }
    if (selection == null || !mounted) {
      return;
    }
    setState(() {
      _changingCover = true;
      _writeError = null;
    });
    try {
      final entry = await widget.library.replaceCover(
        _entry.id,
        selection.bytes,
        extension: selection.extension,
      );
      await _refreshBookEntry(entry);
      if (!mounted) {
        return;
      }
      _showMessage('封面已更新');
    } on LibraryImportException catch (error) {
      _showMessage(error.message, isWriteError: true);
    } catch (_) {
      _showMessage('封面更新失败，请重试', isWriteError: true);
    } finally {
      if (mounted) {
        setState(() => _changingCover = false);
      }
    }
  }

  Future<void> _setTagSelected(BookTag tag, bool selected) async {
    if (_writingBook) return;
    setState(() {
      _savingTags = true;
      _writeError = null;
    });
    try {
      if (selected) {
        await widget.library.addBookTag(_entry.id, tag.id);
      } else {
        await widget.library.removeBookTag(_entry.id, tag.id);
      }
      await _reloadTags();
    } on LibraryImportException catch (error) {
      _showMessage(error.message, isWriteError: true);
    } catch (error, stackTrace) {
      recordAppError('book_tags_save_failed', error, stackTrace: stackTrace);
      _showMessage('标签保存失败，请重试', isWriteError: true);
    } finally {
      if (mounted) setState(() => _savingTags = false);
    }
  }

  Future<void> _createTag() async {
    final name = _tagController.text.trim();
    if (name.isEmpty || _writingBook) {
      return;
    }
    setState(() {
      _savingTags = true;
      _writeError = null;
    });
    try {
      final tag = await widget.library.createTag(name);
      await widget.library.addBookTag(_entry.id, tag.id);
      if (!mounted) return;
      _tagController.clear();
      await _reloadTags();
    } on LibraryImportException catch (error) {
      _showMessage(error.message, isWriteError: true);
    } catch (error, stackTrace) {
      recordAppError('book_tag_create_failed', error, stackTrace: stackTrace);
      _showMessage('标签保存失败，输入已保留，请重试', isWriteError: true);
    } finally {
      if (mounted) setState(() => _savingTags = false);
    }
  }

  Future<void> _reloadTags() async {
    final tags = await widget.library.listTags();
    final selected = await widget.library.bookTags(_entry.id);
    final entry = await widget.library.bookById(_entry.id);
    if (entry != null) await _refreshBookEntry(entry);
    if (!mounted) {
      return;
    }
    setState(() {
      _tags = tags;
      _selectedTagIds = <String>{for (final tag in selected) tag.id};
    });
  }

  Future<void> _refreshBookEntry(BookEntry entry) async {
    final progress = await widget.progressStore?.load(entry.id);
    final characterCount = await _loadCharacterCount(entry.id);
    if (mounted) {
      setState(() {
        _entry = entry;
        _fileSize = widget.library.supportsPersistence
            ? _bookFileSize(entry.filePath)
            : null;
        _characterCount = characterCount;
        _progress = progress;
      });
    }
  }

  Future<int?> _loadCharacterCount(String bookId) async {
    final weights = await widget.library.progressWeights(bookId);
    return weights.estimated || weights.chapterCount == 0
        ? null
        : weights.totalCharacters;
  }

  Future<void> _editFinished() async {
    if (widget.progressStore == null) {
      _showMessage('当前无法保存读完标记');
      return;
    }
    final savedReview = await showReaderBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => FinishBookSheet(
        book: _entry,
        review: _review,
        allowReview: _reviewStore != null,
        finished: _progress?.finished ?? false,
        onCommit: _saveFinished,
      ),
    );
    if (savedReview != null && mounted) {
      _showMessage(savedReview ? '书评已保存' : '已标记读完');
    }
  }

  ReaderProgress _finishedProgress() {
    final existing = _progress;
    if (existing != null) return existing.withFinished(true);
    final lastSpine = ((_entry.spineCount ?? 1) - 1).clamp(0, 1000000);
    return ReaderProgress(spineIndex: lastSpine, pageIndex: 0, finished: true);
  }

  Future<void> _saveFinished(FinishBookDraft? draft) async {
    final progressStore = widget.progressStore;
    if (progressStore == null) throw const FormatException('当前无法保存读完标记');
    final reviewStore = _reviewStore;
    final progress = _finishedProgress();
    if (draft != null &&
        reviewStore != null &&
        progressStore is DriftProgressStore) {
      await progressStore.saveFinishedWithReview(
        _entry.id,
        progress,
        () => reviewStore.save(
          _entry.id,
          rating: draft.rating,
          content: draft.content,
        ),
      );
    } else {
      await progressStore.save(_entry.id, progress);
      if (draft != null && reviewStore != null) {
        await reviewStore.save(
          _entry.id,
          rating: draft.rating,
          content: draft.content,
        );
      }
    }
    final review = draft == null
        ? _review
        : (await reviewStore?.snapshot())?[_entry.id];
    if (mounted) {
      setState(() {
        _progress = progress;
        _review = review;
      });
    }
  }

  Future<void> _unmarkFinished() async {
    final progressStore = widget.progressStore;
    if (progressStore == null) {
      return;
    }
    final confirmed = await showReaderConfirmDialog(
      context: context,
      title: '取消读完标记？',
      message: '书评和评分会保留，阅读进度不会改变。',
      cancelLabel: '保留',
      confirmLabel: '取消标记',
      confirmKey: const ValueKey<String>('book-detail-unmark-confirm'),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final existing = _progress;
    final progress = ReaderProgress(
      spineIndex: existing?.spineIndex ?? 0,
      pageIndex: existing?.pageIndex ?? 0,
      finished: false,
      scrollOffset: existing?.scrollOffset,
      cfi: existing?.cfi,
      contentRevision: existing?.contentRevision,
      approximate: existing?.approximate ?? false,
      readingPercent: existing?.readingPercent,
      layoutFingerprint: existing?.layoutFingerprint,
    );
    try {
      await progressStore.save(_entry.id, progress);
      if (!mounted) {
        return;
      }
      setState(() => _progress = progress);
      _showMessage('已取消读完标记');
    } catch (_) {
      _showMessage('保存失败，请重试');
    }
  }

  void _showMessage(String message, {bool isWriteError = false}) {
    if (!mounted) {
      return;
    }
    if (isWriteError) setState(() => _writeError = message);
    recordAppEvent('book_detail_message', fields: {'message': message});
  }

  Future<void> _openChapterRules() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            TxtChapterRulePage(entry: _entry, library: widget.library),
      ),
    );
    if (changed == true && mounted) {
      final entry = await widget.library.bookById(_entry.id);
      if (entry != null && mounted) await _refreshBookEntry(entry);
    }
  }

  Future<void> _openBookLists() => showBookListMembership(
    context,
    library: widget.library,
    bookId: _entry.id,
  );

  @override
  Widget build(BuildContext context) {
    final canSave =
        !_writingBook && !_loading && _hasMetadataChanges && _loadError == null;
    if (widget.inDrawer) {
      // 与设置、书单等抽屉共用同一骨架：面板底色、标题、关闭和底部主按钮。
      return Material(
        type: MaterialType.transparency,
        child: ReaderSheetForm(
          title: const Text('图书详情'),
          contentPadding: EdgeInsets.zero,
          scrollContent: false,
          content: Column(
            children: [
              if (_writeError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: ReaderNoticeBanner(message: _writeError!),
                ),
              Expanded(child: _content()),
            ],
          ),
          actions: [_saveButton(canSave)],
        ),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('图书详情'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              key: const ValueKey('book-detail-save'),
              onPressed: canSave ? _saveMetadata : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const AppIcon(AppGlyph.check, size: 18),
              label: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _writeError == null
          ? null
          : SafeArea(
              child: Padding(
                padding: ReaderUiStyle.pagePadding,
                child: ReaderNoticeBanner(message: _writeError!),
              ),
            ),
      body: _content(),
    );
  }

  Widget _saveButton(bool canSave) => FilledButton(
    key: const ValueKey('book-detail-save'),
    onPressed: canSave ? _saveMetadata : null,
    child: _saving
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Text('保存'),
  );

  Widget _content() => _loading
      ? const Center(child: CircularProgressIndicator())
      : _loadError != null
      ? ReaderEmptyState(
          icon: AppGlyph.error,
          title: _loadError!,
          action: TextButton(onPressed: _load, child: const Text('重试')),
        )
      : Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              key: const ValueKey('book-detail-content'),
              padding: ReaderUiStyle.pagePadding,
              children: [
                _metadataSection(),
                const SizedBox(height: 16),
                _storageSection(),
                const SizedBox(height: 16),
                _tagsSection(),
                const SizedBox(height: 16),
                _descriptionSection(),
                const SizedBox(height: 16),
                _ReadingStatsSection(stats: _readingStats),
                const SizedBox(height: 24),
                _ReadingStatusSection(
                  progress: _progress,
                  review: _review,
                  busy: _writingBook,
                  canEdit: widget.progressStore != null,
                  onEdit: _editFinished,
                  onUnmark: _unmarkFinished,
                ),
                const SizedBox(height: 24),
                _bookActions(),
              ],
            ),
          ),
        );

  Widget _metadataSection() => ReaderSectionCard(
    key: const ValueKey('book-detail-metadata-card'),
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, bounds) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverEditor(
            entry: _entry,
            width: (bounds.maxWidth * .28).clamp(72.0, 112.0),
            busy: _writingBook,
            changingCover: _changingCover,
            onChange: _changeCover,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                _MetadataField(
                  fieldKey: const ValueKey('book-detail-title-field'),
                  label: '书名',
                  controller: _titleController,
                  enabled: !_writingBook,
                  textInputAction: TextInputAction.next,
                ),
                const Divider(height: 16),
                _MetadataField(
                  fieldKey: const ValueKey('book-detail-author-field'),
                  label: '作者',
                  controller: _authorController,
                  enabled: !_writingBook,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _storageSection() => FutureBuilder<int?>(
    future: _fileSize,
    builder: (context, snapshot) => ReaderSectionCard(
      key: const ValueKey('book-detail-storage-card'),
      children: [
        ReaderOptionTile(
          title: 'EPUB 大小',
          trailing: Text(
            snapshot.data != null
                ? _formatFileSize(snapshot.data!)
                : snapshot.connectionState == ConnectionState.waiting
                ? '读取中…'
                : '暂不可用',
            key: const ValueKey('book-detail-storage-value'),
          ),
        ),
        ReaderOptionTile(
          title: '字数',
          trailing: Text(
            _characterCount == null
                ? '暂无统计'
                : '${_formatReadingCharacters(_characterCount!)} 字',
            key: const ValueKey('book-detail-character-count'),
          ),
        ),
      ],
    ),
  );

  Widget _descriptionSection() => ReaderSectionCard(
    key: const ValueKey('book-detail-description-card'),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('book-detail-edit-description'),
          onTap: _writingBook ? null : _descriptionFocusNode.requestFocus,
          child: Row(
            children: [
              Expanded(
                child: Text('简介', style: Theme.of(context).textTheme.bodySmall),
              ),
              AppIcon(
                AppGlyph.edit,
                size: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 12),
        Semantics(
          label: '简介',
          child: TextField(
            key: const ValueKey('book-detail-description-field'),
            enabled: !_writingBook,
            controller: _descriptionController,
            focusNode: _descriptionFocusNode,
            minLines: _descriptionController.text.isEmpty ? 2 : 3,
            maxLines: 6,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.8),
            decoration: const InputDecoration(
              hintText: '添加简介',
              isDense: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _tagsSection() => ReaderSectionCard(
    key: const ValueKey('book-detail-tags-card'),
    title: '设置标签',
    trailing: Text(
      _savingTags ? '保存中…' : '已选 ${_selectedTagIds.length} 个',
      style: Theme.of(context).textTheme.bodySmall,
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('本书标签', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_selectedTagIds.isEmpty)
          Text(
            '本书暂无标签，可从下方全部标签中添加。',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            key: const ValueKey('book-detail-book-tags'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _tags)
                if (_selectedTagIds.contains(tag.id))
                  InputChip(
                    key: ValueKey('book-detail-book-tag-${tag.id}'),
                    label: _tagLabel(tag),
                    tooltip: tag.name,
                    isEnabled: !_writingBook,
                    deleteIcon: const AppIcon(AppGlyph.close, size: 18),
                    deleteButtonTooltipMessage: '从本书移除标签「${tag.name}」',
                    onDeleted: _writingBook
                        ? null
                        : () => _setTagSelected(tag, false),
                  ),
            ],
          ),
        const SizedBox(height: 8),
        Text('移除仅对本书生效，不影响其他书籍。', style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: 24),
        Text('全部标签', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_tags.isEmpty)
          Text('暂无标签，可在下方新建。', style: Theme.of(context).textTheme.bodySmall)
        else
          Wrap(
            key: const ValueKey('book-detail-all-tags'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _tags)
                FilterChip(
                  key: ValueKey('book-detail-tag-${tag.id}'),
                  label: _tagLabel(tag),
                  tooltip: tag.name,
                  selected: _selectedTagIds.contains(tag.id),
                  showCheckmark: true,
                  onSelected: _writingBook
                      ? null
                      : (selected) => _setTagSelected(tag, selected),
                ),
            ],
          ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('book-detail-new-tag-field'),
          enabled: !_writingBook,
          controller: _tagController,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: '新建标签',
            hintText: '例如：科幻、待读',
            suffixIcon: IconButton(
              key: const ValueKey('book-detail-add-tag'),
              tooltip: '创建并添加标签',
              onPressed: _writingBook || _tagController.text.trim().isEmpty
                  ? null
                  : _createTag,
              icon: const AppIcon(AppGlyph.add),
            ),
          ),
          onSubmitted: (_) => _createTag(),
        ),
      ],
    ),
  );

  Widget _tagLabel(BookTag tag) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 180),
    child: Text(tag.name, maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  Widget _bookActions() => ReaderSectionCard(
    title: '书籍管理',
    children: [
      ReaderOptionTile(
        tileKey: const ValueKey('book-detail-booklists'),
        leading: const AppIcon(AppGlyph.bookmarkAdd),
        title: '加入书单',
        subtitle: '选择这本书所在的书单',
        trailing: const AppIcon(AppGlyph.chevronRight),
        onTap: _openBookLists,
      ),
      if (_canRechapter)
        ReaderOptionTile(
          tileKey: const ValueKey('book-detail-page-chapters'),
          leading: const AppIcon(AppGlyph.listBulleted),
          title: '章节正则',
          subtitle: '预览并重新划分当前正文的章节',
          trailing: const AppIcon(AppGlyph.chevronRight),
          enabled: !_writingBook,
          onTap: _openChapterRules,
        ),
    ],
  );
}

Future<int?> _bookFileSize(String path) async {
  final stat = await File(path).stat();
  return stat.type == FileSystemEntityType.file ? stat.size : null;
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatReadingCharacters(int count) {
  if (count <= 0) {
    return '0';
  }
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)} 亿';
  }
  if (count >= 10000) {
    final value = count / 10000;
    final text = value >= 10
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return '$text 万';
  }
  return '$count';
}

String _formatDateKey(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String _formatDayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (date.isAtSameMomentAs(today)) {
    return '今天';
  }
  if (date.isAtSameMomentAs(yesterday)) {
    return '昨天';
  }
  return '${date.month}月${date.day}日';
}

class _MetadataField extends StatelessWidget {
  const _MetadataField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.enabled,
    required this.textInputAction,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Semantics(
          label: label,
          child: TextField(
            key: fieldKey,
            enabled: enabled,
            controller: controller,
            textInputAction: textInputAction,
            minLines: 1,
            maxLines: 3,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: label == '书名' ? '填写书名' : '未填写',
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              suffixIcon: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: AppIcon(
                  AppGlyph.edit,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 28),
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverEditor extends StatelessWidget {
  const _CoverEditor({
    required this.entry,
    required this.width,
    required this.busy,
    required this.changingCover,
    required this.onChange,
  });

  final BookEntry entry;
  final double width;
  final bool busy;
  final bool changingCover;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Semantics(
      label: '更换封面',
      button: true,
      enabled: !busy,
      child: InkWell(
        key: const ValueKey('book-detail-page-cover'),
        onTap: busy ? null : onChange,
        borderRadius: BorderRadius.circular(4),
        child: ExcludeSemantics(
          child: Column(
            children: [
              BookCoverImage(book: entry, width: width, height: width * 1.4),
              const SizedBox(height: 8),
              if (changingCover)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  '更换封面',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BookReadingStats {
  const _BookReadingStats({
    required this.totalDuration,
    required this.sessionCount,
    required this.pageTurns,
    required this.charactersRead,
    required this.readingDays,
    required this.recentDays,
  });

  const _BookReadingStats.empty()
    : totalDuration = Duration.zero,
      sessionCount = 0,
      pageTurns = 0,
      charactersRead = 0,
      readingDays = 0,
      recentDays = const <_BookDailyReading>[];

  factory _BookReadingStats.fromSessions(
    List<ReadingSession> sessions,
    DateTime now,
  ) {
    final insights = ReadingInsights(sessions, now: now);
    final byDay = {
      for (final day in insights.byDay.entries)
        day.key: _BookDailyReading(date: day.key)..duration = day.value,
    };
    // 每日次数、翻页和字数沿用会话开始日归属；时长复用公共的跨日有效时长。
    for (final session in insights.sessions) {
      final start = session.startedAt.toLocal();
      final date = DateTime(start.year, start.month, start.day);
      final day = byDay.putIfAbsent(date, () => _BookDailyReading(date: date));
      day.sessionCount++;
      day.pageTurns += session.pageTurns;
      day.charactersRead += session.charactersRead;
    }

    final today = DateTime(now.year, now.month, now.day);
    return _BookReadingStats(
      totalDuration: insights.totalReading,
      sessionCount: insights.sessions.length,
      pageTurns: insights.pageTurns,
      charactersRead: insights.charactersRead,
      readingDays: insights.byDay.length,
      recentDays: <_BookDailyReading>[
        for (var offset = 0; offset < 7; offset++)
          byDay[DateTime(today.year, today.month, today.day - offset)] ??
              _BookDailyReading(
                date: DateTime(today.year, today.month, today.day - offset),
              ),
      ],
    );
  }

  final Duration totalDuration;
  final int sessionCount;
  final int pageTurns;
  final int charactersRead;
  final int readingDays;
  final List<_BookDailyReading> recentDays;
}

class _BookDailyReading {
  _BookDailyReading({required this.date});

  final DateTime date;
  Duration duration = Duration.zero;
  int sessionCount = 0;
  int pageTurns = 0;
  int charactersRead = 0;
}

class _ReadingStatsSection extends StatelessWidget {
  const _ReadingStatsSection({required this.stats});

  final _BookReadingStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.sessionCount == 0) {
      return const ReaderSectionCard(
        title: '阅读记录',
        padding: EdgeInsets.all(16),
        child: Text('暂无阅读记录，开始阅读后会在这里汇总。'),
      );
    }
    final maximum = stats.recentDays.fold<Duration>(
      Duration.zero,
      (longest, day) => day.duration > longest ? day.duration : longest,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderSectionCard(
          title: '阅读记录',
          key: const ValueKey('book-detail-reading-summary'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReadingMetric(
                label: '累计时长',
                value: formatReadingDuration(stats.totalDuration),
                valueKey: const ValueKey('book-detail-total-duration'),
                valueSize: 26,
              ),
              const SizedBox(height: 16),
              if (maximum > Duration.zero)
                BookReadingChart(
                  framed: false,
                  durations: [
                    for (final day in stats.recentDays.reversed) day.duration,
                  ],
                  endDate: stats.recentDays.first.date,
                )
              else
                Text(
                  '最近 7 天暂无阅读记录',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const Divider(height: 32),
              _ReadingMetricRow(
                left: ReadingMetric(
                  label: '阅读次数',
                  value: '${stats.sessionCount}',
                  valueSize: 20,
                  valueKey: const ValueKey('book-detail-session-count'),
                ),
                right: ReadingMetric(
                  label: '阅读天数',
                  value: '${stats.readingDays}',
                  valueSize: 20,
                  valueKey: const ValueKey('book-detail-reading-days'),
                ),
              ),
              const SizedBox(height: 16),
              _ReadingMetricRow(
                left: ReadingMetric(
                  label: '翻页次数',
                  value: '${stats.pageTurns}',
                  valueSize: 20,
                  valueKey: const ValueKey('book-detail-page-turns'),
                ),
                right: ReadingMetric(
                  label: '阅读字数',
                  value: _formatReadingCharacters(stats.charactersRead),
                  valueSize: 20,
                  valueKey: const ValueKey('book-detail-characters-read'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ReaderSectionCard(
          child: AppExpansionTile(
            title: const Text('每日明细'),
            subtitle: const Text('查看最近 7 天的时长、次数与翻页'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    for (final day in stats.recentDays)
                      _DailyReadingRow(day: day, maxDuration: maximum),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadingMetricRow extends StatelessWidget {
  const _ReadingMetricRow({required this.left, required this.right});

  final ReadingMetric left;
  final ReadingMetric right;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: 20),
      Expanded(child: right),
    ],
  );
}

class _DailyReadingRow extends StatelessWidget {
  const _DailyReadingRow({required this.day, required this.maxDuration});

  final _BookDailyReading day;
  final Duration maxDuration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActivity = day.duration > Duration.zero;
    final dateKey = _formatDateKey(day.date);
    final maximum = maxDuration.inMicroseconds;
    final value = maximum == 0
        ? 0.0
        : (day.duration.inMicroseconds / maximum).clamp(0.0, 1.0);
    return Container(
      key: ValueKey<String>('book-detail-daily-$dateKey'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(54),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatDayLabel(day.date),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hasActivity
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  formatReadingDuration(day.duration),
                  key: ValueKey<String>('book-detail-daily-duration-$dateKey'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasActivity
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: hasActivity ? FontWeight.w600 : null,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    key: ValueKey<String>('book-detail-daily-bar-$dateKey'),
                    value: value,
                    minHeight: 4,
                    backgroundColor: theme.colorScheme.surfaceContainer,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      hasActivity
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${day.sessionCount} 次 · 翻页 ${day.pageTurns} · '
                  '${_formatReadingCharacters(day.charactersRead)} 字',
                  key: ValueKey<String>('book-detail-daily-detail-$dateKey'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingStatusSection extends StatelessWidget {
  const _ReadingStatusSection({
    required this.progress,
    required this.review,
    required this.canEdit,
    required this.busy,
    required this.onEdit,
    required this.onUnmark,
  });

  final ReaderProgress? progress;
  final BookReview? review;
  final bool canEdit;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onUnmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = progress?.finished ?? false;
    final content = review?.content ?? '';
    return ReaderSectionCard(
      title: '阅读状态',
      key: const ValueKey<String>('book-detail-reading-status'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIcon(
                finished ? AppGlyph.checkCircle : AppGlyph.autoStories,
                size: 20,
                color: finished
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  finished ? '已读完' : '未标记读完',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: finished ? theme.colorScheme.primary : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (review?.rating != null)
                BookRatingStars(
                  rating: review!.rating!,
                  filledColor: theme.colorScheme.onSurface,
                  emptyColor: theme.colorScheme.outlineVariant,
                ),
            ],
          ),
          if (content.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              content,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (finished)
            OverflowBar(
              alignment: MainAxisAlignment.start,
              overflowAlignment: OverflowBarAlignment.start,
              spacing: 8,
              overflowSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  key: const ValueKey<String>('book-detail-edit-finished'),
                  onPressed: canEdit && !busy ? onEdit : null,
                  icon: const AppIcon(AppGlyph.rateReview, size: 18),
                  label: const Text('编辑读完信息'),
                ),
                TextButton(
                  key: const ValueKey<String>('book-detail-unmark-finished'),
                  onPressed: canEdit && !busy ? onUnmark : null,
                  child: const Text('取消读完'),
                ),
              ],
            )
          else
            FilledButton.tonalIcon(
              key: const ValueKey<String>('book-detail-mark-finished'),
              onPressed: canEdit && !busy ? onEdit : null,
              icon: const AppIcon(AppGlyph.checkCircle),
              label: const Text('标记读完'),
            ),
          if (!canEdit) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '从书架打开详情后可标记读完',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
