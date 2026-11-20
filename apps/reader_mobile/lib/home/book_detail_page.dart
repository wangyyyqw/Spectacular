import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../library/library_store.dart';
import '../txt/txt_book_service.dart';
import '../txt/txt_chapter_rule_page.dart';
import 'book_cover_image.dart';
import 'finish_book_sheet.dart';
import 'reading_insights.dart';
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
  final TextEditingController _tagController = TextEditingController();

  List<BookTag> _tags = const <BookTag>[];
  Set<String> _selectedTagIds = <String>{};
  _BookReadingStats _readingStats = const _BookReadingStats.empty();
  ReaderProgress? _progress;
  BookReview? _review;
  bool _loading = true;
  bool _saving = false;
  bool _changingCover = false;
  bool _canRechapter = false;
  String? _loadError;

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
    final entry = await widget.library.bookById(_entry.id);
    final tags = await widget.library.listTags();
    final selected = await widget.library.bookTags(_entry.id);
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

  Future<void> _saveMetadata() async {
    if (_saving) {
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      _showMessage('书名不能为空');
      return;
    }
    setState(() => _saving = true);
    try {
      final entry = await widget.library.updateBookMetadata(
        _entry.id,
        title: _titleController.text,
        author: _authorController.text,
        description: _descriptionController.text,
      );
      if (!mounted) {
        return;
      }
      _titleController.text = entry.title;
      _authorController.text = entry.author;
      _descriptionController.text = entry.description;
      setState(() {
        _entry = entry;
      });
      _showMessage('图书资料已保存');
    } on LibraryImportException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _changeCover() async {
    if (_changingCover) {
      return;
    }
    CoverSelection? selection;
    try {
      selection = await widget.pickCover();
    } catch (_) {
      _showMessage('选择封面失败，请重试');
      return;
    }
    if (selection == null || !mounted) {
      return;
    }
    setState(() => _changingCover = true);
    try {
      final entry = await widget.library.replaceCover(
        _entry.id,
        selection.bytes,
        extension: selection.extension,
      );
      if (!mounted) {
        return;
      }
      setState(() => _entry = entry);
      _showMessage('封面已更新');
    } on LibraryImportException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('封面更新失败，请重试');
    } finally {
      if (mounted) {
        setState(() => _changingCover = false);
      }
    }
  }

  Future<void> _toggleTag(BookTag tag) async {
    try {
      if (_selectedTagIds.contains(tag.id)) {
        await widget.library.removeBookTag(_entry.id, tag.id);
      } else {
        await widget.library.addBookTag(_entry.id, tag.id);
      }
      await _reloadTags();
    } on LibraryImportException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _createTag() async {
    final name = _tagController.text.trim();
    if (name.isEmpty) {
      return;
    }
    try {
      final tag = await widget.library.createTag(name);
      await widget.library.addBookTag(_entry.id, tag.id);
      _tagController.clear();
      await _reloadTags();
    } on LibraryImportException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _reloadTags() async {
    final tags = await widget.library.listTags();
    final selected = await widget.library.bookTags(_entry.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _tags = tags;
      _selectedTagIds = <String>{for (final tag in selected) tag.id};
    });
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
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('取消读完标记？'),
        content: const Text('书评和评分会保留，阅读进度不会改变。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留'),
          ),
          FilledButton(
            key: const ValueKey<String>('book-detail-unmark-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('取消标记'),
          ),
        ],
      ),
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

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
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
      if (entry != null && mounted) setState(() => _entry = entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave =
        !_saving && !_loading && _hasMetadataChanges && _loadError == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('图书详情'),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('book-detail-save'),
            onPressed: canSave ? _saveMetadata : null,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(child: Text(_loadError!))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: <Widget>[
                _CoverEditor(
                  entry: _entry,
                  busy: _changingCover,
                  onChange: _changeCover,
                  titleController: _titleController,
                  authorController: _authorController,
                ),
                const Divider(height: 32),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('book-detail-description-field'),
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '简介',
                    hintText: '写下这本书的简介',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text('标签', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '点击标签可添加或移除；输入新名称创建标签。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                if (_tags.isEmpty)
                  Text(
                    '暂无标签',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final tag in _tags)
                        FilterChip(
                          key: ValueKey<String>('book-detail-tag-${tag.id}'),
                          label: Text(tag.name),
                          selected: _selectedTagIds.contains(tag.id),
                          showCheckmark: false,
                          onSelected: (_) => _toggleTag(tag),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('book-detail-new-tag-field'),
                  controller: _tagController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '新建标签',
                    hintText: '例如：科幻、待读',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      key: const ValueKey<String>('book-detail-add-tag'),
                      tooltip: '创建并添加标签',
                      onPressed: _tagController.text.trim().isEmpty
                          ? null
                          : _createTag,
                      icon: const AppIcon(AppGlyph.add),
                    ),
                  ),
                  onSubmitted: (_) => _createTag(),
                ),
                if (_canRechapter)
                  ListTile(
                    key: const ValueKey('book-detail-page-chapters'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('章节正则'),
                    subtitle: const Text('预览并重新划分当前正文的章节'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openChapterRules,
                  ),
                const Divider(height: 40),
                Text('阅读记录', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                _ReadingStatsSection(stats: _readingStats),
                const Divider(height: 40),
                Text('阅读状态', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                _ReadingStatusSection(
                  progress: _progress,
                  review: _review,
                  canEdit: widget.progressStore != null,
                  onEdit: _editFinished,
                  onUnmark: _unmarkFinished,
                ),
              ],
            ),
    );
  }
}

