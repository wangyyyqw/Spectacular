import 'dart:async';

import 'package:flutter/material.dart';

import '../home/book_cover_image.dart';
import '../library/library_store.dart';
import 'rea_micro_controller.dart';
import 'rea_micro_models.dart';
import 'rea_micro_manual_association_page.dart';

/// 将本地书籍公开关联到阅微云端书籍。
///
/// 页面按出版方分组展示云端候选，关联成功后立即补传本书已有的阅读时长、
/// 阅读位置、划线和想法；失败的数据保留在本地，由控制器在联网后重试。
class ReaMicroPublicReadingPage extends StatefulWidget {
  /// 创建公开阅读页。
  const ReaMicroPublicReadingPage({
    super.key,
    required this.controller,
    required this.book,
  });

  /// 阅微状态控制器。
  final ReaMicroController controller;

  /// 本地书籍。
  final BookEntry book;

  @override
  State<ReaMicroPublicReadingPage> createState() =>
      _ReaMicroPublicReadingPageState();
}

class _ReaMicroPublicReadingPageState extends State<ReaMicroPublicReadingPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.book.title,
  );
  late final TextEditingController _author = TextEditingController(
    text: widget.book.author,
  );
  List<ReaMicroPublicReadingGroup>? _groups;
  ReaMicroPublicReadingCandidate? _selected;
  String? _error;
  bool _searching = false;
  bool _linking = false;
  int _searchGeneration = 0;

  ReaMicroBookLink? get _link => widget.controller.links[widget.book.id];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    unawaited(_search());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _name.dispose();
    _author.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _search() async {
    if (_linking) return;
    final generation = ++_searchGeneration;
    if (!widget.controller.signedIn) {
      setState(() => _error = '请先登录阅微账号');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _groups = null;
      _selected = null;
    });
    try {
      final groups = await widget.controller.searchPublicReadingCandidates(
        name: _name.text,
        author: _author.text,
      );
      if (!mounted || generation != _searchGeneration) return;
      ReaMicroPublicReadingCandidate? selected;
      for (final group in groups) {
        for (final candidate in group.candidates) {
          if (!candidate.linkable) continue;
          selected = candidate;
          break;
        }
        if (selected != null) break;
      }
      setState(() {
        _groups = groups;
        _selected = selected;
        if (groups.isEmpty) _error = '没有找到匹配版本，可调整关键词或手动关联';
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _publishSelected() async {
    final candidate = _selected;
    if (candidate == null || _linking) return;
    if (!candidate.linkable) {
      setState(() => _error = '该版本没有出版方，请选择其他版本或在阅微新建书籍');
      return;
    }
    await _runLink(
      () => widget.controller.registerAndLinkBook(
        widget.book.id,
        cloudBook: candidate.book,
        publisher: candidate.publisher,
      ),
    );
  }

  Future<void> _createAndPublish() async {
    if (_linking) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReaMicroManualAssociationPage(
          controller: widget.controller,
          book: widget.book,
        ),
      ),
    );
    if (changed == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _unlink() async {
    if (_linking) return;
    setState(() {
      _linking = true;
      _error = null;
    });
    try {
      await widget.controller.unlinkBook(widget.book.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _linking = false;
        _error = '解除关联失败：$error';
      });
    }
  }

  Future<void> _runLink(Future<Object?> Function() action) async {
    setState(() {
      _linking = true;
      _error = null;
    });
    try {
      await action();
      widget.controller.scheduleReadingSync(delay: Duration.zero);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _linking = false;
        _error = '关联失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _link;
    final groups = _groups;
    return PopScope(
      canPop: !_linking,
      child: Scaffold(
        key: const ValueKey<String>('reamicro-public-reading-page'),
        appBar: AppBar(title: const Text('关联书籍')),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: _LocalBookHeader(book: widget.book),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: <Widget>[
                    if (link != null) ...<Widget>[
                      _CurrentLinkCard(
                        link: link,
                        linking: _linking,
                        onUnlink: _unlink,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text('聚合搜索', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              '按书名和作者检索，再选择来源平台或出版版本。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const ValueKey<String>(
                                'public-reading-name',
                              ),
                              controller: _name,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => unawaited(_search()),
                              decoration: const InputDecoration(
                                labelText: '阅微书名',
                                prefixIcon: Icon(Icons.book_outlined),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              key: const ValueKey<String>(
                                'public-reading-author',
                              ),
                              controller: _author,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => unawaited(_search()),
                              decoration: const InputDecoration(
                                labelText: '作者（可选）',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const ValueKey<String>(
                                'public-reading-search',
                              ),
                              onPressed: _linking ? null : _search,
                              icon: _searching
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.search),
                              label: Text(_searching ? '正在搜索…' : '搜索关联版本'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        key: const ValueKey<String>('public-reading-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    if (groups != null && groups.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 18),
                      Text('搜索结果', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '共 ${groups.fold<int>(0, (count, group) => count + group.candidates.length)} 个版本',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final group in groups) ...<Widget>[
                        _PublisherGroupCard(
                          group: group,
                          selected: _selected,
                          currentLink: link,
                          onSelected: _linking
                              ? null
                              : (candidate) => setState(() {
                                  _selected = candidate;
                                  _error = null;
                                }),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (groups == null && !_searching && _error == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(child: Text('输入书名后开始搜索')),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton.icon(
                  key: const ValueKey<String>('public-reading-link'),
                  onPressed: _linking || _selected == null
                      ? null
                      : _publishSelected,
                  icon: _linking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(_linking ? '关联中…' : '关联所选版本'),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>('public-reading-new-book'),
                        onPressed: _linking ? null : _createAndPublish,
                        icon: const Icon(Icons.add_link),
                        label: const Text('手动关联'),
                      ),
                    ),
                    if (link != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton(
                          onPressed: _linking ? null : _unlink,
                          child: const Text('解除关联'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalBookHeader extends StatelessWidget {
  const _LocalBookHeader({required this.book});

  final BookEntry book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            BookCoverImage(
              key: const ValueKey<String>('public-reading-cover'),
              book: book,
              width: 64,
              height: 86,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author.isEmpty ? '未知作者' : book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '未关联也保存阅读数据，关联后继续同步到所选版本。',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentLinkCard extends StatelessWidget {
  const _CurrentLinkCard({
    required this.link,
    required this.linking,
    required this.onUnlink,
  });

  final ReaMicroBookLink link;
  final bool linking;
  final Future<void> Function() onUnlink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final public = link.publisherId > 0;
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      child: ListTile(
        leading: const Icon(Icons.cloud_done_outlined),
        title: Text(link.name),
        subtitle: Text(
          '${link.author.isEmpty ? '未知作者' : link.author}'
          ' · ${public ? '已公开关联' : '已关联，缺少出版方'}',
        ),
        trailing: TextButton(
          key: const ValueKey<String>('public-reading-unlink'),
          onPressed: linking ? null : onUnlink,
          child: const Text('解除关联'),
        ),
      ),
    );
  }
}

class _PublisherGroupCard extends StatelessWidget {
  const _PublisherGroupCard({
    required this.group,
    required this.selected,
    required this.currentLink,
    required this.onSelected,
  });

  final ReaMicroPublicReadingGroup group;
  final ReaMicroPublicReadingCandidate? selected;
  final ReaMicroBookLink? currentLink;
  final ValueChanged<ReaMicroPublicReadingCandidate>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey<String>('public-reading-group-${group.publisherName}'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.local_library_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.publisherName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${group.candidates.length} 个版本',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final candidate in group.candidates)
            _CandidateTile(
              candidate: candidate,
              selected: selected?.key == candidate.key,
              linked:
                  currentLink?.cloudBookId == candidate.book.cloudBookId &&
                  (candidate.publisherId <= 0 ||
                      currentLink?.publisherId == candidate.publisherId),
              onTap: onSelected == null ? null : () => onSelected!(candidate),
            ),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.linked,
    required this.onTap,
  });

  final ReaMicroPublicReadingCandidate candidate;
  final bool selected;
  final bool linked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = candidate.book;
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        key: ValueKey<String>('public-reading-candidate-${candidate.key}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      book.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (book.author.trim().isNotEmpty) book.author.trim(),
                        if (candidate.publisher != null &&
                            candidate.publisher!.publisher.trim().isNotEmpty)
                          candidate.publisher!.publisher.trim(),
                        if (!candidate.linkable) '未提供出版方',
                        if (linked) '当前关联',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (linked)
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
