import 'dart:async';

import 'package:flutter/material.dart';

import '../home/book_cover_image.dart';
import '../library/library_store.dart';
import 'rea_micro_controller.dart';
import 'rea_micro_models.dart';
import 'rea_micro_source_icon.dart';

/// 将本地书籍公开关联到阅微云端书籍。
///
/// 页面按平台或出版方渐进展示聚合候选，关联后安排阅读数据同步；
/// 失败的数据保留在本地，由控制器在联网后重试。
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
  List<ReaMicroPublicReadingGroup>? _groups;
  ReaMicroPublicReadingCandidate? _selected;
  String? _error;
  bool _linking = false;
  int _searchGeneration = 0;
  final Set<String> _expandedSources = {};

  ReaMicroBookLink? get _link => widget.controller.links[widget.book.id];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    unawaited(_search());
  }

  @override
  void dispose() {
    _searchGeneration++;
    widget.controller.removeListener(_onControllerChanged);
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
      _error = null;
      _groups = null;
      _selected = null;
      _expandedSources.clear();
    });
    void update(List<ReaMicroPublicReadingGroup> groups) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _groups = groups;
        // 渐进返回时保留用户已经选中的版本。
        if (_selected == null) {
          for (final group in groups) {
            if (group.candidates.isNotEmpty &&
                group.candidates.first.linkable) {
              _selected = group.candidates.first;
              return;
            }
          }
        }
      });
    }

    try {
      final groups = await widget.controller.searchPublicReadingCandidates(
        name: widget.book.title,
        author: widget.book.author,
        onUpdate: update,
        isCancelled: () => !mounted || generation != _searchGeneration,
      );
      if (!mounted || generation != _searchGeneration) return;
      update(groups);
      setState(() {
        if (groups.isEmpty) _error = '没有找到匹配版本，请重新搜索';
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _error = '$error');
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
        thirdParty: candidate.thirdParty,
      ),
    );
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
    _searchGeneration++;
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
        appBar: AppBar(
          title: const Text('关联书籍'),
          actions: [
            IconButton(
              key: const ValueKey('public-reading-search'),
              tooltip: '重新搜索',
              onPressed: _linking ? null : _search,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
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
                          expanded: _expandedSources.contains(
                            group.publisherName,
                          ),
                          onToggle: () => setState(() {
                            if (!_expandedSources.add(group.publisherName)) {
                              _expandedSources.remove(group.publisherName);
                            }
                          }),
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
                if (link != null)
                  TextButton(
                    onPressed: _linking ? null : _unlink,
                    child: const Text('解除关联'),
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
    required this.expanded,
    required this.onToggle,
    required this.selected,
    required this.currentLink,
    required this.onSelected,
  });

  final ReaMicroPublicReadingGroup group;
  final bool expanded;
  final VoidCallback onToggle;
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
          InkWell(
            key: ValueKey(
              'public-reading-source-toggle-${group.publisherName}',
            ),
            onTap: group.candidates.length > 1 ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: <Widget>[
                  ReaMicroSourceIcon(source: group.publisherName),
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
                  if (group.candidates.length > 1) ...[
                    const SizedBox(width: 6),
                    Icon(expanded ? Icons.expand_less : Icons.chevron_right),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          for (final candidate
              in expanded ? group.candidates : group.candidates.take(1))
            _CandidateTile(
              candidate: candidate,
              selected: selected?.key == candidate.key,
              linked:
                  candidate.thirdParty == null &&
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
    final scaler = MediaQuery.textScalerOf(context);
    final titleStyle = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 16,
      height: 1.4,
      fontWeight: selected ? FontWeight.w600 : null,
    );
    final detailStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: 12,
      height: 1.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final titleHeight = scaler.scale(16) * 1.4;
    final detailHeight = scaler.scale(12) * 1.4;
    final contentHeight = titleHeight + 2 * detailHeight + 4;
    final thirdParty = candidate.thirdParty;
    final details = <String>{
      if (book.author.trim().isNotEmpty) book.author.trim(),
      if (candidate.publisher?.publisher.trim().isNotEmpty == true)
        candidate.publisher!.publisher.trim(),
      if (thirdParty?.status == '出版' && thirdParty!.publisher.isNotEmpty)
        thirdParty.publisher,
      if (!candidate.linkable) '未提供出版方',
      if (candidate.status.isNotEmpty) candidate.status,
      if (candidate.words.isNotEmpty) candidate.words,
      if (thirdParty?.price.isNotEmpty == true) thirdParty!.price,
      if (linked) '当前关联',
    }.join(' · ');
    final cover = candidate.cover.startsWith('//')
        ? 'https:${candidate.cover}'
        : candidate.cover;
    final coverHost = Uri.tryParse(cover)?.host ?? '';
    final headers = coverHost.endsWith('.doubanio.com')
        ? const {
            'Referer': 'https://book.douban.com/',
            'User-Agent': 'Mozilla/5.0',
          }
        : const <String, String>{};
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
            crossAxisAlignment: CrossAxisAlignment.center,
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
              BookCoverImage(
                key: ValueKey('public-reading-result-cover-${candidate.key}'),
                book: BookEntry(
                  id: candidate.key,
                  title: book.name,
                  author: book.author,
                  filePath: '',
                  addedAt: DateTime(2026),
                  remoteCoverUrl: cover,
                ),
                width: contentHeight * .75,
                height: contentHeight,
                httpHeaders: headers,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  key: ValueKey('public-reading-result-text-${candidate.key}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      height: titleHeight,
                      child: Text(
                        book.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: detailHeight,
                      child: Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: detailStyle,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: detailHeight,
                      child: Text(
                        candidate.intro.split(RegExp(r'\r?\n')).first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: detailStyle,
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
