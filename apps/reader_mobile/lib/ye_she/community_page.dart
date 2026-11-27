import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'ye_she_controller.dart';
import 'community_feed.dart';
import 'community_navigation.dart';
import '../rea_micro/rea_micro_controller.dart';
import '../rea_micro/rea_micro_models.dart';
import 'ye_she_models.dart';
import 'ye_she_visuals.dart';

/// 阅微社区：想法、收藏与全站书评。
class CommunityPage extends StatefulWidget {
  /// 创建页面。
  const CommunityPage({
    super.key,
    this.controller,
    this.account,
    this.tokenProvider,
  }) : assert(controller != null || tokenProvider != null);

  /// 可注入的控制器，供页面测试使用。
  final YeSheController? controller;
  final ReaMicroController? account;

  /// 当前阅微令牌提供者。
  final String? Function()? tokenProvider;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with SingleTickerProviderStateMixin {
  late final YeSheController _controller;
  late final TabController _tabs;
  late final CommunityFeed<ReaMicroBookReview> _reviews;
  String? _token;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        YeSheController(
          tokenProvider: widget.tokenProvider!,
          pageCache: widget.account?.pageCache,
          onUnavailable: widget.account?.reportUnavailable,
        );
    _token = _controller.tokenProvider();
    _tabs = TabController(length: 3, vsync: this)..addListener(_selectTab);
    _reviews = CommunityFeed((page) async {
      final account = widget.account;
      if (account == null) throw StateError('书评需要阅微账号');
      final items = await account.loadReviewFlow(page: page);
      return (items: items, hasMore: items.length >= 20);
    }, (review) => review.id);
    widget.account?.addListener(_checkAccount);
    widget.account?.pageRefresh.addListener(_refresh);
    _selectTab();
  }

  void _checkAccount() {
    final token = _controller.tokenProvider();
    if (token == _token) return;
    _token = token;
    _controller.thoughtFeed.clear();
    _controller.collectionFeed.clear();
    _reviews.clear();
    _selectTab();
  }

  void _selectTab() {
    if (!_controller.signedIn) return;
    if (_tabs.index == 0) unawaited(_controller.thoughtFeed.ensureLoaded());
    if (_tabs.index < 2) unawaited(_controller.collectionFeed.ensureLoaded());
    if (_tabs.index == 2) unawaited(_reviews.ensureLoaded());
  }

  Future<void> _refresh() async {
    if (!_controller.signedIn) return;
    switch (_tabs.index) {
      case 0:
        await Future.wait([
          _controller.thoughtFeed.refresh(),
          _controller.collectionFeed.refresh(),
        ]);
      case 1:
        await _controller.collectionFeed.refresh();
      case 2:
        await _reviews.refresh();
    }
  }

  @override
  void dispose() {
    widget.account?.removeListener(_checkAccount);
    widget.account?.pageRefresh.removeListener(_refresh);
    _tabs.dispose();
    _reviews.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _controller,
      _tabs,
      _controller.thoughtFeed,
      _controller.collectionFeed,
      _reviews,
    ]),
    builder: (context, child) {
      final feed = switch (_tabs.index) {
        0 => _controller.thoughtFeed,
        1 => _controller.collectionFeed,
        _ => _reviews,
      };
      return Scaffold(
        key: const ValueKey('community-page'),
        appBar: communityAppBar(
          context,
          prefix: 'community',
          title: '社区',
          refresh: _controller.signedIn && !feed.loading ? _refresh : null,
        ),
        body: Column(
          children: [
            CommunityTabs(
              prefix: 'community',
              controller: _tabs,
              tabs: const [
                ('thoughts', AppGlyph.highlighter, '想法'),
                ('collections', AppGlyph.bookmark, '收藏'),
                ('reviews', AppGlyph.review, '书评'),
              ],
            ),
            Expanded(
              child: !_controller.signedIn
                  ? const _CommunitySignedOutView()
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _feedList(
                          'thoughts',
                          _controller.thoughtFeed,
                          '暂无公开读书想法',
                          (thought) => _ThoughtTile(
                            thought: thought,
                            collected: _collectionTypeOf(thought.id, 1) != null,
                            appreciated:
                                _collectionTypeOf(thought.id, 2) != null,
                            busy: _controller.actionBusy,
                            onCollect: () => _toggleThought(thought, 1),
                            onAppreciate: () => _toggleThought(thought, 2),
                            onCollectors: () => _showCollectors(thought),
                          ),
                        ),
                        _feedList(
                          'collections',
                          _controller.collectionFeed,
                          '还没有收藏社区想法',
                          (item) => _CollectionTile(
                            item: item,
                            busy: _controller.actionBusy,
                            onRemove: () => _uncollect(item),
                          ),
                        ),
                        _feedList(
                          'reviews',
                          _reviews,
                          '暂无公开书评',
                          (review) => Card(
                            child: ListTile(
                              leading: YeSheCover(
                                url: review.bookCover,
                                width: 40,
                                height: 54,
                                semanticsLabel: '书评封面',
                              ),
                              title: Text(
                                review.bookName.isEmpty
                                    ? '未知书名'
                                    : review.bookName,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    [
                                      review.userName.isEmpty
                                          ? '阅微读者'
                                          : review.userName,
                                      if (review.rating > 0)
                                        '${review.rating} 分',
                                    ].join(' · '),
                                  ),
                                  if (review.comment.isNotEmpty)
                                    Text(review.comment),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );

  Widget _feedList<T>(
    String key,
    CommunityFeed<T> feed,
    String empty,
    Widget Function(T) tile,
  ) => RefreshIndicator(
    onRefresh: _refresh,
    child: NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.extentAfter < 300 &&
            feed.hasMore &&
            feed.error == null &&
            !feed.loading) {
          unawaited(feed.next());
        }
        return false;
      },
      child: ListView.builder(
        key: PageStorageKey('community-$key'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        itemCount: feed.items.length + 1,
        itemBuilder: (context, index) {
          if (index < feed.items.length) return tile(feed.items[index]);
          if (feed.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (feed.error != null) {
            return Column(
              children: [
                Text('加载失败：${feed.error}'),
                TextButton(onPressed: feed.retry, child: const Text('重试')),
              ],
            );
          }
          if (feed.items.isEmpty) return YeSheEmpty(empty);
          if (feed.hasMore) {
            return TextButton(onPressed: feed.next, child: const Text('加载更多'));
          }
          return const SizedBox.shrink();
        },
      ),
    ),
  );

  int? _collectionTypeOf(int markId, int collectionType) {
    for (final entry in _controller.collectionFeed.items) {
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
                '登录阅微账号后，可浏览读者的公开想法与书评，查看自己的收藏。',
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
