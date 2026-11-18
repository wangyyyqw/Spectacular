import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'ye_she_controller.dart';
import 'ye_she_models.dart';

/// 阅微野社：文房、游艺、见闻。
class YeShePage extends StatefulWidget {
  /// 创建页面。
  const YeShePage({super.key, this.controller, this.tokenProvider})
    : assert(controller != null || tokenProvider != null);

  /// 可注入的控制器，供页面测试使用。
  final YeSheController? controller;

  /// 当前阅微令牌提供者。
  final String? Function()? tokenProvider;

  @override
  State<YeShePage> createState() => _YeShePageState();
}

class _YeShePageState extends State<YeShePage>
    with SingleTickerProviderStateMixin {
  late final YeSheController _controller;
  late final bool _ownsController;
  late final TabController _tabController;
  YeSheRankKind _rankKind = YeSheRankKind.readDuration;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        YeSheController(tokenProvider: widget.tokenProvider!);
    _tabController = TabController(length: 3, vsync: this);
    unawaited(_controller.loadAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('野社'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: _controller,
            builder: (context, child) => IconButton(
              key: const ValueKey<String>('ye-she-refresh'),
              tooltip: '刷新野社',
              onPressed:
                  _controller.loadingStudy ||
                      _controller.loadingPlay ||
                      _controller.loadingDiscover ||
                      _controller.loadingRanks
                  ? null
                  : () => unawaited(_controller.refreshAll()),
              icon: const AppIcon(AppGlyph.refresh),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Widget>[
            Tab(key: ValueKey<String>('ye-she-tab-study'), text: '文房'),
            Tab(key: ValueKey<String>('ye-she-tab-play'), text: '游艺'),
            Tab(key: ValueKey<String>('ye-she-tab-discover'), text: '见闻'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, child) {
          if (!_controller.signedIn) {
            return const _SignedOutView();
          }
          if (_controller.actionBusy) {
            return Column(
              children: <Widget>[
                LinearProgressIndicator(
                  key: const ValueKey<String>('ye-she-action-progress'),
                ),
                Expanded(child: _tabBody()),
              ],
            );
          }
          return _tabBody();
        },
      ),
    );
  }

  Widget _tabBody() {
    return TabBarView(
      controller: _tabController,
      children: <Widget>[
        _refreshable(_buildStudy),
        _refreshable(_buildPlay),
        _refreshable(_buildDiscover),
      ],
    );
  }

  Widget _refreshable(Widget Function() builder) {
    return RefreshIndicator(
      onRefresh: () async {
        await _controller.refreshAll();
      },
      child: builder(),
    );
  }

  Widget _buildStudy() {
    return ListView(
      key: const PageStorageKey<String>('ye-she-study-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        if (_controller.loadingStudy) const LinearProgressIndicator(),
        _errorCard(_controller.studyError),
        _accountCard(),
        _titleCard(),
        _rankCard(),
        _inventoryCard(),
        _societyCard(),
        _guildCard(),
        _collectionsCard(),
      ],
    );
  }

  Widget _buildPlay() {
    return ListView(
      key: const PageStorageKey<String>('ye-she-play-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        if (_controller.loadingPlay) const LinearProgressIndicator(),
        _errorCard(_controller.playError),
        _dailyLoreCard(),
        _merchantCard(),
        _retainerCard(),
        _auctionCard(),
        _gamblingCard(),
      ],
    );
  }

  Widget _buildDiscover() {
    return ListView(
      key: const PageStorageKey<String>('ye-she-discover-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        if (_controller.loadingDiscover) const LinearProgressIndicator(),
        _errorCard(_controller.discoverError),
        _wishCard(),
        _taoistCard(),
        _pawnCard(),
        _dailyShopCard(),
        _voucherShopCard(),
        _marketCard(),
        _medalTreasureCard(),
        _thoughtsCard(),
        _rumorsCard(),
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
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricWrap(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(spacing: 8, runSpacing: 6, children: children),
    );
  }

  Widget _accountCard() {
    final status = _controller.account;
    return _YeCard(
      key: const ValueKey<String>('ye-she-account'),
      icon: AppGlyph.stats,
      title: '文房',
      subtitle: status == null
          ? '账户状态尚未读取'
          : '${status.level} 级 · ${status.exp}/${status.expMax} 阅历',
      child: status == null
          ? const _EmptyHint('账户状态暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _metricWrap(<Widget>[
                  _MetricChip('铜钱', status.coin),
                  _MetricChip('彩筹', status.gem),
                  _MetricChip('玉券', status.voucher),
                ]),
                const SizedBox(height: 10),
                Text(
                  '行商收支 ${_signed(status.travelingMerchantNet)} 铜 · '
                  '聚宝楼收支 ${_signed(status.auctionNet)} 铜',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  Widget _titleCard() {
    final title = _controller.title;
    return _YeCard(
      key: const ValueKey<String>('ye-she-title'),
      icon: AppGlyph.star,
      title: '名帖',
      subtitle: title == null ? '名帖尚未读取' : title.displayName,
      child: title == null
          ? const _EmptyHint('名帖信息暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _InfoLine('当前等级', '${title.level} 级'),
                if (title.sourceName.trim().isNotEmpty)
                  _InfoLine('来源', title.sourceName),
                _InfoLine('升级保底', '${title.upgradePityCount} 次'),
                _InfoLine('传承保底', '${title.heritagePityCount} 次'),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _confirmedAction(
                            title: '升级名帖',
                            message: '升级会消耗社区资源，确定继续吗？',
                            action: _controller.upgradeTitle,
                          ),
                    child: const Text('升级'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _confirmedAction(
                            title: '传承名帖',
                            message: '传承会消耗社区资源，确定继续吗？',
                            action: _controller.heritageTitle,
                          ),
                    child: const Text('传承'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _confirmedAction(
                            title: '弃置名帖',
                            message: '弃置当前名帖可能失去已获得的雅号，确定继续吗？',
                            action: _controller.abandonTitle,
                          ),
                    child: const Text('弃置'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _rankCard() {
    final board = _controller.ranks[_rankKind];
    final theme = Theme.of(context);
    return _YeCard(
      key: const ValueKey<String>('ye-she-ranks'),
      icon: AppGlyph.stats,
      title: '排行榜',
      subtitle: board == null
          ? '阅读、财富、聚宝楼、收藏与名帖'
          : '${_rankKind.label}${board.rankDate.isEmpty ? '' : ' · ${board.rankDate}'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final kind in YeSheRankKind.values)
                ChoiceChip(
                  key: ValueKey<String>('ye-she-rank-${kind.name}'),
                  label: Text(kind.label),
                  selected: kind == _rankKind,
                  onSelected: (_) => setState(() => _rankKind = kind),
                ),
            ],
          ),
          if (_controller.loadingRanks)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            ),
          if (_controller.ranksError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _controller.ranksError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (board == null)
            const _EmptyHint('排行榜暂不可用')
          else if (board.entries.isEmpty)
            const _EmptyHint('榜单暂时没有记录')
          else
            for (final entry in board.entries.take(20))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(
                    '${entry.rank}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                title: Text(
                  entry.nickName.isEmpty ? '阅微用户' : entry.nickName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  <String>[
                    if (entry.title.trim().isNotEmpty) entry.title,
                    if (entry.titleLevel > 0) '名帖 ${entry.titleLevel} 级',
                    '${entry.level} 级',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(_rankValueText(_rankKind, entry.value)),
              ),
          if (board != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                board.my.rank > 0
                    ? '我的排名：第 ${board.my.rank} 名 · '
                          '${_rankValueText(_rankKind, board.my.value)}'
                    : '我的排名：尚未上榜',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _inventoryCard() {
    final seals = _controller.seals;
    final notelets = _controller.notelets;
    final medals = _controller.medals;
    final cards = _controller.callingCards;
    return _YeCard(
      key: const ValueKey<String>('ye-she-inventory'),
      icon: AppGlyph.bookmark,
      title: '清玩 · 鉴赏',
      subtitle: '藏印、花笺、徽章与名片',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _metricWrap(<Widget>[
            _InventoryButton(
              label: '藏印',
              value: '${seals?.items.length ?? 0} 张',
              onPressed: () => _openSignedItems(
                title: '藏印',
                note: seals == null ? null : '印泥 ${seals.inkPasteQuantity} 丸',
                items: seals?.items ?? const <YeSheNamedItem>[],
                actionLabel: '盖章',
                onAction: (item) => _stampSeal(item.id),
              ),
            ),
            _InventoryButton(
              label: '花笺',
              value: '${notelets?.items.length ?? 0} 张',
              onPressed: () => _openSignedItems(
                title: '花笺',
                note: notelets == null
                    ? null
                    : '花笺纸 ${notelets.paperQuantity} 张',
                items: notelets?.items ?? const <YeSheNamedItem>[],
                actionLabel: '使用',
                onAction: (item) => _stampNotelet(item.id),
              ),
            ),
            _InventoryButton(
              label: '徽章',
              value: '${medals?.items.length ?? 0} 枚',
              onPressed: () => _openSignedItems(
                title: '徽章',
                items: medals?.items ?? const <YeSheNamedItem>[],
              ),
            ),
            _InventoryButton(
              label: '名片',
              value: '${cards?.items.length ?? 0} 张',
              onPressed: () => _openSignedItems(
                title: '名片',
                items: cards?.items ?? const <YeSheNamedItem>[],
                actionLabel: '使用',
                onAction: (item) async {
                  final result = await _controller.useCallingCard(item.id);
                  _showResult(result);
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _societyCard() {
    final society = _controller.mySociety;
    final scores = _controller.societyScores;
    return _YeCard(
      key: const ValueKey<String>('ye-she-society'),
      icon: AppGlyph.review,
      title: society?.name.isNotEmpty == true ? society!.name : '文会',
      subtitle: society == null
          ? '尚未加入文会'
          : '${society.level} 级 · ${society.memberCount}/${society.memberLimit} 人 · '
                '本周 ${society.weekScore} 声望',
      child: society == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _EmptyHint('创建或加入一个文会，与同好共读。'),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy ? null : _createSociety,
                    child: const Text('创建文会'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : _joinSocietyByCode,
                    child: const Text('邀请码加入'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : _browsePublicSocieties,
                    child: const Text('公开文会'),
                  ),
                ]),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (society.inviteCode.trim().isNotEmpty)
                  _InfoLine('邀请码', society.inviteCode),
                _InfoLine(
                  '奖励状态',
                  society.claimedRewardName.trim().isEmpty
                      ? society.rewardStatus.trim().isEmpty
                            ? '可领取时请点击领取'
                            : society.rewardStatus
                      : '已领取 ${society.claimedRewardName}',
                ),
                if (scores != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '本周文会声望 ${scores.totalScore}/${scores.maxScore}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      if (scores.weekStart.trim().isNotEmpty)
                        Text(
                          scores.weekStart,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: scores.ratio),
                  if (scores.members.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '本周贡献排行',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final member in scores.members.take(8))
                          Chip(
                            label: Text(
                              '${member.nickName} · ${member.weekScore}',
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ],
                if (society.members.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('成员', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final member in society.members.take(8))
                        Chip(
                          label: Text(
                            '${member.nickName} · ${member.weekScore}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _confirmedAction(
                            title: '领取文会奖励',
                            message: '领取本周文会声望奖励？',
                            action: _controller.claimSocietyReward,
                          ),
                    child: const Text('领取周奖励'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : _updateSocietyCover,
                    child: const Text('修改封面'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : _kickSocietyMember,
                    child: const Text('移出成员'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _confirmedAction(
                            title: '退出文会',
                            message: '退出后将失去当前文会身份，确定继续吗？',
                            action: _controller.quitSociety,
                          ),
                    child: const Text('退出'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _confirmedAction(
                            title: '解散文会',
                            message: '解散文会不可恢复，确定继续吗？',
                            action: _controller.dissolveSociety,
                          ),
                    child: const Text('解散'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _guildCard() {
    final guilds = _controller.guilds;
    final membership = guilds?.membership;
    final joined = membership?.joined == true;
    YeSheMerchantGuild? current;
    if (joined) {
      for (final guild in guilds!.guilds) {
        if (guild.id == membership!.guildId) {
          current = guild;
          break;
        }
      }
    }
    return _YeCard(
      key: const ValueKey<String>('ye-she-guild'),
      icon: AppGlyph.folder,
      title: '商会 · 财富',
      subtitle: joined
          ? '${current?.name ?? '已加入商会'} · 贡献 ${membership!.contribution}'
          : guilds == null
          ? '商会信息尚未读取'
          : '加入费用 ${guilds.joinCost} 铜',
      child: guilds == null
          ? const _EmptyHint('商会信息暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (joined)
                  _actionWrap(<Widget>[
                    TextButton(
                      onPressed: _showGuildMembers,
                      child: const Text('成员'),
                    ),
                    TextButton(
                      onPressed: _showGuildHistory,
                      child: const Text('行商动态'),
                    ),
                    TextButton(
                      onPressed: () => _confirmedAction(
                        title: '退出商会',
                        message: '退出商会后当前贡献等级可能失效，确定继续吗？',
                        action: _controller.leaveGuild,
                      ),
                      child: const Text('退出商会'),
                    ),
                  ])
                else if (guilds.guilds.isEmpty)
                  const _EmptyHint('暂无可加入的商会')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final guild in guilds.guilds)
                        ActionChip(
                          label: Text('${guild.name} · ${guild.memberCount} 人'),
                          onPressed: () => _confirmedAction(
                            title: '加入 ${guild.name}',
                            message: '加入需要 ${guilds.joinCost} 铜，确定继续吗？',
                            action: () => _controller.joinGuild(guild.id),
                          ),
                        ),
                    ],
                  ),
                if (joined) ...[
                  const SizedBox(height: 12),
                  _guildAuctionPanel(),
                ],
              ],
            ),
    );
  }

  Widget _guildAuctionPanel() {
    final auction = _controller.guildAuction;
    if (auction == null || !auction.hasAuction) {
      return const _EmptyHint('商会今日暂无拍卖');
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '商会拍卖 · ${auction.itemName}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (auction.itemQuality.trim().isNotEmpty)
                Text(
                  auction.itemQuality,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          if (auction.itemDescription.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                auction.itemDescription,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 6),
          _metricWrap(<Widget>[
            _MetricChip('起拍价', auction.startingPrice),
            _MetricChip('当前价', auction.highestBid),
            _MetricChip('最低出价', auction.minimumBid),
            _MetricChip('铜钱', auction.coin),
          ]),
          if (auction.phase.trim().isNotEmpty) _InfoLine('阶段', auction.phase),
          if (auction.bidCount > 0) _InfoLine('出价次数', '${auction.bidCount} 次'),
          if (auction.isLeading) const _InfoLine('状态', '当前领先'),
          if (auction.frozenCoin > 0)
            _InfoLine('冻结铜钱', '${auction.frozenCoin} 铜'),
          if (auction.unavailableReason.trim().isNotEmpty)
            _InfoLine('暂不可出价', auction.unavailableReason),
          if (auction.endTime != null)
            _InfoLine('结束时间', _formatDateTime(auction.endTime!)),
          _actionWrap(<Widget>[
            TextButton(
              onPressed: _controller.actionBusy || !auction.canBid
                  ? null
                  : _bidGuildAuction,
              child: Text(auction.canBid ? '出价' : '暂不可出价'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _collectionsCard() {
    final collections = _controller.collections;
    return _YeCard(
      key: const ValueKey<String>('ye-she-collections'),
      icon: AppGlyph.article,
      title: '我的收藏',
      subtitle: '${collections.length} 条',
      child: collections.isEmpty
          ? const _EmptyHint('还没有收藏社区想法')
          : Column(
              children: <Widget>[
                for (final item in collections.take(6))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      item.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: item.collectionName.trim().isEmpty
                        ? null
                        : Text(item.collectionName),
                  ),
              ],
            ),
    );
  }

  Widget _dailyLoreCard() {
    final lore = _controller.dailyLore;
    return _YeCard(
      key: const ValueKey<String>('ye-she-daily-lore'),
      icon: AppGlyph.menuBook,
      title: lore?.title.isNotEmpty == true ? lore!.title : '每日轶闻',
      subtitle: lore == null
          ? '今日暂无轶闻'
          : '${lore.category} · ${lore.quality} · ${lore.exp} 阅历',
      child: lore == null
          ? const _EmptyHint('今日轶闻暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(lore.content),
                const SizedBox(height: 8),
                if (lore.propName.trim().isNotEmpty)
                  _InfoLine('可能获得', lore.propName),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy || lore.isFinish
                        ? null
                        : () => _runAction(_controller.completeLore),
                    child: Text(lore.isFinish ? '今日已完成' : '完成轶闻'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _merchantCard() {
    final merchant = _controller.travelingMerchant;
    final trip = merchant?.activeTrip;
    final cityName = _cityName(merchant, trip?.cityCode);
    final transportName = _transportName(merchant, trip?.transportId);
    return _YeCard(
      key: const ValueKey<String>('ye-she-merchant'),
      icon: AppGlyph.autoStories,
      title: '行商',
      subtitle: trip == null
          ? merchant == null
                ? '行商状态尚未读取'
                : '${merchant.cities.length} 条商路 · ${merchant.transports.where((item) => item.owned).length} 艘船'
          : '$cityName · ${_tripStatus(trip.status)}',
      child: merchant == null
          ? const _EmptyHint('行商信息暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (trip == null)
                  _actionWrap(<Widget>[
                    TextButton(
                      onPressed: _controller.actionBusy
                          ? null
                          : _startTraveling,
                      child: const Text('开始行商'),
                    ),
                  ])
                else ...[
                  _InfoLine('船只', transportName),
                  _InfoLine('本金', '${trip.principal} 铜'),
                  _InfoLine('预计耗时', '${trip.totalDurationMinutes} 分钟'),
                  if (trip.eventTitle.trim().isNotEmpty)
                    _InfoLine('事件', trip.eventTitle),
                  if (trip.eventContent.trim().isNotEmpty)
                    Text(
                      trip.eventContent,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (trip.settlementAmount != 0)
                    _InfoLine('结算', '${trip.settlementAmount} 铜'),
                  _actionWrap(<Widget>[
                    TextButton(
                      onPressed: _controller.actionBusy
                          ? null
                          : () => _confirmedAction(
                              title: '结算行商',
                              message: '结算本次行程并领取收益？',
                              action: _controller.settleTraveling,
                            ),
                      child: const Text('结算行程'),
                    ),
                    TextButton(
                      onPressed: _controller.actionBusy
                          ? null
                          : _startTraveling,
                      child: const Text('另起一程'),
                    ),
                  ]),
                ],
                if (_controller.travelHistory.isNotEmpty)
                  _actionWrap(<Widget>[
                    TextButton(
                      onPressed: _showTravelHistory,
                      child: Text('历史 ${_controller.travelHistory.length} 条'),
                    ),
                  ]),
              ],
            ),
    );
  }

  Widget _retainerCard() {
    final retainers = _controller.retainers;
    return _YeCard(
      key: const ValueKey<String>('ye-she-retainers'),
      icon: AppGlyph.profile,
      title: '黄金台 · 门客',
      subtitle: retainers == null
          ? '门客名册尚未读取'
          : '${retainers.owned.length} 位门客 · 清贵 ${retainers.qinggui} · '
                '保底 ${retainers.pityCount}',
      child: retainers == null
          ? const _EmptyHint('门客信息暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (retainers.owned.isEmpty)
                  const _EmptyHint('尚未招募门客')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final item in retainers.owned.take(8))
                        Chip(
                          label: Text('${item.displayName} · ${item.quality}'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _confirmedAction(
                            title: '招募门客',
                            message: '招募会消耗黄金台资源，确定继续吗？',
                            action: _controller.recruitRetainer,
                          ),
                    child: const Text('招募门客'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _auctionCard() {
    final auction = _controller.auction;
    return _YeCard(
      key: const ValueKey<String>('ye-she-auction'),
      icon: AppGlyph.star,
      title: auction?.objectName.isNotEmpty == true
          ? auction!.objectName
          : '聚宝楼',
      subtitle: auction == null
          ? '今日暂无拍品'
          : '${auction.category} · ${auction.appraisal}',
      child: auction == null
          ? const _EmptyHint('聚宝楼暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _metricWrap(<Widget>[
                  _MetricChip('当前价', auction.highestBid),
                  _MetricChip('我的出价', auction.myBid),
                ]),
                if (auction.condition.trim().isNotEmpty)
                  _InfoLine('品相', auction.condition),
                if (auction.material.trim().isNotEmpty)
                  _InfoLine('材质', auction.material),
                if (auction.highestBidNickName.trim().isNotEmpty)
                  _InfoLine('领先者', auction.highestBidNickName),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy || !auction.canBid
                        ? null
                        : _bidAuction,
                    child: Text(auction.canBid ? '出价' : '暂不可出价'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _gamblingCard() {
    final gambling = _controller.gambling;
    return _YeCard(
      key: const ValueKey<String>('ye-she-gambling'),
      icon: AppGlyph.play,
      title: gambling?.name.isNotEmpty == true ? gambling!.name : '樗蒲',
      subtitle: gambling == null
          ? '今日暂未开局'
          : '${gambling.people} 人参与 · 剩余 ${gambling.remainingCount} 次',
      child: gambling == null
          ? const _EmptyHint('樗蒲暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (gambling.prize.trim().isNotEmpty)
                  _InfoLine('彩头', gambling.prize),
                _metricWrap(<Widget>[_MetricChip('我的点数', gambling.myScore)]),
                if (gambling.myDice.trim().isNotEmpty)
                  _InfoLine('骰面', gambling.myDice),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy || !gambling.canBet
                        ? null
                        : () => _runAction(_controller.betGambling),
                    child: Text(gambling.canBet ? '参与' : '已参与'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy || !gambling.canClaim
                        ? null
                        : () => _runAction(_controller.claimGambling),
                    child: Text(gambling.canClaim ? '领取奖励' : '暂无可领奖励'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _wishCard() {
    final wish = _controller.wishUp;
    return _YeCard(
      key: const ValueKey<String>('ye-she-wish'),
      icon: AppGlyph.star,
      title:
          '祈愿 · ${wish?.propName.isNotEmpty == true ? wish!.propName : '本周提升'}',
      subtitle: wish == null ? '祈愿信息尚未读取' : '本周 ${wish.weekStart}',
      child: wish == null
          ? const _EmptyHint('祈愿信息暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (wish.description.trim().isNotEmpty) Text(wish.description),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy ? null : () => _wish(1),
                    child: const Text('祈愿 1 次'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy ? null : () => _wish(10),
                    child: const Text('祈愿 10 次'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _runAction(_controller.wangyanWish),
                    child: const Text('望言祈愿'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _taoistCard() {
    final blessing = _controller.taoistBlessing;
    return _YeCard(
      key: const ValueKey<String>('ye-she-taoist'),
      icon: AppGlyph.lightMode,
      title: '道观',
      subtitle: blessing == null
          ? '祈福状态尚未读取'
          : '今日祈福 ${blessing.todayPrayCount} 次'
                '${blessing.freePrayAvailable ? ' · 免费祈福可用' : ''}',
      child: blessing == null
          ? const _EmptyHint('道观暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (blessing.blessingName.trim().isNotEmpty)
                  _InfoLine('当前福泽', blessing.blessingName),
                if (blessing.blessingDescription.trim().isNotEmpty)
                  Text(blessing.blessingDescription),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _pray('LUCK'),
                    child: const Text('运'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _pray('SAFETY'),
                    child: const Text('安'),
                  ),
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _pray('WEALTH'),
                    child: const Text('财'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _pawnCard() {
    final count = _controller.pawnCount;
    final materials = _controller.materials;
    return _YeCard(
      key: const ValueKey<String>('ye-she-pawn'),
      icon: AppGlyph.folder,
      title: '期物司',
      subtitle: count == null
          ? '典当次数尚未读取'
          : '今日 ${count.usedToday}/${count.maxPerDay} 次 · 剩余 ${count.remaining} 次',
      child: count == null
          ? const _EmptyHint('期物司暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (count.specialPropName.trim().isNotEmpty)
                  _InfoLine('今日高价收购', count.specialPropName),
                if (materials.isEmpty)
                  const _EmptyHint('暂无可典当材料')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final item in materials.take(8))
                        ActionChip(
                          label: Text('${item.name} ×${item.quantity}'),
                          onPressed: count.remaining <= 0
                              ? null
                              : () => _pawn(item),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }

  Widget _dailyShopCard() {
    final shop = _controller.dailyShop;
    return _YeCard(
      key: const ValueKey<String>('ye-she-daily-shop'),
      icon: AppGlyph.folder,
      title: '百杂铺',
      subtitle: shop == null
          ? '百杂铺尚未读取'
          : '铜钱 ${shop.coin} · 刷新 ${shop.refreshCount} 次',
      child: shop == null
          ? const _EmptyHint('百杂铺暂不可用')
          : shop.items.isEmpty
          ? const _EmptyHint('今日货架已空')
          : Column(
              children: <Widget>[
                for (final item in shop.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.name),
                    subtitle: Text('${item.quality} · ${item.type}'),
                    trailing: TextButton(
                      onPressed: item.purchased || _controller.actionBusy
                          ? null
                          : () => _buyDaily(item),
                      child: Text(item.purchased ? '已购买' : '${item.price} 铜'),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _voucherShopCard() {
    final shop = _controller.voucherShop;
    return _YeCard(
      key: const ValueKey<String>('ye-she-voucher-shop'),
      icon: AppGlyph.folderAdd,
      title: '玉机阁',
      subtitle: '玉券兑换',
      child: shop == null
          ? const _EmptyHint('玉机阁暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (shop.items.isEmpty)
                  const _EmptyHint('暂无可兑换物品')
                else
                  for (final item in shop.items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.name),
                      subtitle: Text('${item.quality} · ${item.type}'),
                      trailing: TextButton(
                        onPressed: _controller.actionBusy
                            ? null
                            : () => _buyVoucher(item),
                        child: Text('${item.price} 玉券'),
                      ),
                    ),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy ? null : _buyVoucherBox,
                    child: const Text('购买奇珍盒'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _marketCard() {
    final market = _controller.mutualMarket;
    return _YeCard(
      key: const ValueKey<String>('ye-she-market'),
      icon: AppGlyph.sort,
      title: '互市坊',
      subtitle: market == null
          ? '互市坊尚未读取'
          : '铜钱 ${market.coin} · ${market.listings.length} 条挂单',
      child: market == null
          ? const _EmptyHint('互市坊暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (market.props.isNotEmpty) ...[
                  Text('可上架', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final prop in market.props.take(8))
                        ActionChip(
                          label: Text('${prop.name} ×${prop.ownedQuantity}'),
                          onPressed: prop.ownedQuantity <= 0
                              ? null
                              : () => _createListing(prop),
                        ),
                    ],
                  ),
                ],
                if (market.listings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('在售', style: Theme.of(context).textTheme.labelMedium),
                  for (final listing in market.listings.take(6))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${listing.propName} · ${listing.unitPrice} 铜',
                      ),
                      subtitle: Text(
                        '${listing.sellerName} · 剩余 ${listing.remainingQuantity}',
                      ),
                      trailing: TextButton(
                        onPressed: _controller.actionBusy
                            ? null
                            : () => _buyListing(listing),
                        child: const Text('购买'),
                      ),
                    ),
                ],
                if (market.myListings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('我的挂单', style: Theme.of(context).textTheme.labelMedium),
                  for (final listing in market.myListings.take(6))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${listing.propName} · ${listing.unitPrice} 铜',
                      ),
                      subtitle: Text('剩余 ${listing.remainingQuantity}'),
                      trailing: TextButton(
                        onPressed: _controller.actionBusy
                            ? null
                            : () => _confirmedAction(
                                title: '取消挂单',
                                message: '取消 ${listing.propName} 的挂单？',
                                action: () =>
                                    _controller.cancelMarketListing(listing.id),
                              ),
                        child: const Text('取消'),
                      ),
                    ),
                ],
                if (market.props.isEmpty && market.listings.isEmpty)
                  const _EmptyHint('互市坊暂时冷清'),
              ],
            ),
    );
  }

  Widget _medalTreasureCard() {
    final treasure = _controller.medalTreasure;
    return _YeCard(
      key: const ValueKey<String>('ye-she-medal-treasure'),
      icon: AppGlyph.star,
      title: treasure?.medalName.isNotEmpty == true
          ? treasure!.medalName
          : '徽章征集',
      subtitle: treasure == null
          ? '徽章征集尚未读取'
          : '${treasure.currentCount}/${treasure.totalCount} · ${treasure.userCount} 人参与',
      child: treasure == null
          ? const _EmptyHint('徽章征集暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (treasure.previousWinnerNickName.trim().isNotEmpty)
                  _InfoLine('上期得主', treasure.previousWinnerNickName),
                _actionWrap(<Widget>[
                  TextButton(
                    onPressed: _controller.actionBusy
                        ? null
                        : _joinMedalTreasure,
                    child: const Text('投入征集'),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _thoughtsCard() {
    final thoughts = _controller.thoughts;
    return _YeCard(
      key: const ValueKey<String>('ye-she-thoughts'),
      icon: AppGlyph.highlighter,
      title: '社区想法',
      subtitle: '${thoughts.length} 条公开笔记',
      child: thoughts.isEmpty
          ? const _EmptyHint('暂无公开读书想法')
          : Column(
              children: <Widget>[
                for (final thought in thoughts.take(6))
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
    );
  }

  Widget _rumorsCard() {
    final rumors = _controller.rumors;
    return _YeCard(
      key: const ValueKey<String>('ye-she-rumors'),
      icon: AppGlyph.article,
      title: '唱经楼',
      subtitle: '${rumors.length} 条传闻',
      child: rumors.isEmpty
          ? const _EmptyHint('暂无社区传闻')
          : Column(
              children: <Widget>[
                for (final rumor in rumors.take(8))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const AppIcon(AppGlyph.article),
                    title: Text(
                      rumor.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      rumor.nickName.trim().isEmpty
                          ? rumor.type
                          : '${rumor.nickName} · ${rumor.type}',
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _runAction(Future<YeSheActionResult> Function() action) async {
    final result = await action();
    _showResult(result);
  }

  void _showResult(YeSheActionResult result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _confirmedAction({
    required String title,
    required String message,
    required Future<YeSheActionResult> Function() action,
  }) async {
    final confirmed = await _confirm(title: title, message: message);
    if (!confirmed) return;
    await _runAction(action);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    String initialValue = '',
    bool allowEmpty = false,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    final text = result?.trim();
    if (text == null || (!allowEmpty && text.isEmpty)) return null;
    return text;
  }

  Future<int?> _promptInt({
    required String title,
    required String label,
    required int initialValue,
    int minimum = 1,
  }) async {
    final text = await _promptText(
      title: title,
      label: label,
      initialValue: initialValue.toString(),
    );
    final value = int.tryParse(text ?? '');
    if (value == null || value < minimum) return null;
    return value;
  }

  Future<void> _stampSeal(int sealId) async {
    final reviewId = await _promptInt(
      title: '盖章',
      label: '书评 ID',
      initialValue: 0,
    );
    if (reviewId == null) return;
    final result = await _controller.stampSeal(
      sealId: sealId,
      reviewId: reviewId,
    );
    _showResult(result);
  }

  Future<void> _stampNotelet(int noteletId) async {
    final reviewId = await _promptInt(
      title: '使用花笺',
      label: '书评 ID',
      initialValue: 0,
    );
    if (reviewId == null) return;
    final result = await _controller.stampNotelet(
      noteletId: noteletId,
      reviewId: reviewId,
    );
    _showResult(result);
  }

  Future<void> _createSociety() async {
    final result = await showDialog<({String name, bool isPublic})>(
      context: context,
      builder: (context) {
        var isPublic = true;
        final nameController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('创建文会'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '文会名称'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('公开文会'),
                  value: isPublic,
                  onChanged: (value) => setState(() => isPublic = value),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(context).pop((name: name, isPublic: isPublic));
                },
                child: const Text('创建'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    final action = await _controller.createSociety(
      name: result.name,
      isPublic: result.isPublic,
    );
    _showResult(action);
  }

  Future<void> _joinSocietyByCode() async {
    final code = await _promptText(title: '邀请码加入', label: '文会邀请码');
    if (code == null) return;
    final result = await _controller.joinSociety(code);
    _showResult(result);
  }

  Future<void> _browsePublicSocieties() async {
    final societies = await _controller.searchLiterarySocieties();
    if (!mounted) return;
    if (societies.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未找到可加入的公开文会')));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text('公开文会', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final society in societies)
            ListTile(
              title: Text(society.name),
              subtitle: Text(
                '${society.level} 级 · ${society.memberCount}/${society.memberLimit} 人',
              ),
              trailing: TextButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(
                    _runAction(() => _controller.joinPublicSociety(society.id)),
                  );
                },
                child: const Text('加入'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _updateSocietyCover() async {
    final cover = await _promptText(
      title: '修改文会封面',
      label: '封面图片地址',
      initialValue: _controller.mySociety?.coverUrl ?? '',
    );
    if (cover == null) return;
    final result = await _controller.updateSocietyCover(cover);
    _showResult(result);
  }

  Future<void> _kickSocietyMember() async {
    final members =
        _controller.mySociety?.members ?? const <YeSheSocietyMember>[];
    if (members.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('文会成员列表为空')));
      return;
    }
    final selected = await showModalBottomSheet<YeSheSocietyMember>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: <Widget>[
          for (final member in members)
            ListTile(
              title: Text(member.nickName),
              subtitle: Text(
                '${member.weekScore} 声望'
                '${member.isPresident ? ' · 会长' : ''}',
              ),
              onTap: () => Navigator.of(context).pop(member),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final confirmed = await _confirm(
      title: '移出成员',
      message: '将 ${selected.nickName} 移出文会？',
    );
    if (!confirmed) return;
    final result = await _controller.kickSocietyMember(selected.userId);
    _showResult(result);
  }

  Future<void> _showGuildMembers() async {
    await _controller.loadGuildMembers();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, child) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            Text('商会成员', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_controller.guildMembers.isEmpty)
              const _EmptyHint('暂无成员信息')
            else
              for (final member in _controller.guildMembers)
                ListTile(
                  title: Text(member.nickName),
                  subtitle: Text(
                    '${member.levelName} · 贡献 ${member.contribution}',
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGuildHistory() async {
    await _controller.loadGuildHistory();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, child) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            Text('商会行商动态', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_controller.guildHistory.isEmpty)
              const _EmptyHint('暂无行商动态')
            else
              for (final item in _controller.guildHistory)
                ListTile(title: Text(item.nickName), subtitle: Text(item.trip)),
          ],
        ),
      ),
    );
  }

  Future<void> _bidAuction() async {
    final auction = _controller.auction;
    if (auction == null) return;
    final amount = await _promptInt(
      title: '聚宝楼出价',
      label: '出价铜钱',
      initialValue: auction.highestBid + 1,
      minimum: auction.highestBid + 1,
    );
    if (amount == null) return;
    final result = await _controller.bidAuction(amount);
    _showResult(result);
  }

  Future<void> _bidGuildAuction() async {
    final auction = _controller.guildAuction;
    if (auction == null || !auction.hasAuction) return;
    final minimum = auction.minimumBid > 0
        ? auction.minimumBid
        : auction.highestBid + 1;
    final amount = await _promptInt(
      title: '商会拍卖出价',
      label: '出价铜钱',
      initialValue: minimum,
      minimum: minimum,
    );
    if (amount == null) return;
    final result = await _controller.bidGuildAuction(amount);
    _showResult(result);
  }

  Future<void> _startTraveling() async {
    final data = _controller.travelingMerchant;
    if (data == null) return;
    if (data.cities.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂无可选商路')));
      return;
    }
    final transports = data.transports.where((item) => item.owned).toList();
    if (transports.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂无可用的行商船只')));
      return;
    }
    final result =
        await showDialog<({String cityCode, int transportId, int principal})>(
          context: context,
          builder: (context) {
            var cityCode = data.cities.first.code;
            var transportId = transports.first.id;
            final principalController = TextEditingController(text: '100');
            return StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: const Text('开始行商'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DropdownButtonFormField<String>(
                        initialValue: cityCode,
                        decoration: const InputDecoration(labelText: '商路'),
                        items: <DropdownMenuItem<String>>[
                          for (final city in data.cities)
                            DropdownMenuItem<String>(
                              value: city.code,
                              child: Text('${city.name} · ${city.routeType}'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => cityCode = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: transportId,
                        decoration: const InputDecoration(labelText: '船只'),
                        items: <DropdownMenuItem<int>>[
                          for (final transport in transports)
                            DropdownMenuItem<int>(
                              value: transport.id,
                              child: Text(
                                '${transport.name} · 速度 +${transport.speedPercent}%',
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => transportId = value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: principalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '本金（铜）'),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () {
                      final principal = int.tryParse(principalController.text);
                      if (principal == null || principal <= 0) return;
                      Navigator.of(context).pop((
                        cityCode: cityCode,
                        transportId: transportId,
                        principal: principal,
                      ));
                    },
                    child: const Text('出发'),
                  ),
                ],
              ),
            );
          },
        );
    if (result == null) return;
    final action = await _controller.startTraveling(
      cityCode: result.cityCode,
      transportId: result.transportId,
      principal: result.principal,
    );
    _showResult(action);
  }

  Future<void> _showTravelHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text('行商历史', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final trip in _controller.travelHistory)
            ListTile(
              title: Text(
                '${_cityName(_controller.travelingMerchant, trip.cityCode)} · '
                '${_tripStatus(trip.status)}',
              ),
              subtitle: Text(
                '本金 ${trip.principal} 铜 · 结算 ${trip.settlementAmount} 铜',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _wish(int count) async {
    final result = await _controller.makeWish(count);
    _showResult(result);
  }

  Future<void> _pray(String type) async {
    final result = await _controller.pray(type);
    _showResult(result);
  }

  Future<void> _pawn(YeSheMaterial material) async {
    final confirmed = await _confirm(
      title: '典当 ${material.name}',
      message: '确定典当一件 ${material.name}？',
    );
    if (!confirmed) return;
    final result = await _controller.pawnMaterial(material.userPropId);
    _showResult(result);
  }

  Future<void> _buyDaily(YeSheShopItem item) async {
    final quantity = await _promptInt(
      title: '购买 ${item.name}',
      label: '数量',
      initialValue: 1,
    );
    if (quantity == null) return;
    final result = await _controller.buyDailyItem(
      propId: item.propId,
      quantity: quantity,
    );
    _showResult(result);
  }

  Future<void> _buyVoucher(YeSheShopItem item) async {
    final quantity = await _promptInt(
      title: '兑换 ${item.name}',
      label: '数量',
      initialValue: 1,
    );
    if (quantity == null) return;
    final result = await _controller.buyVoucherItem(
      propId: item.propId,
      quantity: quantity,
    );
    _showResult(result);
  }

  Future<void> _buyVoucherBox() async {
    final quantity = await _promptInt(
      title: '购买奇珍盒',
      label: '数量',
      initialValue: 1,
    );
    if (quantity == null) return;
    final result = await _controller.buyVoucherBox(quantity);
    _showResult(result);
  }

  Future<void> _createListing(YeSheMarketProp prop) async {
    final unitPrice = await _promptInt(
      title: '上架 ${prop.name}',
      label: '单价（铜）',
      initialValue: prop.referencePrice > 0
          ? prop.referencePrice
          : prop.minPrice,
      minimum: prop.minPrice > 0 ? prop.minPrice : 1,
    );
    if (unitPrice == null) return;
    final quantity = await _promptInt(
      title: '上架 ${prop.name}',
      label: '数量',
      initialValue: 1,
    );
    if (quantity == null) return;
    final result = await _controller.createMarketListing(
      propId: prop.propId,
      unitPrice: unitPrice,
      quantity: quantity,
    );
    _showResult(result);
  }

  Future<void> _buyListing(YeSheMarketListing listing) async {
    final quantity = await _promptInt(
      title: '购买 ${listing.propName}',
      label: '数量',
      initialValue: 1,
    );
    if (quantity == null) return;
    final result = await _controller.buyMarketListing(
      listingId: listing.id,
      quantity: quantity,
    );
    _showResult(result);
  }

  Future<void> _joinMedalTreasure() async {
    final count = await _promptInt(
      title: '投入徽章征集',
      label: '投入数量',
      initialValue: 1,
    );
    if (count == null) return;
    final result = await _controller.joinMedalTreasure(count);
    _showResult(result);
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

  Future<void> _showCollectors(YeSheThought thought) async {
    final collectors = await _controller.loadMarkCollectors(thought.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text('收藏者', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (collectors.isEmpty)
            const _EmptyHint('暂无人收藏')
          else
            for (final collector in collectors)
              ListTile(
                title: Text(
                  yeSheText(
                    collector['nickName'] ??
                        collector['userName'] ??
                        collector['name'],
                  ),
                ),
                subtitle: Text(
                  yeSheText(collector['title'] ?? collector['levelName']),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _openSignedItems({
    required String title,
    String? note,
    required List<YeSheNamedItem> items,
    String? actionLabel,
    Future<void> Function(YeSheNamedItem item)? onAction,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (note != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(note, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          if (items.isEmpty)
            _EmptyHint('尚未获得$title')
          else
            for (final item in items)
              ListTile(
                title: Text(item.name),
                trailing: actionLabel == null || onAction == null
                    ? null
                    : TextButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(onAction(item));
                        },
                        child: Text(actionLabel),
                      ),
              ),
        ],
      ),
    );
  }

  String _cityName(YeSheTravelingMerchant? data, String? code) {
    if (data == null || code == null || code.isEmpty) return '行商途中';
    for (final city in data.cities) {
      if (city.code == code) return city.name;
    }
    return code;
  }

  String _transportName(YeSheTravelingMerchant? data, int? id) {
    if (data == null || id == null || id <= 0) return '未知船只';
    for (final transport in data.transports) {
      if (transport.id == id) return transport.name;
    }
    return '船只 $id';
  }

  String _tripStatus(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('travel')) return '路途中';
    if (normalized.contains('complete') || normalized.contains('finish')) {
      return '已抵达';
    }
    if (normalized.contains('settle')) return '已结算';
    return status.trim().isEmpty ? '进行中' : status;
  }
}

class _YeCard extends StatelessWidget {
  const _YeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final AppGlyph icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppIcon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(subtitle, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label $value'),
    );
  }
}

class _InventoryButton extends StatelessWidget {
  const _InventoryButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text('$label $value'), onPressed: onPressed);
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(thought.text, maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            '${thought.bookName} · ${thought.userName} · ${thought.chapter}',
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: <Widget>[
              TextButton(onPressed: onCollectors, child: const Text('收藏者')),
              TextButton(
                onPressed: busy ? null : onCollect,
                child: Text(collected ? '取消收藏' : '收藏'),
              ),
              TextButton(
                onPressed: busy ? null : onAppreciate,
                child: Text(appreciated ? '取消赞赏' : '赞赏'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignedOutView extends StatelessWidget {
  const _SignedOutView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const AppIcon(AppGlyph.autoStories, size: 44),
            const SizedBox(height: 16),
            Text('登录阅微后进入野社', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('野社复用阅微账号，不会在本地另存登录状态。'),
          ],
        ),
      ),
    );
  }
}

Widget _actionWrap(List<Widget> children) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: children,
    ),
  );
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _rankValueText(YeSheRankKind kind, int value) {
  return switch (kind) {
    YeSheRankKind.readDuration => _formatRankDuration(value),
    YeSheRankKind.wealth || YeSheRankKind.auction => '$value 铜',
    YeSheRankKind.collectionValue => '$value',
    YeSheRankKind.communityTitle => '$value 级',
  };
}

String _formatRankDuration(int seconds) {
  if (seconds <= 0) return '0 分';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) {
    return minutes > 0 ? '$hours 小时 $minutes 分' : '$hours 小时';
  }
  if (minutes > 0) return '$minutes 分';
  return '$seconds 秒';
}

String _signed(int value) => value > 0 ? '+$value' : '$value';
