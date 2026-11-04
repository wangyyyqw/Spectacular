import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../library/library_store.dart';

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
  });

  /// 打开页面时的书籍条目。
  final BookEntry entry;

  /// 书库存储。
  final LibraryStore library;

  /// 封面选择入口。
  final CoverPicker pickCover;

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
  bool _loading = true;
  bool _saving = false;
  bool _changingCover = false;
  String? _loadError;

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
      _loading = false;
      _loadError = null;
    });
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

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
                ),
                const SizedBox(height: 24),
                Text('图书资料', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('book-detail-title-field'),
                  controller: _titleController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '书名',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('book-detail-author-field'),
                  controller: _authorController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '作者',
                    hintText: '未填写',
                    border: OutlineInputBorder(),
                  ),
                ),
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
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 10),
                if (_tags.isEmpty)
                  Text(
                    '暂无标签',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
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
                      icon: const Icon(Icons.add),
                    ),
                  ),
                  onSubmitted: (_) => _createTag(),
                ),
                const Divider(height: 40),
                Text('图书信息', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: <Widget>[
                    _MetaItem(
                      label: '章节',
                      value: '${_entry.spineCount ?? 0} 章',
                    ),
                    _MetaItem(label: '导入', value: _formatDate(_entry.addedAt)),
                    _MetaItem(
                      label: '最近阅读',
                      value: _entry.lastReadAt == null
                          ? '未读'
                          : _formatDate(_entry.lastReadAt!),
                    ),
                    _MetaItem(
                      label: '可读性',
                      value:
                          'L${_entry.readabilityLevel} '
                          '${_levelLabels[_entry.readabilityLevel.clamp(0, 4)]}',
                    ),
                  ],
                ),
                const Divider(height: 40),
                Text('导入报告', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _ImportReports(library: widget.library, bookId: _entry.id),
              ],
            ),
    );
  }

  static const _levelLabels = <String>['完整', '已修复', '部分降级', '结构异常', '无法阅读'];

  static String _formatDate(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

class _CoverEditor extends StatelessWidget {
  const _CoverEditor({
    required this.entry,
    required this.busy,
    required this.onChange,
  });

  final BookEntry entry;
  final bool busy;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _BookCover(entry: entry),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                entry.author.isEmpty ? '未知作者' : entry.author,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey<String>('book-detail-change-cover'),
                onPressed: busy ? null : onChange,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                label: Text(busy ? '正在更新…' : '更换封面'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.entry});

  final BookEntry entry;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(
          1,
          entry.coverHue.toDouble(),
          0.42,
          0.38,
        ).toColor(),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        entry.title.isEmpty ? '书' : entry.title.characters.first,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(color: Colors.white),
      ),
    );
    final path = entry.coverPath;
    return SizedBox(
      key: const ValueKey<String>('book-detail-page-cover'),
      width: 120,
      height: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: path == null
            ? placeholder
            : Image.file(
                File(path),
                key: ValueKey<String>('cover-$path'),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                cacheWidth: 480,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        Text(value, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ImportReports extends StatelessWidget {
  const _ImportReports({required this.library, required this.bookId});

  final LibraryStore library;
  final String bookId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<ImportReportEntry>>(
      future: library.importReports(bookId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final items = snapshot.data ?? const <ImportReportEntry>[];
        if (items.isEmpty) {
          return Text(
            '无修复或告警',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[for (final item in items) _ReportRow(item: item)],
        );
      },
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.item});

  final ImportReportEntry item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (item.severity) {
      >= 2 => ('错误', theme.colorScheme.error),
      1 => ('警告', theme.colorScheme.tertiary),
      _ => ('提示', theme.colorScheme.outline),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.code,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(item.message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
