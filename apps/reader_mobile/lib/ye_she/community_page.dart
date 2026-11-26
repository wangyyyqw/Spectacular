import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'ye_she_controller.dart';
import '../rea_micro/rea_micro_controller.dart';
import 'ye_she_models.dart';
import 'ye_she_visuals.dart';

/// 阅微社区：我的收藏与公开读书想法。
class CommunityPage extends StatefulWidget {
  /// 创建页面。
  const CommunityPage({
    super.key,
    this.controller,
    this.account,
    this.tokenProvider,
    this.currentUserName = '',
    this.currentUserAvatar = '',
  }) : assert(controller != null || tokenProvider != null);

  /// 可注入的控制器，供页面测试使用。
  final YeSheController? controller;
  final ReaMicroController? account;

  /// 当前阅微令牌提供者。
  final String? Function()? tokenProvider;

  /// 当前阅微账号昵称。
  final String currentUserName;

  /// 当前阅微账号头像。
  final String currentUserAvatar;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  late final YeSheController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        YeSheController(
          tokenProvider: widget.tokenProvider!,
          pageCache: widget.account?.pageCache,
          onUnavailable: widget.account?.reportUnavailable,
        );
    widget.account?.pageRefresh.addListener(_controller.refreshCommunity);
    unawaited(_controller.loadCommunity());
  }

  @override
  void dispose() {
    widget.account?.pageRefresh.removeListener(_controller.refreshCommunity);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey<String>('community-page'),
      body: Column(
        children: <Widget>[
          SafeArea(bottom: false, child: _header(theme)),
          Expanded(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, child) {
                if (!_controller.signedIn) {
                  return const _CommunitySignedOutView();
                }
                if (_controller.loadingCommunity &&
                    !_controller.loadedCommunity) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _controller.refreshCommunity,
                  child: _content(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: YeSheTokens.headerGradient(context),
        border: Border(bottom: BorderSide(color: YeSheTokens.line(context))),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -34,
            top: -50,
            child: Container(
              width: 154,
              height: 154,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: YeSheTokens.jade(context).withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Builder(
                  builder: (context) {
                    final canPop = Navigator.of(context).canPop();
                    return IconButton(
                      tooltip: canPop ? '返回' : '社区',
                      onPressed: canPop
                          ? () => Navigator.of(context).maybePop()
                          : null,
                      icon: AppIcon(
                        canPop ? AppGlyph.arrowBack : AppGlyph.highlighter,
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '社区',
                          key: const ValueKey<String>('community-header-title'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '收藏与阅微读者的公开想法',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, child) => IconButton(
                    key: const ValueKey<String>('community-refresh'),
                    tooltip: '刷新社区',
                    onPressed: _controller.loadingCommunity
                        ? null
                        : () => unawaited(_controller.refreshCommunity()),
                    icon: const AppIcon(AppGlyph.refresh),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final theme = Theme.of(context);
    final collections = _controller.collections;
    final thoughts = _controller.thoughts;
    return ListView(
      key: const PageStorageKey<String>('community-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        if (_controller.loadingCommunity) const LinearProgressIndicator(),
        _errorCard(_controller.communityError),
        _CommunityCard(
          key: const ValueKey<String>('community-collections'),
          icon: AppGlyph.bookmark,
          title: '我的收藏',
          subtitle: '${collections.length} 条',
          trailing: collections.isEmpty
              ? null
              : YeSheTag(
                  '${collections.length} 条',
                  color: YeSheTokens.jade(context),
                ),
          child: collections.isEmpty
              ? const YeSheEmpty('还没有收藏社区想法')
              : Column(
                  children: <Widget>[
                    for (final item in collections)
                      _CollectionTile(
                        item: item,
                        busy: _controller.actionBusy,
                        onRemove: () => _uncollect(item),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _CommunityCard(
          key: const ValueKey<String>('community-thoughts'),
          icon: AppGlyph.highlighter,
          title: '社区想法',
          subtitle: '${thoughts.length} 条公开笔记',
          trailing: thoughts.isEmpty
              ? null
              : YeSheTag(
                  '${thoughts.length} 条',
                  color: YeSheTokens.jade(context),
                ),
          child: thoughts.isEmpty
              ? const YeSheEmpty('暂无公开读书想法')
              : Column(
                  children: <Widget>[
                    for (final thought in thoughts)
                      _ThoughtTile(
                        thought: thought,
                        collected: _collectionTypeOf(thought.id, 1) != null,
                        appreciated: _collectionTypeOf(thought.id, 2) != null,
                        busy: _controller.actionBusy,
                        onCollect: () => _toggleThought(thought, 1),
                        onAppreciate: () => _toggleThought(thought, 2),
                        onCollectors: () => _showCollectors(thought),
                      ),
                  ],
                ),
        ),
        if (widget.currentUserName.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '以 ${widget.currentUserName.trim()} 的阅微账号浏览',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _errorCard(String? error) {
    if (error == null || error.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.22),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppIcon(AppGlyph.warning, color: theme.colorScheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: _controller.loadingCommunity
                  ? null
                  : () => unawaited(_controller.refreshCommunity()),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  int? _collectionTypeOf(int markId, int collectionType) {
    for (final entry in _controller.collections) {
      if (entry.markId == markId && entry.collectionType == collectionType) {
        return entry.collectionType;
      }
    }
    return null;
  }

  Future<void> _toggleThought(YeSheThought thought, int collectionType) async {
    final existing = _collectionTypeOf(thought.id, collectionType);
    final result = existing == null
        ? await _controller.collectThought(
            markId: thought.id,
            collectionType: collectionType,
          )
        : await _controller.uncollectThought(
            markId: thought.id,
            collectionType: existing,
          );
    _showResult(result);
  }

  Future<void> _uncollect(YeSheCollectionEntry item) async {
    final result = await _controller.uncollectThought(
      markId: item.markId,
      collectionType: item.collectionType,
    );
    _showResult(result);
  }

  Future<void> _showCollectors(YeSheThought thought) async {
    final collectors = await _controller.loadMarkCollectors(thought.id);
    if (!mounted) return;
    await showReaderBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text('收藏者', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (collectors.isEmpty)
            const YeSheEmpty('暂无人收藏')
          else
            for (final collector in collectors)
              ListTile(
                leading: YeSheAvatar(
                  url: yeSheText(
                    collector['avatar'] ??
                        collector['userAvatar'] ??
                        collector['avatarUrl'],
                  ),
                  size: 34,
                  semanticsLabel: '收藏者头像',
                ),
                title: Text(_collectorName(collector)),
                subtitle: Text(
                  yeSheText(collector['title'] ?? collector['levelName']),
                ),
              ),
        ],
      ),
    );
  }

  String _collectorName(Map<String, dynamic> collector) {
    final name = yeSheText(
      collector['nickName'] ?? collector['userName'] ?? collector['name'],
    );
    return name.trim().isEmpty ? '阅微用户' : name;
  }

  void _showResult(YeSheActionResult result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final AppGlyph icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: YeSheTokens.paper(context),
        borderRadius: ReaderUiStyle.cardRadiusOf(Theme.of(context)),
        border: Border.all(color: YeSheTokens.line(context)),
        boxShadow: YeSheTokens.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: YeSheTokens.vermilion(context).withValues(alpha: 0.09),
                  borderRadius: ReaderUiStyle.controlRadiusOf(
                    Theme.of(context),
                  ),
                ),
                child: AppIcon(
                  icon,
                  size: 17,
                  color: YeSheTokens.vermilion(context),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.item,
    required this.busy,
    required this.onRemove,
  });

  final YeSheCollectionEntry item;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(9, 8, 4, 8),
      decoration: BoxDecoration(
        color: YeSheTokens.wash(context),
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
        border: Border.all(color: YeSheTokens.line(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 48,
            height: 58,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                YeSheCover(
                  url: item.bookCover,
                  width: 42,
                  height: 58,
                  borderRadius: 6,
                  semanticsLabel: '收藏书封',
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: YeSheAvatar(
                    url: item.userAvatar,
                    size: 22,
                    ringColor: YeSheTokens.wash(context),
                    semanticsLabel: '${item.userName}的头像',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 3),
                Text(
                  <String>[
                    if (item.bookName.trim().isNotEmpty) item.bookName,
                    if (item.userName.trim().isNotEmpty) item.userName,
                    if (item.collectionName.trim().isNotEmpty)
                      item.collectionName,
                    if (item.collectedAt != null)
                      _formatDateTime(item.collectedAt!),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '取消收藏',
            onPressed: busy ? null : onRemove,
            icon: const AppIcon(AppGlyph.bookmark, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ThoughtTile extends StatelessWidget {
  const _ThoughtTile({
    required this.thought,
    required this.collected,
    required this.appreciated,
    required this.busy,
    required this.onCollect,
    required this.onAppreciate,
    required this.onCollectors,
  });

  final YeSheThought thought;
  final bool collected;
  final bool appreciated;
  final bool busy;
  final VoidCallback onCollect;
  final VoidCallback onAppreciate;
  final VoidCallback onCollectors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 8),
      decoration: BoxDecoration(
        color: YeSheTokens.wash(context),
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
        border: Border.all(color: YeSheTokens.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              YeSheAvatar(
                url: thought.userAvatar,
                size: 30,
                semanticsLabel: '${thought.userName}的头像',
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      thought.userName.isEmpty ? '阅微读者' : thought.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (thought.title.trim().isNotEmpty ||
                        thought.userLevel > 0)
                      Text(
                        <String>[
                          if (thought.title.trim().isNotEmpty) thought.title,
                          if (thought.userLevel > 0) '${thought.userLevel} 级',
                        ].join(' · '),
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              if (thought.createdAt != null)
                Text(
                  _formatDateTime(thought.createdAt!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            thought.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
          if (thought.bookName.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                YeSheCover(
                  url: thought.bookCover,
                  width: 32,
                  height: 43,
                  borderRadius: 5,
                  semanticsLabel: '想法书封',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    <String>[
                      thought.bookName,
                      if (thought.chapter.trim().isNotEmpty) thought.chapter,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 2,
            children: <Widget>[
              TextButton.icon(
                onPressed: onCollectors,
                icon: const AppIcon(AppGlyph.profile, size: 15),
                label: const Text('收藏者'),
              ),
              TextButton.icon(
                onPressed: busy ? null : onCollect,
                icon: AppIcon(
                  collected ? AppGlyph.bookmark : AppGlyph.bookmarkAdd,
                  size: 15,
                ),
                label: Text(collected ? '取消收藏' : '收藏'),
              ),
              TextButton.icon(
                onPressed: busy ? null : onAppreciate,
                icon: AppIcon(
                  appreciated ? AppGlyph.checkCircle : AppGlyph.star,
                  size: 15,
                ),
                label: Text(appreciated ? '取消赞赏' : '赞赏'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommunitySignedOutView extends StatelessWidget {
  const _CommunitySignedOutView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey<String>('community-signed-out'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
          decoration: BoxDecoration(
            color: YeSheTokens.paper(context),
            borderRadius: ReaderUiStyle.cardRadiusOf(Theme.of(context)),
            border: Border.all(color: YeSheTokens.line(context)),
            boxShadow: YeSheTokens.cardShadow(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ClipOval(
                child: Image.asset(
                  YeSheTokens.defaultAvatar,
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '登录阅微后查看社区',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '社区复用阅微账号，展示你收藏的想法与读者的公开笔记。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