String _formatReadingDuration(Duration duration) {
  if (duration <= Duration.zero) {
    return '0 分钟';
  }
  final minutes = (duration.inSeconds / 60).ceil();
  if (minutes < 1) {
    return '<1 分钟';
  }
  if (minutes < 60) {
    return '$minutes 分钟';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
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

class _CoverEditor extends StatelessWidget {
  const _CoverEditor({
    required this.entry,
    required this.busy,
    required this.onChange,
    required this.titleController,
    required this.authorController,
  });

  final BookEntry entry;
  final bool busy;
  final VoidCallback onChange;
  final TextEditingController titleController;
  final TextEditingController authorController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          button: true,
          enabled: !busy,
          label: '点击更换封面',
          child: GestureDetector(
            key: const ValueKey('book-detail-page-cover'),
            onTap: busy ? null : onChange,
            child: SizedBox(
              width: 120,
              height: 160,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  BookCoverImage(book: entry, width: 120, height: 160),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: .9),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : AppIcon(
                                AppGlyph.image,
                                size: 18,
                                color: theme.colorScheme.onSurface,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('图书资料', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey<String>('book-detail-title-field'),
                controller: titleController,
                textInputAction: TextInputAction.next,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '书名',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey<String>('book-detail-author-field'),
                controller: authorController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '作者',
                  hintText: '未填写',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
    final byDay = <DateTime, _BookDailyReading>{};
    var totalDuration = Duration.zero;
    var sessionCount = 0;
    var pageTurns = 0;
    var charactersRead = 0;

    for (final session in sessions) {
      if (session.duration < minimumCountedSessionDuration ||
          !session.endedAt.isAfter(session.startedAt)) {
        continue;
      }
      sessionCount += 1;
      totalDuration += session.duration;
      pageTurns += session.pageTurns;
      charactersRead += session.charactersRead;

      final startedDay = DateTime(
        session.startedAt.year,
        session.startedAt.month,
        session.startedAt.day,
      );
      final started = byDay.putIfAbsent(
        startedDay,
        () => _BookDailyReading(date: startedDay),
      );
      started.sessionCount += 1;
      started.pageTurns += session.pageTurns;
      started.charactersRead += session.charactersRead;

      var cursor = session.startedAt;
      while (cursor.isBefore(session.endedAt)) {
        final dayStart = DateTime(cursor.year, cursor.month, cursor.day);
        final nextDay = DateTime(cursor.year, cursor.month, cursor.day + 1);
        final segmentEnd = session.endedAt.isBefore(nextDay)
            ? session.endedAt
            : nextDay;
        final overlap = segmentEnd.difference(cursor);
        if (overlap > Duration.zero) {
          final day = byDay.putIfAbsent(
            dayStart,
            () => _BookDailyReading(date: dayStart),
          );
          day.duration += overlap;
        }
        cursor = segmentEnd;
      }
    }

    final today = DateTime(now.year, now.month, now.day);
    return _BookReadingStats(
      totalDuration: totalDuration,
      sessionCount: sessionCount,
      pageTurns: pageTurns,
      charactersRead: charactersRead,
      readingDays: byDay.values
          .where((day) => day.duration > Duration.zero)
          .length,
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
    final theme = Theme.of(context);
    if (stats.sessionCount == 0) {
      return Text(
        '暂无阅读记录，开始阅读后会在这里汇总。',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: <Widget>[
            _ReadingMetric(
              label: '累计时长',
              value: _formatReadingDuration(stats.totalDuration),
              valueKey: const ValueKey<String>('book-detail-total-duration'),
            ),
            _ReadingMetric(
              label: '阅读次数',
              value: '${stats.sessionCount}',
              valueKey: const ValueKey<String>('book-detail-session-count'),
            ),
            _ReadingMetric(
              label: '阅读天数',
              value: '${stats.readingDays}',
              valueKey: const ValueKey<String>('book-detail-reading-days'),
            ),
            _ReadingMetric(
              label: '翻页次数',
              value: '${stats.pageTurns}',
              valueKey: const ValueKey<String>('book-detail-page-turns'),
            ),
            _ReadingMetric(
              label: '阅读字数',
              value: _formatReadingCharacters(stats.charactersRead),
              valueKey: const ValueKey<String>('book-detail-characters-read'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('最近 7 天', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        for (final day in stats.recentDays) _DailyReadingRow(day: day),
      ],
    );
  }
}

class _ReadingMetric extends StatelessWidget {
  const _ReadingMetric({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          key: valueKey,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DailyReadingRow extends StatelessWidget {
  const _DailyReadingRow({required this.day});

  final _BookDailyReading day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActivity = day.duration > Duration.zero;
    final dateKey = _formatDateKey(day.date);
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
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              _formatDayLabel(day.date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasActivity
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _formatReadingDuration(day.duration),
                  key: ValueKey<String>('book-detail-daily-duration-$dateKey'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasActivity
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: hasActivity ? FontWeight.w600 : null,
                  ),
                ),
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
    required this.onEdit,
    required this.onUnmark,
  });

  final ReaderProgress? progress;
  final BookReview? review;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onUnmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = progress?.finished ?? false;
    final content = review?.content ?? '';
    return Container(
      key: const ValueKey<String>('book-detail-reading-status'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
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
                _ReviewStars(rating: review!.rating!, size: 18),
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
            Row(
              children: <Widget>[
                OutlinedButton.icon(
                  key: const ValueKey<String>('book-detail-edit-finished'),
                  onPressed: canEdit ? onEdit : null,
                  icon: const AppIcon(AppGlyph.rateReview, size: 18),
                  label: const Text('编辑读完信息'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey<String>('book-detail-unmark-finished'),
                  onPressed: canEdit ? onUnmark : null,
                  child: const Text('取消读完'),
                ),
              ],
            )
          else
            FilledButton.tonalIcon(
              key: const ValueKey<String>('book-detail-mark-finished'),
              onPressed: canEdit ? onEdit : null,
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

class _ReviewStars extends StatelessWidget {
  const _ReviewStars({required this.rating, required this.size});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var star = 1; star <= 5; star++)
          AppIcon(
            AppGlyph.star,
            filled: star <= rating,
            size: size,
            color: star <= rating
                ? const Color(0xFFE0A327)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
      ],
    );
  }
}
