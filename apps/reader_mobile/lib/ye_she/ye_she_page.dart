import 'dart:async';

import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'ye_she_assets.dart';
import 'ye_she_controller.dart';
import '../rea_micro/rea_micro_controller.dart';
import 'ye_she_models.dart';
import 'ye_she_visuals.dart';

/// 阅微野社：文房、游艺、见闻。
class YeShePage extends StatefulWidget {
  /// 创建页面。
  const YeShePage({
    super.key,
    this.controller,
    this.account,
    this.tokenProvider,
    this.currentUserName = '',
    this.currentUserId = 0,
    this.currentUserAvatar = '',
    this.currentUserTitle = '',
  }) : assert(controller != null || tokenProvider != null);

  /// 可注入的控制器，供页面测试使用。
  final YeSheController? controller;
  final ReaMicroController? account;

  /// 当前阅微令牌提供者。
  final String? Function()? tokenProvider;

  /// 当前阅微账号昵称。
  final String currentUserName;

  /// 当前阅微账号编号，用于判断文会管理权限。
  final int currentUserId;

  /// 当前阅微账号头像。
  final String currentUserAvatar;

  /// 当前阅微账号头衔。
  final String currentUserTitle;

  @override
  State<YeShePage> createState() => _YeShePageState();
}

class _YeShePageState extends State<YeShePage>
    with SingleTickerProviderStateMixin {
  late final YeSheController _controller;
  late final bool _ownsController;
  late final TabController _tabController;
  YeSheRankKind _rankKind = YeSheRankKind.readDuration;
  String _lastPawnMessage = '';

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
    widget.account?.pageRefresh.addListener(_refreshCurrentTab);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_loadSelectedTab);
    unawaited(_controller.loadAll());
  }

  @override
  void dispose() {
    widget.account?.pageRefresh.removeListener(_refreshCurrentTab);
    _tabController.removeListener(_loadSelectedTab);
    _tabController.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _loadSelectedTab() {
    if (_tabController.indexIsChanging) return;
    switch (_tabController.index) {
      case 1:
        if (!_controller.loadedPlay) unawaited(_controller.refreshPlay());
        break;
      case 2:
        if (!_controller.loadedDiscover) {
          unawaited(_controller.refreshDiscover());
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Column(
        children: <Widget>[
          SafeArea(bottom: false, child: _header(theme)),
          _tabBar(theme),
          Expanded(
            child: ListenableBuilder(
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
                        color: YeSheTokens.vermilion(context),
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                      Expanded(child: _tabBody()),
                    ],
                  );
                }
                return _tabBody();
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
          Positioned(
            right: 22,
            bottom: 10,
            child: Transform.rotate(
              angle: -0.06,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: YeSheTokens.vermilion(context)
                        .withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '野社',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: YeSheTokens.vermilion(context)
                        .withValues(alpha: 0.75),
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Builder(
                  builder: (context) {
                    final canPop = Navigator.of(context).canPop();
                    return IconButton(
                      tooltip: canPop ? '返回' : '野社',
                      onPressed: canPop
                          ? () => Navigator.of(context).maybePop()
                          : null,
                      icon: AppIcon(
                        canPop ? AppGlyph.arrowBack : AppGlyph.review,
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
                          '野社',
                          key: const ValueKey<String>('ye-she-header-title'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AnimatedBuilder(
                          animation: _tabController,
                          builder: (context, child) => Text(
                            _tabDescription(_tabController.index),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, child) => IconButton(
                    key: const ValueKey<String>('ye-she-refresh'),
                    tooltip: '刷新野社',
                    onPressed: _currentTabLoading
                        ? null
                        : () => unawaited(_refreshCurrentTab()),
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

  Widget _tabBar(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TabBar(
        key: const ValueKey<String>('ye-she-tab-bar'),
        controller: _tabController,
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: YeSheTokens.vermilion(context),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: scheme.surface,
          borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
          border: Border.all(color: YeSheTokens.line(context)),
        ),
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll<Color>(
          YeSheTokens.vermilion(context).withValues(alpha: 0.08),
        ),
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
        unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
          letterSpacing: 1,
        ),
        tabs: <Widget>[
          _tab(
            index: 0,
            key: const ValueKey<String>('ye-she-tab-study'),
            glyph: AppGlyph.menuBook,
            label: '文房',
          ),
          _tab(
            index: 1,
            key: const ValueKey<String>('ye-she-tab-play'),
            glyph: AppGlyph.play,
            label: '游艺',
          ),
          _tab(
            index: 2,
            key: const ValueKey<String>('ye-she-tab-discover'),
            glyph: AppGlyph.discover,
            label: '见闻',
          ),
        ],
      ),
    );
  }

  Widget _tab({
    required int index,
    required Key key,
    required AppGlyph glyph,
    required String label,
  }) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, child) {
        final selected = _tabController.index == index;
        final scheme = Theme.of(context).colorScheme;
        final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
        return Tab(
          key: key,
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AppIcon(
                glyph,
                size: 16,
                color: selected
                    ? YeSheTokens.vermilion(context)
                    : color.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color)),
            ],
          ),
        );
      },
    );
  }

  String _tabDescription(int index) {
    return switch (index) {
      0 => '文会、清玩与榜上声名',
      1 => '聚宝、樗蒲与道观',
      _ => '祈愿、期物与百杂市井',
    };
  }

  Widget _tabBody() {
    return TabBarView(
      controller: _tabController,
      children: <Widget>[
        _refreshable(_refreshStudyTab, _buildStudy),
        _refreshable(_controller.refreshPlay, _buildPlay),
        _refreshable(_controller.refreshDiscover, _buildDiscover),
      ],
    );
  }

  Widget _refreshable(
    Future<void> Function() refresh,
    Widget Function() builder,
  ) {
    return RefreshIndicator(onRefresh: refresh, child: builder());
  }

  bool get _currentTabLoading {
    return switch (_tabController.index) {
      0 => _controller.loadingStudy || _controller.loadingRanks,
      1 => _controller.loadingPlay,
      _ => _controller.loadingDiscover,
    };
  }

  Future<void> _refreshCurrentTab() {
    return switch (_tabController.index) {
      0 => _refreshStudyTab(),
      1 => _controller.refreshPlay(),
      _ => _controller.refreshDiscover(),
    };
  }

  Future<void> _refreshStudyTab() async {
    await _controller.refreshStudy();
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
        _societyCard(),
        _inventoryCard(),
        _titleCard(),
        _rankCard(),
        _merchantCard(),
        _retainerCard(),
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
        _guildCard(),
        _auctionCard(),
        _gamblingCard(),
        _taoistCard(),
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
        _pawnCard(),
        _dailyLoreCard(),
        _dailyShopCard(),
        _voucherShopCard(),
        _marketCard(),
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
              onPressed: () => unawaited(_refreshCurrentTab()),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingOrEmpty(bool loading, String emptyText) {
    return loading ? const _PendingHint('正在读取…') : _EmptyHint(emptyText);
  }

  Widget _metricWrap(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(spacing: 8, runSpacing: 6, children: children),
    );
  }

  Widget _accountCard() {
    final status = _controller.account;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final userName = widget.currentUserName.trim().isEmpty
        ? '阅微用户'
        : widget.currentUserName.trim();
    final userTitle = widget.currentUserTitle.trim();
    final progress = status == null || status.expMax <= 0
        ? 0.0
        : (status.exp / status.expMax).clamp(0.0, 1.0);
    return Container(
      key: const ValueKey<String>('ye-she-account'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[scheme.surface, YeSheTokens.wash(context)],
        ),
        borderRadius: ReaderUiStyle.cardRadiusOf(Theme.of(context)),
        border: Border.all(color: YeSheTokens.line(context)),
        boxShadow: YeSheTokens.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              YeSheAvatar(
                url: widget.currentUserAvatar,
                size: 54,
                ringColor: YeSheTokens.jade(context),
                semanticsLabel: '我的野社头像',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (status != null)
                          YeSheTag(
                            'Lv.${status.level}',
                            color: YeSheTokens.vermilion(context),
                          ),
                      ],
                    ),
                    if (userTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '名帖 · $userTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: YeSheTokens.gold(context),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      status == null
                          ? '账户状态尚未读取'
                          : '阅历 ${status.exp}/${status.expMax} · '
                                '${status.expMax - status.exp} 点升级',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Transform.rotate(
                angle: 0.04,
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: YeSheTokens.vermilion(context)
                        .withValues(alpha: 0.08),
                    border: Border.all(
                      color: YeSheTokens.vermilion(context)
                          .withValues(alpha: 0.45),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '野',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: YeSheTokens.vermilion(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: YeSheTokens.vermilion(context),
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 12),
          if (status == null)
            _loadingOrEmpty(!_controller.loadedStudy, '账户状态暂不可用')
          else ...<Widget>[
            _metricWrap(<Widget>[
              _MetricChip('铜钱', status.coin, glyph: AppGlyph.star),
              _MetricChip('彩筹', status.gem, glyph: AppGlyph.bookmark),
              _MetricChip('玉券', status.voucher, glyph: AppGlyph.folder),
            ]),
            const SizedBox(height: 4),
            Text(
              '行商 ${_signed(status.travelingMerchantNet)} · '
              '聚宝楼 ${_signed(status.auctionNet)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _titleCard() {
    final title = _controller.title;
    final theme = Theme.of(context);
    final hasTitle = title?.title.trim().isNotEmpty == true;
    final hasTitleCost = _TitleCostPanel.allOwned(_controller.materials);
    return _YeCard(
      key: const ValueKey<String>('ye-she-title'),
      icon: AppGlyph.star,
      title: '名帖',
      subtitle: title == null
          ? _controller.loadingStudy
                ? '名帖读取中'
                : '名帖尚未读取'
          : title.displayName,
      child: title == null
          ? _loadingOrEmpty(_controller.loadingStudy, '名帖信息暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        YeSheTokens.gold(context).withValues(alpha: 0.16),
                        YeSheTokens.wash(context),
                      ],
                    ),
                    borderRadius: ReaderUiStyle.controlRadiusOf(
                      Theme.of(context),
                    ),
                    border: Border.all(
                      color: YeSheTokens.gold(context).withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: YeSheTokens.gold(context),
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          '${title.level}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: YeSheTokens.gold(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            if (title.sourceName.trim().isNotEmpty)
                              Text(
                                '承自 ${title.sourceName}',
                                style: theme.textTheme.labelSmall,
                              ),
                          ],
                        ),
                      ),
                      YeSheTag(
                        '${title.level} 级',
                        color: YeSheTokens.gold(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _TitleCostPanel(
                  materials: _controller.materials,
                  loading: _controller.loadingStudy,
                  loaded: _controller.materialsLoaded,
                ),
                const SizedBox(height: 8),
                _InfoLine('当前等级', '${title.level} 级'),
                _InfoLine('升级保底', '${title.upgradePityCount} 次'),
                _InfoLine('传承保底', '${title.heritagePityCount} 次'),
                _actionWrap(<Widget>[
                  _primaryActionButton(
                    '升级',
                    onPressed: _controller.actionBusy || !hasTitleCost
                        ? null
                        : () => _confirmedAction(
                            title: '升级名帖',
                            message: '升级消耗清酒、檀香、欹器各 1 件，确定继续吗？',
                            action: _controller.upgradeTitle,
                          ),
                  ),
                  _secondaryActionButton(
                    '传承',
                    onPressed: _controller.actionBusy || !hasTitleCost
                        ? null
                        : () => _confirmedAction(
                            title: '传承名帖',
                            message: '传承消耗清酒、檀香、欹器各 1 件，确定继续吗？',
                            action: _controller.heritageTitle,
                          ),
                  ),
                  _dangerActionButton(
                    context,
                    '弃置',
                    onPressed: _controller.actionBusy || !hasTitle
                        ? null
                        : () => _confirmedAction(
                            title: '弃置名帖',
                            message: '弃置当前名帖可能失去已获得的雅号，确定继续吗？',
                            action: _controller.abandonTitle,
                          ),
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
            _loadingOrEmpty(_controller.loadingRanks, '排行榜暂不可用')
          else if (board.entries.isEmpty)
            const _EmptyHint('榜单暂时没有记录')
          else
            for (final entry in board.entries.take(20))
              _RankRow(
                entry: entry,
                valueText: _rankValueText(_rankKind, entry.value),
              ),
          if (board != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: YeSheTokens.wash(context),
                  borderRadius: ReaderUiStyle.controlRadiusOf(
                    Theme.of(context),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    AppIcon(
                      AppGlyph.stats,
                      size: 16,
                      color: YeSheTokens.vermilion(context),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
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
    final loading = _controller.loadingStudy;
    String countText(int? count, String unit) => count == null
        ? loading
              ? '读取中'
              : '0 $unit'
        : '$count $unit';
    final total =
        (seals?.items.length ?? 0) +
        (notelets?.items.length ?? 0) +
        (medals?.items.length ?? 0) +
        (cards?.items.length ?? 0);
    return _YeCard(
      key: const ValueKey<String>('ye-she-inventory'),
      icon: AppGlyph.bookmark,
      title: '清玩 · 鉴赏',
      subtitle: '藏印、花笺、徽章与名片',
      trailing: YeSheTag(
        loading &&
                (seals == null ||
                    notelets == null ||
                    medals == null ||
                    cards == null)
            ? '读取中'
            : '$total 件',
        color: YeSheTokens.gold(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _metricWrap(<Widget>[
            _InventoryButton(
              label: '藏印',
              value: countText(seals?.items.length, '张'),
              onPressed: () => _openSignedItems(
                title: '藏印',
                kind: _SignedItemKind.seal,
                note: seals == null ? null : '印泥 ${seals.inkPasteQuantity} 丸',
                items: seals?.items ?? const <YeSheNamedItem>[],
                actionLabel: '盖章',
                onAction: (item) => _stampSeal(item.id),
              ),
            ),
            _InventoryButton(
              label: '花笺',
              value: countText(notelets?.items.length, '张'),
              onPressed: () => _openSignedItems(
                title: '花笺',
                kind: _SignedItemKind.notelet,
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
              value: countText(medals?.items.length, '枚'),
              onPressed: () => _openSignedItems(
                title: '徽章',
                kind: _SignedItemKind.medal,
                items: medals?.items ?? const <YeSheNamedItem>[],
              ),
            ),
            _InventoryButton(
              label: '名片',
              value: countText(cards?.items.length, '张'),
              onPressed: () => _openSignedItems(
                title: '名片',
                kind: _SignedItemKind.callingCard,
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
    final theme = Theme.of(context);
    final isPresident =
        society != null &&
        widget.currentUserId > 0 &&
        (society.presidentUserId == widget.currentUserId ||
            society.members.any(
              (member) =>
                  member.userId == widget.currentUserId && member.isPresident,
            ));
    return _YeCard(
      key: const ValueKey<String>('ye-she-society'),
      icon: AppGlyph.review,
      title: society?.name.isNotEmpty == true ? society!.name : '文会',
      subtitle: society == null
          ? '尚未加入文会'
          : '${society.level} 级 · ${society.memberCount}/${society.memberLimit} 人 · '
                '本周 ${society.weekScore} 声望',
      showHeader: society == null,
      banner: society == null ? null : _SocietyBanner(society: society),
      child: society == null
          ? !_controller.loadedStudy
                ? const _PendingHint('文会信息读取中…')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const _EmptyHint('创建或加入一个文会，与同好共读。'),
                      _actionWrap(<Widget>[
                        _primaryActionButton(
                          '创建文会',
                          onPressed: _controller.actionBusy
                              ? null
                              : _createSociety,
                        ),
                        _secondaryActionButton(
                          '邀请码加入',
                          onPressed: _controller.actionBusy
                              ? null
                              : _joinSocietyByCode,
                        ),
                        _secondaryActionButton(
                          '公开文会',
                          onPressed: _controller.actionBusy
                              ? null
                              : _browsePublicSocieties,
                        ),
                      ]),
                    ],
                  )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (isPresident || society.inviteCode.trim().isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      if (isPresident)
                        YeSheTag('会长', color: YeSheTokens.vermilion(context)),
                      if (society.inviteCode.trim().isNotEmpty)
                        YeSheTag(
                          '邀请码 ${society.inviteCode}',
                          color: YeSheTokens.jade(context),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                ],
                if (scores != null) ...<Widget>[
                  Text(
                    '本周文会声望 ${scores.totalScore}/${scores.maxScore}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: scores.ratio,
                      minHeight: 5,
                      color: YeSheTokens.jade(context),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ] else
                  Text(
                    _controller.loadingStudy ? '本周声望读取中…' : '本周声望尚未读取',
                    style: theme.textTheme.bodySmall,
                  ),
                if (society.members.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _MemberAvatarRow(members: society.members.take(8)),
                ],
                if (society.members.isNotEmpty ||
                    society.memberCount > society.members.length) ...[
                  const SizedBox(height: 8),
                  _secondaryActionButton(
                    '成员 ${society.memberCount}',
                    onPressed: _showSocietyMembers,
                  ),
                ],
                const SizedBox(height: 8),
                _InfoLine('奖励状态', society.weeklyRewardStatusText),
                if (scores != null) ...[
                  if (scores.members.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    YeSheSectionLabel(
                      '本周贡献排行',
                      trailing: scores.weekStart.trim().isEmpty
                          ? null
                          : Text(
                              scores.weekStart,
                              style: theme.textTheme.labelSmall,
                            ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final member in scores.members.take(8))
                          _MemberChip(member: member, score: member.weekScore),
                      ],
                    ),
                  ],
                ],
                _actionWrap(<Widget>[
                  _primaryActionButton(
                    society.weeklyRewardActionLabel,
                    key: const ValueKey<String>('ye-she-society-reward'),
                    onPressed:
                        _controller.actionBusy || !society.canClaimWeeklyReward
                        ? null
                        : () => _confirmedAction(
                            title: '领取文会奖励',
                            message: '领取本周文会声望奖励？',
                            action: _controller.claimSocietyReward,
                          ),
                  ),
                  if (isPresident) ...<Widget>[
                    _secondaryActionButton(
                      '修改封面',
                      onPressed: _controller.actionBusy
                          ? null
                          : _updateSocietyCover,
                    ),
                    _secondaryActionButton(
                      '移出成员',
                      onPressed: _controller.actionBusy
                          ? null
                          : _kickSocietyMember,
                    ),
                    _dangerActionButton(
                      context,
                      '解散文会',
                      onPressed: _controller.actionBusy
                          ? null
                          : () => _confirmedAction(
                              title: '解散文会',
                              message: '解散文会不可恢复，确定继续吗？',
                              action: _controller.dissolveSociety,
                            ),
                    ),
                  ] else if (widget.currentUserId > 0)
                    _dangerActionButton(
                      context,
                      '退出文会',
                      onPressed: _controller.actionBusy
                          ? null
                          : () => _confirmedAction(
                              title: '退出文会',
                              message: '退出后将失去当前文会身份，确定继续吗？',
                              action: _controller.quitSociety,
                            ),
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
          ? _controller.loadingStudy || _controller.loadingPlay
                ? '商会信息读取中'
                : '商会信息尚未读取'
          : '加入费用 ${guilds.joinCost} 铜',
      banner: YeSheBanner(
        asset: YeSheTokens.guildBanner(current?.code ?? ''),
        height: 92,
        label: current?.name ?? '商会',
        caption: joined ? '${current?.name ?? '商会'} · 本周行商' : '入会结伴，共分商路',
      ),
      trailing: joined && current != null
          ? YeSheTag(
              '${current.memberCount} 人',
              color: YeSheTokens.jade(context),
            )
          : null,
      child: guilds == null
          ? _loadingOrEmpty(
              _controller.loadingStudy || _controller.loadingPlay,
              '商会信息暂不可用',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (joined)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: YeSheStatChip(
                              label: '商会资金',
                              value: '${current?.balance ?? 0}',
                              icon: AppGlyph.star,
                              color: YeSheTokens.gold(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          YeSheStatChip(
                            label: '贡献',
                            value: '${membership!.contribution}',
                            icon: AppGlyph.review,
                            color: YeSheTokens.jade(context),
                          ),
                        ],
                      ),
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
                      ]),
                    ],
                  )
                else if (guilds.guilds.isEmpty)
                  const _EmptyHint('暂无可加入的商会')
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (guilds.joinCost > 0)
                        _CostStatusPanel(
                          rows: <_CostStatusRow>[
                            _CostStatusRow(
                              '加入商会 · 铜钱',
                              guilds.joinCost,
                              _controller.account?.coin ?? 0,
                            ),
                          ],
                        ),
                      if (guilds.joinCost > 0) const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final guild in guilds.guilds)
                            ActionChip(
                              label: Text(
                                '${guild.name} · ${guild.memberCount} 人',
                              ),
                              onPressed: () => _confirmedAction(
                                title: '加入 ${guild.name}',
                                message: '加入需要 ${guilds.joinCost} 铜，确定继续吗？',
                                action: () => _controller.joinGuild(guild.id),
                              ),
                            ),
                        ],
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
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset(
                  '${YeSheTokens.assetRoot}shrine_trinkets.webp',
                  width: 42,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '商会拍卖 · ${auction.itemName}',
                      style: Theme.of(context).textTheme.titleSmall,
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
                  ],
                ),
              ),
              if (auction.itemQuality.trim().isNotEmpty)
                Text(
                  auction.itemQuality,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
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

  Widget _dailyLoreCard() {
    final lore = _controller.dailyLore;
    return _YeCard(
      key: const ValueKey<String>('ye-she-daily-lore'),
      icon: AppGlyph.menuBook,
      title: lore?.title.isNotEmpty == true ? lore!.title : '每日轶闻',
      subtitle: lore == null
          ? _controller.loadingDiscover
                ? '每日轶闻读取中'
                : '今日暂无轶闻'
          : '${lore.category} · ${lore.quality} · ${lore.exp} 阅历',
      trailing: lore == null
          ? null
          : YeSheTag(
              lore.quality.isEmpty ? '轶闻' : lore.quality,
              color: YeSheTokens.gold(context),
            ),
      child: lore == null
          ? _loadingOrEmpty(_controller.loadingDiscover, '今日轶闻暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
                  decoration: BoxDecoration(
                    color: YeSheTokens.wash(context),
                    borderRadius: ReaderUiStyle.controlRadiusOf(
                      Theme.of(context),
                    ),
                    border: Border.all(color: YeSheTokens.line(context)),
                  ),
                  child: Text(
                    lore.content,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(height: 1.6),
                  ),
                ),
                const SizedBox(height: 8),
                if (lore.propName.trim().isNotEmpty)
                  _InfoLine('可能获得', lore.propName),
                _metricWrap(<Widget>[
                  if (lore.exp > 0)
                    _MetricChip('阅历', lore.exp, glyph: AppGlyph.star),
                  if (lore.gem > 0)
                    _MetricChip('彩筹', lore.gem, glyph: AppGlyph.bookmark),
                ]),
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
    final now = DateTime.now();
    final tripStage = trip == null ? '待出发' : _tripStatus(trip, now);
    final progress = trip?.progressAt(now) ?? 0;
    return _YeCard(
      key: const ValueKey<String>('ye-she-merchant'),
      icon: AppGlyph.autoStories,
      title: '行商',
      subtitle: trip == null
          ? merchant == null
                ? _controller.loadingStudy || _controller.loadingPlay
                      ? '行商状态读取中'
                      : '行商状态尚未读取'
                : '${merchant.cities.length} 条商路 · ${merchant.transports.where((item) => item.owned).length} 艘船'
          : '$cityName · $tripStage',
      banner: YeSheBanner(
        asset: trip == null
            ? 'shrine_xingshang.webp'
            : YeSheTokens.cityAsset(_cityIndex(merchant, trip.cityCode)),
        height: 104,
        label: trip == null ? '行商' : cityName,
        caption: trip == null
            ? '择一城，装一船，待风起'
            : '$transportName · $tripStage · ${(progress * 100).round()}%',
      ),
      trailing: trip == null
          ? null
          : YeSheTag(
              tripStage,
              color: trip.isSettled
                  ? YeSheTokens.gold(context)
                  : YeSheTokens.jade(context),
            ),
      child: merchant == null
          ? _loadingOrEmpty(
              _controller.loadingStudy || _controller.loadingPlay,
              '行商信息暂不可用',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (trip == null)
                  _actionWrap(<Widget>[
                    TextButton(
                      onPressed: _controller.actionBusy
                          ? null
                          : _startTraveling,
                      child: Text(
                        _controller.travelHistory.isEmpty ? '开始行商' : '另起一程',
                      ),
                    ),
                  ])
                else ...[
                  _metricWrap(<Widget>[
                    _MetricChip('本金', trip.principal, glyph: AppGlyph.star),
                    _MetricChip(
                      '耗时',
                      trip.totalDurationMinutes,
                      glyph: AppGlyph.refresh,
                    ),
                    if (trip.settlementAmount != 0)
                      _MetricChip(
                        '结算',
                        trip.settlementAmount,
                        glyph: AppGlyph.checkCircle,
                      ),
                  ]),
                  _InfoLine('船只', transportName),
                  if (trip.eventTitle.trim().isNotEmpty)
                    _InfoLine('事件', trip.eventTitle),
                  if (trip.eventContent.trim().isNotEmpty)
                    Text(
                      trip.eventContent,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Text(
                        '行程进度 ${(progress * 100).round()}%',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        tripStage,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      key: const ValueKey<String>('ye-she-merchant-progress'),
                      value: progress,
                      minHeight: 5,
                      color: trip.isSettled
                          ? YeSheTokens.gold(context)
                          : YeSheTokens.jade(context),
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
                  ),
                  _actionWrap(<Widget>[
                    if (trip.canSettle)
                      TextButton(
                        onPressed: _controller.actionBusy
                            ? null
                            : () => _confirmedAction(
                                title: '结算行商',
                                message: '结算本次行程并领取收益？',
                                action: _controller.settleTraveling,
                              ),
                        child: const Text('结算行程'),
                      )
                    else
                      const TextButton(onPressed: null, child: Text('行程进行中')),
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
    final hasRecruitCost = retainers != null && retainers.qinggui >= 1;
    return _YeCard(
      key: const ValueKey<String>('ye-she-retainers'),
      icon: AppGlyph.profile,
      title: '黄金台 · 门客',
      subtitle: retainers == null
          ? _controller.loadingStudy || _controller.loadingPlay
                ? '门客名册读取中'
                : '门客名册尚未读取'
          : '${retainers.owned.length} 位门客 · 清贵 ${retainers.qinggui} · '
                '保底 ${retainers.pityCount}',
      trailing: retainers == null
          ? null
          : YeSheTag(
              '${retainers.owned.length} 位',
              color: YeSheTokens.gold(context),
            ),
      child: retainers == null
          ? _loadingOrEmpty(
              _controller.loadingStudy || _controller.loadingPlay,
              '门客信息暂不可用',
            )
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
                        _RetainerTile(retainer: item),
                    ],
                  ),
                const SizedBox(height: 8),
                _CostStatusPanel(
                  rows: <_CostStatusRow>[
                    _CostStatusRow('招募门客 · 清贵', 1, retainers.qinggui),
                  ],
                ),
                _actionWrap(<Widget>[
                  _primaryActionButton(
                    '招募门客',
                    onPressed: _controller.actionBusy || !hasRecruitCost
                        ? null
                        : () => _confirmedAction(
                            title: '招募门客',
                            message: '招募消耗清贵 1，确定继续吗？',
                            action: _controller.recruitRetainer,
                          ),
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
      banner: YeSheBanner(
        asset: 'shrine_auction.webp',
        height: 112,
        label: '聚宝楼',
        caption: auction == null ? '今日暂无拍品' : '一槌定音，价高者得',
        trailing: auction == null
            ? null
            : YeSheTag(
                auction.canBid ? '正在唱价' : '暂不可出价',
                color: auction.canBid ? YeSheTokens.vermilion(context) : null,
              ),
      ),
      child: auction == null
          ? _loadingOrEmpty(_controller.loadingPlay, '聚宝楼暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    YeSheAssetImage(
                      asset: YeSheTokens.auctionAsset(
                        auction.objectName,
                        seed: auction.objectId.isEmpty
                            ? '${auction.id}-${auction.objectName}'
                            : auction.objectId,
                      ),
                      width: 72,
                      height: 88,
                      borderRadius: 9,
                      semanticsLabel: '${auction.objectName}的拍品图',
                      fallbackGlyph: AppGlyph.star,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _metricWrap(<Widget>[
                            _MetricChip(
                              '当前价',
                              auction.highestBid,
                              glyph: AppGlyph.star,
                            ),
                            _MetricChip(
                              '我的出价',
                              auction.myBid,
                              glyph: AppGlyph.bookmark,
                            ),
                          ]),
                          if (auction.condition.trim().isNotEmpty)
                            _InfoLine('品相', auction.condition),
                          if (auction.material.trim().isNotEmpty)
                            _InfoLine('材质', auction.material),
                        ],
                      ),
                    ),
                  ],
                ),
                if (auction.highestBidNickName.trim().isNotEmpty ||
                    auction.highestBidAvatar.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: <Widget>[
                        YeSheAvatar(
                          url: auction.highestBidAvatar,
                          size: 30,
                          semanticsLabel: '当前领先者头像',
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '领先 ${auction.highestBidNickName.isEmpty ? '阅微用户' : auction.highestBidNickName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (auction.endTime != null)
                          Text(
                            _formatDateTime(auction.endTime!),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
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
          ? _controller.loadingPlay
                ? '樗蒲读取中'
                : '今日暂未开局'
          : '${gambling.people} 人参与 · 剩余 ${gambling.remainingCount} 次',
      banner: YeSheBanner(
        asset: 'shrine_chupu.webp',
        height: 112,
        label: '樗蒲',
        caption: gambling == null
            ? '今日暂未开局'
            : '${gambling.people} 人同场 · 彩头 ${gambling.prize}',
        trailing: gambling == null
            ? null
            : YeSheTag(
                gambling.canBet ? '可投注' : '已投注',
                color: gambling.canBet ? YeSheTokens.vermilion(context) : null,
              ),
      ),
      child: gambling == null
          ? _loadingOrEmpty(_controller.loadingPlay, '樗蒲暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (gambling.prize.trim().isNotEmpty)
                  _InfoLine('彩头', gambling.prize),
                _metricWrap(<Widget>[
                  _MetricChip('我的点数', gambling.myScore, glyph: AppGlyph.star),
                  _MetricChip('参与', gambling.people, glyph: AppGlyph.profile),
                ]),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      for (var index = 0; index < 3; index++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: YeSheAssetImage(
                            asset:
                                '${YeSheTokens.assetRoot}gambling_${(gambling.id + index) % 5}.webp',
                            width: 42,
                            height: 58,
                            borderRadius: 6,
                            semanticsLabel: '樗蒲牌面',
                            fallbackGlyph: AppGlyph.play,
                          ),
                        ),
                    ],
                  ),
                ),
                if (gambling.myDice.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: <Widget>[
                        for (final die in gambling.myDice.split(
                          RegExp(r'[,，\s]+'),
                        ))
                          if (die.trim().isNotEmpty)
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: YeSheTokens.wash(context),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: YeSheTokens.line(context),
                                ),
                              ),
                              child: Text(
                                die,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: YeSheTokens.vermilion(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                      ],
                    ),
                  ),
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
    final gem = _controller.account?.gem ?? 0;
    final canWishOnce = _controller.account != null && gem >= 1;
    final canWishTen = _controller.account != null && gem >= 10;
    return _YeCard(
      key: const ValueKey<String>('ye-she-wish'),
      icon: AppGlyph.star,
      title:
          '祈愿 · ${wish?.propName.isNotEmpty == true ? wish!.propName : '本周提升'}',
      subtitle: wish == null
          ? _controller.loadingDiscover
                ? '祈愿信息读取中'
                : '祈愿信息尚未读取'
          : '本周 ${wish.weekStart}',
      banner: YeSheBanner(
        asset: 'shrine_sunrise.webp',
        height: 100,
        label: '祈愿',
        caption: wish == null
            ? '本周祈愿尚未开始'
            : '${wish.propName.isEmpty ? '本周提升' : wish.propName} · 概率提升',
      ),
      trailing: wish == null
          ? null
          : YeSheTag(
              wish.weekStart.isEmpty ? '本周' : wish.weekStart,
              color: YeSheTokens.jade(context),
            ),
      child: wish == null
          ? _loadingOrEmpty(_controller.loadingDiscover, '祈愿信息暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (wish.description.trim().isNotEmpty) Text(wish.description),
                const SizedBox(height: 8),
                _CostStatusPanel(
                  rows: <_CostStatusRow>[
                    _CostStatusRow('祈愿 1 次 · 彩筹', 1, gem),
                    _CostStatusRow('祈愿 10 次 · 彩筹', 10, gem),
                  ],
                ),
                _actionWrap(<Widget>[
                  _primaryActionButton(
                    '祈愿 1 次',
                    onPressed: _controller.actionBusy || !canWishOnce
                        ? null
                        : () => _wish(1),
                  ),
                  _secondaryActionButton(
                    '祈愿 10 次',
                    onPressed: _controller.actionBusy || !canWishTen
                        ? null
                        : () => _wish(10),
                  ),
                  _secondaryActionButton(
                    '望言祈愿',
                    onPressed: _controller.actionBusy
                        ? null
                        : () => _runAction(_controller.wangyanWish),
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
          ? _controller.loadingPlay
                ? '祈福状态读取中'
                : '祈福状态尚未读取'
          : '今日祈福 ${blessing.todayPrayCount} 次'
                '${blessing.freePrayAvailable ? ' · 免费祈福可用' : ''}',
      child: blessing == null
          ? _loadingOrEmpty(_controller.loadingPlay, '道观暂不可用')
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
          ? _controller.loadingDiscover
                ? '典当次数读取中'
                : '典当次数尚未读取'
          : '今日 ${count.usedToday}/${count.maxPerDay} 次 · 剩余 ${count.remaining} 次',
      trailing: count == null
          ? null
          : YeSheTag(
              '剩 ${count.remaining} 次',
              color: count.remaining > 0
                  ? YeSheTokens.jade(context)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      child: count == null
          ? _loadingOrEmpty(_controller.loadingDiscover, '期物司暂不可用')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (count.specialPropName.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: YeSheTokens.gold(context).withValues(alpha: 0.1),
                      borderRadius: ReaderUiStyle.controlRadiusOf(
                        Theme.of(context),
                      ),
                      border: Border.all(
                        color: YeSheTokens.gold(context)
                            .withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        YeSheItemIcon(
                          propId: yeSheInt(count.specialPropId),
                          size: 20,
                          fallbackGlyph: AppGlyph.star,
                          fallbackColor: YeSheTokens.gold(context),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '今日高价收购',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: YeSheTokens.gold(context)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            count.specialPropName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_lastPawnMessage.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: YeSheTokens.jade(context).withValues(alpha: 0.09),
                      borderRadius: ReaderUiStyle.controlRadiusOf(
                        Theme.of(context),
                      ),
                      border: Border.all(
                        color: YeSheTokens.jade(context)
                            .withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        AppIcon(
                          AppGlyph.checkCircle,
                          size: 15,
                          color: YeSheTokens.jade(context),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _lastPawnMessage,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: YeSheTokens.jade(context),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (materials.isEmpty)
                  const _EmptyHint('暂无可典当材料')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final item in materials.take(8))
                        _MaterialTile(
                          key: ValueKey<String>(
                            'ye-she-material-${item.userPropId}',
                          ),
                          material: item,
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
          ? _controller.loadingDiscover
                ? '百杂铺读取中'
                : '百杂铺尚未读取'
          : '铜钱 ${shop.coin} · 刷新 ${shop.refreshCount} 次',
      child: shop == null
          ? _loadingOrEmpty(_controller.loadingDiscover, '百杂铺暂不可用')
          : shop.items.isEmpty
          ? const _EmptyHint('今日货架已空')
          : Column(
              children: <Widget>[
                for (final item in shop.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: _ItemGlyph(
                      propId: item.propId,
                      glyph: _itemGlyph(item.name, item.type),
                      color: YeSheTokens.jade(context),
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      <String>[
                        if (item.quality.trim().isNotEmpty) item.quality,
                        if (item.type.trim().isNotEmpty) item.type,
                      ].join(' · '),
                    ),
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
          ? _loadingOrEmpty(_controller.loadingDiscover, '玉机阁暂不可用')
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
                      leading: _ItemGlyph(
                        propId: item.propId,
                        glyph: _itemGlyph(item.name, item.type),
                        color: YeSheTokens.gold(context),
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        <String>[
                          if (item.quality.trim().isNotEmpty) item.quality,
                          if (item.type.trim().isNotEmpty) item.type,
                        ].join(' · '),
                      ),
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
          ? _controller.loadingDiscover
                ? '互市坊读取中'
                : '互市坊尚未读取'
          : '铜钱 ${market.coin} · ${market.listings.length} 条挂单',
      trailing: market == null
          ? null
          : YeSheTag(
              '${market.myListings.length} 条我的挂单',
              color: YeSheTokens.jade(context),
            ),
      child: market == null
          ? _loadingOrEmpty(_controller.loadingDiscover, '互市坊暂不可用')
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
                          avatar: YeSheItemIcon(
                            propId: prop.propId,
                            size: 20,
                            fallbackGlyph: AppGlyph.folder,
                            fallbackColor: YeSheTokens.jade(context),
                          ),
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
                      leading: _ItemGlyph(
                        propId: listing.propId,
                        glyph: _itemGlyph(
                          listing.propName,
                          listing.propQuality,
                        ),
                        color: YeSheTokens.jade(context),
                      ),
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
                      leading: _ItemGlyph(
                        propId: listing.propId,
                        glyph: _itemGlyph(
                          listing.propName,
                          listing.propQuality,
                        ),
                        color: YeSheTokens.gold(context),
                      ),
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

  Widget _rumorsCard() {
    final rumors = _controller.rumors;
    return _YeCard(
      key: const ValueKey<String>('ye-she-rumors'),
      icon: AppGlyph.article,
      title: '唱经楼',
      subtitle: _controller.loadingDiscover && rumors.isEmpty
          ? '传闻读取中'
          : '${rumors.length} 条传闻',
      child: rumors.isEmpty
          ? _loadingOrEmpty(_controller.loadingDiscover, '暂无社区传闻')
          : Column(
              children: <Widget>[
                for (final rumor in rumors.take(8))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: YeSheAvatar(
                      url: rumor.avatar,
                      size: 34,
                      semanticsLabel: '${rumor.nickName}的头像',
                    ),
                    title: Text(
                      rumor.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      <String>[
                        if (rumor.nickName.trim().isNotEmpty) rumor.nickName,
                        if (rumor.type.trim().isNotEmpty) rumor.type,
                        if (rumor.createTime != null)
                          _formatDateTime(rumor.createTime!),
                      ].join(' · '),
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
    final result = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
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
    final result = await showReaderDialog<String>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
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
    final result = await showReaderDialog<({String name, bool isPublic})>(
      context: context,
      builder: (context) {
        var isPublic = true;
        final nameController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) => ReaderFrostedAlertDialog(
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
                ReaderSwitchListTile(
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
    await showReaderBottomSheet<void>(
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

  Future<void> _showSocietyMembers() async {
    final members =
        _controller.mySociety?.members ?? const <YeSheSocietyMember>[];
    await showReaderBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text('文会成员', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (members.isEmpty)
            const _EmptyHint('暂无成员信息')
          else
            for (final member in members)
              ListTile(
                leading: YeSheAvatar(
                  url: member.avatar,
                  size: 38,
                  semanticsLabel: '${member.nickName}的头像',
                ),
                title: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        member.nickName.isEmpty ? '阅微用户' : member.nickName,
                      ),
                    ),
                    if (member.isPresident)
                      YeSheTag('会长', color: YeSheTokens.vermilion(context)),
                  ],
                ),
                subtitle: Text(
                  <String>[
                    if (member.title.trim().isNotEmpty) member.title,
                    '${member.weekScore} 声望',
                    if (member.recentBookName.trim().isNotEmpty)
                      '读《${member.recentBookName}》',
                  ].join(' · '),
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
    final selected = await showReaderBottomSheet<YeSheSocietyMember>(
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
    await showReaderBottomSheet<void>(
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
                  leading: YeSheAvatar(
                    url: member.avatar,
                    size: 38,
                    semanticsLabel: '${member.nickName}的头像',
                  ),
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
    await showReaderBottomSheet<void>(
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
                ListTile(
                  leading: YeSheAvatar(
                    url: item.avatar,
                    size: 34,
                    semanticsLabel: '${item.nickName}的头像',
                  ),
                  title: Text(item.nickName),
                  subtitle: Text(item.trip),
                ),
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
    final activeTrip = data.activeTrip;
    if (activeTrip != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activeTrip.canSettle ? '请先结算当前行商' : '行商进行中，抵达并结算后才能再次出发',
          ),
        ),
      );
      return;
    }
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
        await showReaderDialog<
          ({String cityCode, int transportId, int principal})
        >(
          context: context,
          builder: (context) {
            var cityCode = data.cities.first.code;
            var transportId = transports.first.id;
            final principalController = TextEditingController(text: '100');
            return StatefulBuilder(
              builder: (context, setState) => ReaderFrostedAlertDialog(
                title: const Text('开始行商'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ReaderDropdownButtonFormField<String>(
                        initialValue: cityCode,
                        decoration: const InputDecoration(labelText: '商路'),
                        items: <DropdownMenuItem<String>>[
                          for (final (index, city) in data.cities.indexed)
                            DropdownMenuItem<String>(
                              value: city.code,
                              child: Row(
                                children: <Widget>[
                                  YeSheAssetImage(
                                    asset: YeSheTokens.cityAsset(index),
                                    width: 24,
                                    height: 24,
                                    borderRadius: 5,
                                    semanticsLabel: '${city.name}的商路图',
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${city.name} · ${city.routeType}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => cityCode = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      ReaderDropdownButtonFormField<int>(
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
    await showReaderBottomSheet<void>(
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
                '${_tripStatus(trip)}',
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
    if (mounted && result.success) {
      setState(() => _lastPawnMessage = result.message);
    }
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

  Future<void> _openSignedItems({
    required String title,
    required _SignedItemKind kind,
    String? note,
    required List<YeSheNamedItem> items,
    String? actionLabel,
    Future<void> Function(YeSheNamedItem item)? onAction,
  }) async {
    await showReaderBottomSheet<void>(
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
                leading: YeSheAssetImage(
                  asset: switch (kind) {
                    _SignedItemKind.seal => YeSheTokens.sealAsset(
                      item.propId,
                      seed: '${item.identity}-${item.name}',
                    ),
                    _SignedItemKind.notelet => YeSheTokens.noteletFallback,
                    _SignedItemKind.medal => YeSheTokens.medalAsset(
                      item.propId,
                    ),
                    _SignedItemKind.callingCard => YeSheTokens.callingCardAsset(
                      item.name,
                    ),
                  },
                  width: 42,
                  height: 42,
                  borderRadius: 7,
                  semanticsLabel: '${item.name}的图片',
                  fallbackGlyph: switch (kind) {
                    _SignedItemKind.seal => AppGlyph.bookmark,
                    _SignedItemKind.notelet => AppGlyph.note,
                    _SignedItemKind.medal => AppGlyph.star,
                    _SignedItemKind.callingCard => AppGlyph.profile,
                  },
                ),
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

  int _cityIndex(YeSheTravelingMerchant? data, String? code) {
    if (data == null || code == null || code.isEmpty) return 0;
    final index = data.cities.indexWhere((city) => city.code == code);
    return index < 0 ? 0 : index;
  }

  String _transportName(YeSheTravelingMerchant? data, int? id) {
    if (data == null || id == null || id <= 0) return '未知船只';
    for (final transport in data.transports) {
      if (transport.id == id) return transport.name;
    }
    return '船只 $id';
  }

  String _tripStatus(YeSheTravelTrip trip, [DateTime? now]) =>
      trip.stageAt(now ?? DateTime.now());
}

/// 文会封面横幅：与行商、聚宝楼卡片一致，将名称与基本信息叠在图片上。
class _SocietyBanner extends StatelessWidget {
  const _SocietyBanner({required this.society});

  final YeSheLiterarySociety society;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        return SizedBox(
          height: 148,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              YeSheCover(
                key: const ValueKey<String>('ye-she-society-cover'),
                url: society.coverUrl,
                width: width,
                height: 148,
                borderRadius: 0,
                semanticsLabel: '${society.name}的封面',
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: dark ? 0.18 : 0.02),
                      Colors.black.withValues(alpha: dark ? 0.72 : 0.6),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 15,
                right: 14,
                bottom: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            society.name.isNotEmpty ? society.name : '文会',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              shadows: const <Shadow>[
                                Shadow(color: Color(0x66000000), blurRadius: 8),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${society.level} 级 · '
                            '${society.memberCount}/${society.memberLimit} 人 · '
                            '本周 ${society.weekScore} 声望',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              shadows: const <Shadow>[
                                Shadow(color: Color(0x66000000), blurRadius: 6),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.36),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Text(
                        society.isPublic ? '公开' : '私密',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
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
  }
}

class _YeCard extends StatelessWidget {
  const _YeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.banner,
    this.trailing,
    this.showHeader = true,
  });

  final AppGlyph icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? banner;
  final Widget? trailing;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: ReaderUiStyle.cardRadiusOf(Theme.of(context)),
          border: Border.all(color: YeSheTokens.line(context)),
          boxShadow: YeSheTokens.cardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ?banner,
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (showHeader) ...<Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: YeSheTokens.vermilion(context)
                                .withValues(alpha: 0.08),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (trailing != null) ...<Widget>[
                          const SizedBox(width: 6),
                          trailing!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 11),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                  ],
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value, {this.glyph});

  final String label;
  final int value;
  final AppGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    return YeSheStatChip(
      label: label,
      value: '$value',
      icon: glyph,
      color: glyph == null ? null : YeSheTokens.gold(context),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry, required this.valueText});

  final YeSheRankEntry entry;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleText = <String>[
      if (entry.title.trim().isNotEmpty) entry.title,
      if (entry.titleLevel > 0) '名帖 ${entry.titleLevel} 级',
      '${entry.level} 级',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: entry.rank <= 3
            ? YeSheTokens.gold(context).withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
      ),
      child: Row(
        children: <Widget>[
          YeSheRankBadge(rank: entry.rank),
          const SizedBox(width: 8),
          YeSheAvatar(
            url: entry.avatar,
            size: 34,
            ringColor: entry.rank <= 3
                ? YeSheTokens.gold(context).withValues(alpha: 0.55)
                : YeSheTokens.line(context),
            semanticsLabel: '${entry.nickName}的头像',
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.nickName.isEmpty ? '阅微用户' : entry.nickName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: entry.rank <= 3
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Text(
              valueText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium?.copyWith(
                color: entry.rank <= 3
                    ? YeSheTokens.vermilion(context)
                    : scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberAvatarRow extends StatelessWidget {
  const _MemberAvatarRow({required this.members});

  final Iterable<YeSheSocietyMember> members;

  @override
  Widget build(BuildContext context) {
    final list = members.toList(growable: false);
    if (list.isEmpty) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 38,
        width: 36 + (list.length - 1) * 22,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            for (var index = 0; index < list.length; index++)
              Positioned(
                left: index * 22,
                top: 3,
                child: YeSheAvatar(
                  url: list[index].avatar,
                  size: 30,
                  ringColor: Theme.of(context).colorScheme.surface,
                  semanticsLabel: '${list[index].nickName}的头像',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.member, required this.score});

  final YeSheSocietyMember member;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 9, 3),
      decoration: BoxDecoration(
        color: YeSheTokens.wash(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: YeSheTokens.line(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YeSheAvatar(
            url: member.avatar,
            size: 24,
            semanticsLabel: '${member.nickName}的头像',
          ),
          const SizedBox(width: 5),
          Text(
            member.nickName.isEmpty ? '同好' : member.nickName,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 4),
          Text(
            '$score',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: YeSheTokens.vermilion(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RetainerTile extends StatelessWidget {
  const _RetainerTile({required this.retainer});

  final YeSheRetainer retainer;

  @override
  Widget build(BuildContext context) {
    final name = retainer.displayName;
    final seed = retainer.code.trim().isEmpty
        ? '${retainer.id}-$name'
        : retainer.code;
    return Container(
      width: 84,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
      decoration: BoxDecoration(
        color: YeSheTokens.wash(context),
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
        border: Border.all(color: YeSheTokens.line(context)),
      ),
      child: Column(
        children: <Widget>[
          YeSheAssetImage(
            asset: YeSheTokens.retainerAsset(seed),
            width: 64,
            height: 64,
            borderRadius: 8,
            semanticsLabel: '$name的门客像',
            fallbackGlyph: AppGlyph.profile,
          ),
          const SizedBox(height: 5),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          if (retainer.quality.trim().isNotEmpty)
            Text(
              retainer.quality,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    super.key,
    required this.material,
    required this.onPressed,
  });

  final YeSheMaterial material;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = material.name.trim();
    final glyph = switch (name) {
      _ when name.contains('纸') || name.contains('笺') => AppGlyph.note,
      _ when name.contains('墨') || name.contains('砚') || name.contains('石') =>
        AppGlyph.edit,
      _ when name.contains('笔') || name.contains('毫') => AppGlyph.editNote,
      _ when name.contains('花') || name.contains('桃') => AppGlyph.star,
      _ when name.contains('竹') || name.contains('木') => AppGlyph.article,
      _ => AppGlyph.folder,
    };
    return Material(
      color: YeSheTokens.wash(context),
      borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
      child: InkWell(
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              YeSheItemIcon(
                propId: material.propId,
                size: 20,
                fallbackGlyph: glyph,
                fallbackColor: YeSheTokens.jade(context),
              ),
              const SizedBox(width: 5),
              Text(
                material.name,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: onPressed == null
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '×${material.quantity}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: YeSheTokens.vermilion(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemGlyph extends StatelessWidget {
  const _ItemGlyph({required this.glyph, required this.color, this.propId = 0});

  final AppGlyph glyph;
  final Color color;
  final int propId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
      ),
      child: YeSheItemIcon(
        propId: propId,
        size: 23,
        fallbackGlyph: glyph,
        fallbackColor: color,
      ),
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: YeSheTokens.wash(context),
      borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
      child: InkWell(
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(value, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(width: 2),
              AppIcon(
                AppGlyph.chevronRight,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
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
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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
  Widget build(BuildContext context) => YeSheEmpty(text);
}

class _PendingHint extends StatelessWidget {
  const _PendingHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      YeSheEmpty(text, icon: AppGlyph.refresh);
}

class _CostStatusRow {
  const _CostStatusRow(this.name, this.required, this.owned);

  final String name;
  final int required;
  final int owned;
}

class _CostStatusPanel extends StatelessWidget {
  const _CostStatusPanel({required this.rows});

  final List<_CostStatusRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: BoxDecoration(
        color: YeSheTokens.wash(context),
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
        border: Border.all(color: YeSheTokens.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '本次消耗',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          for (final row in rows) _row(context, row),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, _CostStatusRow row) {
    final theme = Theme.of(context);
    final enough = row.owned >= row.required;
    final color = enough ? YeSheTokens.jade(context) : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          AppIcon(
            enough ? AppGlyph.checkCircle : AppGlyph.warning,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(row.name)),
          Text(
            '需要 ${row.required} · 拥有 ${row.owned}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: enough ? theme.colorScheme.onSurfaceVariant : color,
              fontWeight: enough ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleCostSpec {
  const _TitleCostSpec({required this.propId, required this.name});

  final int propId;
  final String name;
}

class _TitleCostPanel extends StatelessWidget {
  const _TitleCostPanel({
    required this.materials,
    required this.loading,
    required this.loaded,
  });

  static const List<_TitleCostSpec> costs = <_TitleCostSpec>[
    _TitleCostSpec(propId: 11, name: '清酒'),
    _TitleCostSpec(propId: 13, name: '檀香'),
    _TitleCostSpec(propId: 18, name: '欹器'),
  ];

  final List<YeSheMaterial> materials;
  final bool loading;
  final bool loaded;

  static bool allOwned(List<YeSheMaterial> materials) {
    if (materials.isEmpty) return false;
    return costs.every((cost) => _ownedQuantity(materials, cost) >= 1);
  }

  static int _ownedQuantity(
    List<YeSheMaterial> materials,
    _TitleCostSpec cost,
  ) {
    var quantity = 0;
    for (final item in materials) {
      if (item.propId == cost.propId || item.name.trim().contains(cost.name)) {
        quantity += item.quantity;
      }
    }
    return quantity;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: BoxDecoration(
        color: YeSheTokens.wash(context),
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
        border: Border.all(color: YeSheTokens.line(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '本次消耗',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          if (loading && materials.isEmpty)
            Text(
              '材料读取中…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else if (!loaded && materials.isEmpty)
            Text(
              '材料信息暂不可用',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else if (materials.isEmpty)
            Text(
              '暂无可消耗材料',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final cost in costs)
              _row(context, cost, _ownedQuantity(materials, cost)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, _TitleCostSpec cost, int owned) {
    final theme = Theme.of(context);
    final enough = owned >= 1;
    final color = enough ? YeSheTokens.jade(context) : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          AppIcon(
            enough ? AppGlyph.checkCircle : AppGlyph.warning,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 5),
          YeSheItemIcon(
            propId: cost.propId,
            size: 18,
            fallbackGlyph: AppGlyph.folder,
            fallbackColor: color,
          ),
          const SizedBox(width: 5),
          Expanded(child: Text(cost.name)),
          Text(
            '需要 1 · 拥有 $owned',
            style: theme.textTheme.labelSmall?.copyWith(
              color: enough ? theme.colorScheme.onSurfaceVariant : color,
              fontWeight: enough ? FontWeight.w400 : FontWeight.w600,
            ),
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
    final theme = Theme.of(context);
    return Center(
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
                '登录阅微后进入野社',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '野社复用阅微账号，不会在本地另存登录状态。',
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

enum _SignedItemKind { seal, notelet, medal, callingCard }

Widget _primaryActionButton(
  String label, {
  required VoidCallback? onPressed,
  Key? key,
}) {
  return FilledButton.tonal(
    key: key,
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
    ),
    child: Text(label),
  );
}

Widget _secondaryActionButton(
  String label, {
  required VoidCallback? onPressed,
  Key? key,
}) {
  return OutlinedButton(
    key: key,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    child: Text(label),
  );
}

Widget _dangerActionButton(
  BuildContext context,
  String label, {
  required VoidCallback? onPressed,
  Key? key,
}) {
  final error = Theme.of(context).colorScheme.error;
  return OutlinedButton(
    key: key,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: error,
      side: BorderSide(color: error.withValues(alpha: 0.5)),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    child: Text(label),
  );
}

Widget _actionWrap(List<Widget> children) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
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

AppGlyph _itemGlyph(String name, [String type = '']) {
  final text = '$name $type';
  return switch (text) {
    _ when text.contains('纸') || text.contains('笺') => AppGlyph.note,
    _ when text.contains('墨') || text.contains('砚') || text.contains('石') =>
      AppGlyph.edit,
    _ when text.contains('笔') || text.contains('毫') => AppGlyph.editNote,
    _ when text.contains('印') || text.contains('章') => AppGlyph.bookmark,
    _ when text.contains('帖') || text.contains('卡') => AppGlyph.profile,
    _ when text.contains('花') || text.contains('桃') => AppGlyph.star,
    _ when text.contains('书') => AppGlyph.menuBook,
    _ => AppGlyph.folder,
  };
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
