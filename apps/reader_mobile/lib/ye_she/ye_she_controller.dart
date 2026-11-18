import 'package:flutter/foundation.dart';

import 'ye_she_api_client.dart';
import 'ye_she_models.dart';

/// 野社三页的数据加载与交互状态。
///
/// 三个页签分别加载，任一模块失败只记录自己的错误，不会清空其他模块已经
/// 成功读取的数据。
class YeSheController extends ChangeNotifier {
  /// 创建控制器。
  YeSheController({required this.tokenProvider, YeSheApi? api})
    : _api = api ?? YeSheApiClient(tokenProvider: tokenProvider),
      _ownsApi = api == null;

  /// 当前阅微令牌。
  final String? Function() tokenProvider;

  final YeSheApi _api;
  final bool _ownsApi;

  bool _disposed = false;
  bool _loaded = false;
  bool _loadingStudy = false;
  bool _loadingPlay = false;
  bool _loadingDiscover = false;
  bool _loadingRanks = false;
  bool _authExpired = false;
  bool _actionBusy = false;
  String _actionName = '';
  String? _studyError;
  String? _playError;
  String? _discoverError;
  String? _ranksError;

  YeSheAccountStatus? _account;
  YeSheTitle? _title;
  YeSheSeals? _seals;
  YeSheNotelets? _notelets;
  YeSheMedals? _medals;
  YeSheCallingCards? _callingCards;
  YeSheLiterarySociety? _mySociety;
  YeSheLiterarySocietyScores? _societyScores;
  YeSheMerchantGuilds? _guilds;
  YeSheGuildAuction? _guildAuction;
  List<YeSheCollectionEntry> _collections = const <YeSheCollectionEntry>[];
  List<YeSheGuildMember> _guildMembers = const <YeSheGuildMember>[];
  List<YeSheGuildHistoryEntry> _guildHistory = const <YeSheGuildHistoryEntry>[];

  YeSheDailyLore? _dailyLore;
  YeSheGambling? _gambling;
  YeSheAuction? _auction;
  YeSheTravelingMerchant? _travelingMerchant;
  List<YeSheTravelTrip> _travelHistory = const <YeSheTravelTrip>[];
  YeSheRetainers? _retainers;

  YeSheWishUp? _wishUp;
  YeSheTaoistBlessing? _taoistBlessing;
  YeShePawnCount? _pawnCount;
  List<YeSheMaterial> _materials = const <YeSheMaterial>[];
  YeSheDailyShop? _dailyShop;
  YeSheVoucherShop? _voucherShop;
  YeSheMutualMarket? _mutualMarket;
  List<YeSheRumor> _rumors = const <YeSheRumor>[];
  List<YeSheThought> _thoughts = const <YeSheThought>[];
  YeSheMedalTreasure? _medalTreasure;
  Map<YeSheRankKind, YeSheRankBoard> _ranks =
      const <YeSheRankKind, YeSheRankBoard>{};

  /// 是否已有阅微令牌。
  bool get signedIn => tokenProvider()?.trim().isNotEmpty == true;

  /// 是否已经执行过一次加载。
  bool get loaded => _loaded;

  /// 文房是否正在加载。
  bool get loadingStudy => _loadingStudy;

  /// 游艺是否正在加载。
  bool get loadingPlay => _loadingPlay;

  /// 见闻是否正在加载。
  bool get loadingDiscover => _loadingDiscover;

  /// 排行榜是否正在加载。
  bool get loadingRanks => _loadingRanks;

  /// 登录是否已在请求过程中失效。
  bool get authExpired => _authExpired;

  /// 是否正在执行写操作。
  bool get actionBusy => _actionBusy;

  /// 当前写操作名称。
  String get actionName => _actionName;

  /// 文房局部错误。
  String? get studyError => _studyError;

  /// 游艺局部错误。
  String? get playError => _playError;

  /// 见闻局部错误。
  String? get discoverError => _discoverError;

  /// 排行榜局部错误。
  String? get ranksError => _ranksError;

  YeSheAccountStatus? get account => _account;
  YeSheTitle? get title => _title;
  YeSheSeals? get seals => _seals;
  YeSheNotelets? get notelets => _notelets;
  YeSheMedals? get medals => _medals;
  YeSheCallingCards? get callingCards => _callingCards;
  YeSheLiterarySociety? get mySociety => _mySociety;
  YeSheLiterarySocietyScores? get societyScores => _societyScores;
  YeSheMerchantGuilds? get guilds => _guilds;
  YeSheGuildAuction? get guildAuction => _guildAuction;
  List<YeSheCollectionEntry> get collections => _collections;
  List<YeSheGuildMember> get guildMembers => _guildMembers;
  List<YeSheGuildHistoryEntry> get guildHistory => _guildHistory;
  YeSheDailyLore? get dailyLore => _dailyLore;
  YeSheGambling? get gambling => _gambling;
  YeSheAuction? get auction => _auction;
  YeSheTravelingMerchant? get travelingMerchant => _travelingMerchant;
  List<YeSheTravelTrip> get travelHistory => _travelHistory;
  YeSheRetainers? get retainers => _retainers;
  YeSheWishUp? get wishUp => _wishUp;
  YeSheTaoistBlessing? get taoistBlessing => _taoistBlessing;
  YeShePawnCount? get pawnCount => _pawnCount;
  List<YeSheMaterial> get materials => _materials;
  YeSheDailyShop? get dailyShop => _dailyShop;
  YeSheVoucherShop? get voucherShop => _voucherShop;
  YeSheMutualMarket? get mutualMarket => _mutualMarket;
  List<YeSheRumor> get rumors => _rumors;
  List<YeSheThought> get thoughts => _thoughts;
  YeSheMedalTreasure? get medalTreasure => _medalTreasure;
  Map<YeSheRankKind, YeSheRankBoard> get ranks => _ranks;

  /// 首次加载三个页签。
  Future<void> loadAll() async {
    if (_loaded || !signedIn || _disposed) return;
    _loaded = true;
    await Future.wait<void>(<Future<void>>[
      refreshStudy(),
      refreshPlay(),
      refreshDiscover(),
      refreshRanks(),
    ]);
  }

  /// 全部刷新。
  Future<void> refreshAll() async {
    if (!signedIn || _disposed) return;
    _loaded = true;
    await Future.wait<void>(<Future<void>>[
      refreshStudy(),
      refreshPlay(),
      refreshDiscover(),
      refreshRanks(),
    ]);
  }

  /// 刷新五类排行榜；单类失败不影响其他榜单。
  Future<void> refreshRanks() async {
    if (!_canLoad() || _loadingRanks) return;
    _loadingRanks = true;
    _ranksError = null;
    _notify();
    final failures = <String>[];
    final results = await Future.wait<YeSheRankBoard?>(
      <Future<YeSheRankBoard?>>[
        _attemptRank(
          '阅读时长',
          YeSheRankKind.readDuration,
          _api.fetchReadDurationRank(),
          failures,
        ),
        _attemptRank(
          '财富',
          YeSheRankKind.wealth,
          _api.fetchWealthRank(),
          failures,
        ),
        _attemptRank(
          '聚宝楼',
          YeSheRankKind.auction,
          _api.fetchAuctionRank(),
          failures,
        ),
        _attemptRank(
          '收藏价值',
          YeSheRankKind.collectionValue,
          _api.fetchCollectionValueRank(),
          failures,
        ),
        _attemptRank(
          '名帖',
          YeSheRankKind.communityTitle,
          _api.fetchCommunityTitleRank(),
          failures,
        ),
      ],
    );
    if (_disposed) return;
    final next = Map<YeSheRankKind, YeSheRankBoard>.of(_ranks);
    for (final board in results) {
      if (board != null) next[board.kind] = board;
    }
    _ranks = Map<YeSheRankKind, YeSheRankBoard>.unmodifiable(next);
    _loadingRanks = false;
    _ranksError = _failureText(failures);
    _notify();
  }

  Future<YeSheRankBoard?> _attemptRank(
    String name,
    YeSheRankKind kind,
    Future<YeSheJson> request,
    List<String> failures,
  ) async {
    try {
      return YeSheRankBoard.fromJson(await request, kind);
    } catch (error) {
      _recordAuth(error);
      failures.add('$name榜：${_messageOf(error)}');
      return null;
    }
  }

  /// 刷新文房。
  Future<void> refreshStudy() async {
    if (!_canLoad() || _loadingStudy) return;
    _loadingStudy = true;
    _studyError = null;
    _notify();
    final failures = <String>[];
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _attempt(
        '账户',
        _api.fetchCommunityStatus(),
        YeSheAccountStatus.fromJson,
        failures,
      ),
      _attempt('名帖', _api.fetchCommunityTitle(), YeSheTitle.fromJson, failures),
      _attempt('藏印', _api.fetchUserSeals(), YeSheSeals.fromJson, failures),
      _attempt(
        '花笺',
        _api.fetchUserNotelets(),
        YeSheNotelets.fromJson,
        failures,
      ),
      _attempt('徽章', _api.fetchUserMedals(), YeSheMedals.fromJson, failures),
      _attempt(
        '名片',
        _api.fetchUserCallingCards(),
        YeSheCallingCards.fromJson,
        failures,
      ),
      _attempt<YeSheLiterarySociety?>(
        '我的文会',
        _api.fetchMyLiterarySociety(),
        _societyFromJson,
        failures,
      ),
      _attempt(
        '商会',
        _api.fetchMerchantGuilds(),
        YeSheMerchantGuilds.fromJson,
        failures,
      ),
      _attempt(
        '我的收藏',
        _api.fetchMyCollections(),
        _collectionsFromJson,
        failures,
      ),
    ]);
    if (_disposed) return;
    _account = results[0] as YeSheAccountStatus?;
    _title = results[1] as YeSheTitle?;
    _seals = results[2] as YeSheSeals?;
    _notelets = results[3] as YeSheNotelets?;
    _medals = results[4] as YeSheMedals?;
    _callingCards = results[5] as YeSheCallingCards?;
    _mySociety = results[6] as YeSheLiterarySociety?;
    _guilds = results[7] as YeSheMerchantGuilds?;
    _collections =
        results[8] as List<YeSheCollectionEntry>? ??
        const <YeSheCollectionEntry>[];
    _societyScores = null;
    if (_mySociety != null) {
      try {
        _societyScores = YeSheLiterarySocietyScores.fromJson(
          await _api.fetchLiterarySocietyScores(),
        );
      } catch (error) {
        _recordAuth(error);
        failures.add('文会声望：${_messageOf(error)}');
      }
    }
    _guildAuction = null;
    if (_guilds?.membership?.joined == true) {
      try {
        _guildAuction = _guildAuctionFromJson(await _api.fetchGuildAuction());
      } catch (error) {
        _recordAuth(error);
        failures.add('商会拍卖：${_messageOf(error)}');
      }
    }
    _loadingStudy = false;
    _studyError = _failureText(failures);
    _notify();
  }

  /// 刷新游艺。
  Future<void> refreshPlay() async {
    if (!_canLoad() || _loadingPlay) return;
    _loadingPlay = true;
    _playError = null;
    _notify();
    final failures = <String>[];
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _attempt<YeSheDailyLore?>(
        '每日轶闻',
        _api.fetchDailyLore(),
        _dailyLoreFromJson,
        failures,
      ),
      _attempt<YeSheAuction?>(
        '聚宝楼',
        _api.fetchAuction(),
        _auctionFromJson,
        failures,
      ),
      _attempt(
        '樗蒲',
        _api.fetchTodayGambling(),
        YeSheGambling.fromJson,
        failures,
      ),
      _attempt(
        '行商',
        _api.fetchTravelingMerchant(),
        YeSheTravelingMerchant.fromJson,
        failures,
      ),
      _attempt(
        '行商记录',
        _api.fetchTravelingMerchantHistory(),
        _tripsFromJson,
        failures,
      ),
      _attempt(
        '门客',
        _api.fetchTravelingMerchantRetainers(),
        YeSheRetainers.fromJson,
        failures,
      ),
    ]);
    if (_disposed) return;
    _dailyLore = results[0] as YeSheDailyLore?;
    _auction = results[1] as YeSheAuction?;
    _gambling = results[2] as YeSheGambling?;
    _travelingMerchant = results[3] as YeSheTravelingMerchant?;
    _travelHistory =
        results[4] as List<YeSheTravelTrip>? ?? const <YeSheTravelTrip>[];
    _retainers = results[5] as YeSheRetainers?;
    _loadingPlay = false;
    _playError = _failureText(failures);
    _notify();
  }

  /// 刷新见闻。
  Future<void> refreshDiscover() async {
    if (!_canLoad() || _loadingDiscover) return;
    _loadingDiscover = true;
    _discoverError = null;
    _notify();
    final failures = <String>[];
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _attempt('祈愿', _api.fetchWishUp(), YeSheWishUp.fromJson, failures),
      _attempt(
        '道观',
        _api.fetchTaoistBlessing(),
        YeSheTaoistBlessing.fromJson,
        failures,
      ),
      _attempt('期物司', _api.fetchPawnCount(), YeShePawnCount.fromJson, failures),
      _attempt(
        '可典当材料',
        _api.fetchUserMaterials(),
        _materialsFromJson,
        failures,
      ),
      _attempt('百杂铺', _api.fetchDailyShop(), YeSheDailyShop.fromJson, failures),
      _attempt(
        '玉机阁',
        _api.fetchVoucherShop(),
        YeSheVoucherShop.fromJson,
        failures,
      ),
      _attempt(
        '互市坊',
        _api.fetchMutualMarket(),
        YeSheMutualMarket.fromJson,
        failures,
      ),
      _attempt('唱经楼', _api.fetchRumors(), _rumorsFromJson, failures),
      _attempt('社区想法', _api.fetchPublicThoughts(), _thoughtsFromJson, failures),
      _attempt(
        '徽章征集',
        _api.fetchMedalTreasure(),
        YeSheMedalTreasure.fromJson,
        failures,
      ),
    ]);
    if (_disposed) return;
    _wishUp = results[0] as YeSheWishUp?;
    _taoistBlessing = results[1] as YeSheTaoistBlessing?;
    _pawnCount = results[2] as YeShePawnCount?;
    _materials = results[3] as List<YeSheMaterial>? ?? const <YeSheMaterial>[];
    _dailyShop = results[4] as YeSheDailyShop?;
    _voucherShop = results[5] as YeSheVoucherShop?;
    _mutualMarket = results[6] as YeSheMutualMarket?;
    _rumors = results[7] as List<YeSheRumor>? ?? const <YeSheRumor>[];
    _thoughts = results[8] as List<YeSheThought>? ?? const <YeSheThought>[];
    _medalTreasure = results[9] as YeSheMedalTreasure?;
    _loadingDiscover = false;
    _discoverError = _failureText(failures);
    _notify();
  }

  /// 查询公开文会。
  Future<List<YeSheLiterarySociety>> searchLiterarySocieties() async {
    if (!_canLoad()) return const <YeSheLiterarySociety>[];
    try {
      final result = YeSheLiterarySocieties.fromJson(
        await _api.fetchLiterarySocieties(),
      );
      return result.items;
    } catch (error) {
      _recordAuth(error);
      return const <YeSheLiterarySociety>[];
    }
  }

  /// 读取商会成员。
  Future<void> loadGuildMembers() async {
    if (!_canLoad()) return;
    try {
      final json = await _api.fetchMerchantGuildMembers();
      _guildMembers = <YeSheGuildMember>[
        for (final item in yeSheMapList(json['items']))
          YeSheGuildMember.fromJson(item),
      ];
      _notify();
    } catch (error) {
      _recordAuth(error);
    }
  }

  /// 读取商会行商动态。
  Future<void> loadGuildHistory() async {
    if (!_canLoad()) return;
    try {
      final json = await _api.fetchMerchantGuildHistory();
      _guildHistory = <YeSheGuildHistoryEntry>[
        for (final item in yeSheMapList(json['items']))
          YeSheGuildHistoryEntry.fromJson(item),
      ];
      _notify();
    } catch (error) {
      _recordAuth(error);
    }
  }

  /// 读取某条想法的收藏者。
  Future<List<Map<String, dynamic>>> loadMarkCollectors(int markId) async {
    if (!_canLoad()) return const <Map<String, dynamic>>[];
    try {
      final json = await _api.fetchMarkCollectors(markId: markId);
      return yeSheMapList(json['items']);
    } catch (error) {
      _recordAuth(error);
      return const <Map<String, dynamic>>[];
    }
  }

  /// 升级名帖。
  Future<YeSheActionResult> upgradeTitle() =>
      _perform('名帖升级', '名帖已升级', _api.upgradeCommunityTitle, refreshStudy);

  /// 传承名帖。
  Future<YeSheActionResult> heritageTitle() =>
      _perform('名帖传承', '名帖已传承', _api.heritageCommunityTitle, refreshStudy);

  /// 弃置当前名帖。
  Future<YeSheActionResult> abandonTitle() =>
      _perform('弃置名帖', '名帖已弃置', _api.abandonCommunityTitle, refreshStudy);

  /// 使用名片。
  Future<YeSheActionResult> useCallingCard(int id) =>
      _perform('使用名片', '名片已使用', () => _api.useCallingCard(id), refreshStudy);

  /// 盖章。
  Future<YeSheActionResult> stampSeal({
    required int sealId,
    required int reviewId,
  }) => _perform(
    '盖章',
    '已盖章',
    () => _api.stampSeal(sealId: sealId, reviewId: reviewId),
    refreshStudy,
  );

  /// 使用花笺。
  Future<YeSheActionResult> stampNotelet({
    required int noteletId,
    required int reviewId,
  }) => _perform(
    '使用花笺',
    '花笺已使用',
    () => _api.stampNotelet(noteletId: noteletId, reviewId: reviewId),
    refreshStudy,
  );

  /// 创建文会。
  Future<YeSheActionResult> createSociety({
    required String name,
    required bool isPublic,
  }) => _perform(
    '创建文会',
    '文会已创建',
    () => _api.createLiterarySociety(name: name, isPublic: isPublic),
    refreshStudy,
  );

  /// 邀请码加入文会。
  Future<YeSheActionResult> joinSociety(String inviteCode) => _perform(
    '加入文会',
    '已加入文会',
    () => _api.joinLiterarySociety(inviteCode),
    refreshStudy,
  );

  /// 加入公开文会。
  Future<YeSheActionResult> joinPublicSociety(int id) => _perform(
    '加入文会',
    '已加入文会',
    () => _api.joinPublicLiterarySociety(id),
    refreshStudy,
  );

  /// 退出文会。
  Future<YeSheActionResult> quitSociety() =>
      _perform('退出文会', '已退出文会', _api.quitLiterarySociety, refreshStudy);

  /// 解散文会。
  Future<YeSheActionResult> dissolveSociety() =>
      _perform('解散文会', '文会已解散', _api.dissolveLiterarySociety, refreshStudy);

  /// 移出成员。
  Future<YeSheActionResult> kickSocietyMember(int userId) => _perform(
    '移出成员',
    '已移出文会成员',
    () => _api.kickLiterarySocietyMember(userId),
    refreshStudy,
  );

  /// 更新文会封面。
  Future<YeSheActionResult> updateSocietyCover(String coverUrl) => _perform(
    '更新文会封面',
    '文会封面已更新',
    () => _api.updateLiterarySocietyCover(coverUrl),
    refreshStudy,
  );

  /// 领取文会周奖励。
  Future<YeSheActionResult> claimSocietyReward() => _perform(
    '领取文会奖励',
    '文会周奖励已领取',
    _api.claimLiterarySocietyWeeklyReward,
    refreshStudy,
  );

  /// 加入商会。
  Future<YeSheActionResult> joinGuild(int id) =>
      _perform('加入商会', '已加入商会', () => _api.joinMerchantGuild(id), refreshStudy);

  /// 退出商会。
  Future<YeSheActionResult> leaveGuild() =>
      _perform('退出商会', '已退出商会', _api.leaveMerchantGuild, refreshStudy);

  /// 完成每日轶闻。
  Future<YeSheActionResult> completeLore() {
    final id = _dailyLore?.id ?? 0;
    if (id <= 0) {
      return Future<YeSheActionResult>.value(
        const YeSheActionResult(success: false, message: '当前没有可完成的轶闻'),
      );
    }
    return _perform(
      '完成轶闻',
      '今日轶闻已完成',
      () => _api.completeDailyLore(id),
      refreshPlay,
    );
  }

  /// 参与樗蒲。
  Future<YeSheActionResult> betGambling() {
    final id = _gambling?.id ?? 0;
    if (id <= 0) {
      return Future<YeSheActionResult>.value(
        const YeSheActionResult(success: false, message: '当前没有可参与的樗蒲'),
      );
    }
    return _perform('参与樗蒲', '已参与今日樗蒲', () => _api.betGambling(id), refreshPlay);
  }

  /// 领取樗蒲奖励。
  Future<YeSheActionResult> claimGambling() {
    final id = _gambling?.id ?? 0;
    if (id <= 0) {
      return Future<YeSheActionResult>.value(
        const YeSheActionResult(success: false, message: '当前没有可领取的奖励'),
      );
    }
    return _perform(
      '领取樗蒲奖励',
      '樗蒲奖励已领取',
      () => _api.claimGamblingReward(id),
      refreshPlay,
    );
  }

  /// 聚宝楼出价。
  Future<YeSheActionResult> bidAuction(int amount) {
    final id = _auction?.id ?? 0;
    if (id <= 0) {
      return Future<YeSheActionResult>.value(
        const YeSheActionResult(success: false, message: '当前没有可出价的拍品'),
      );
    }
    return _perform(
      '聚宝楼出价',
      '出价已提交',
      () => _api.bidAuction(id: id, amount: amount),
      refreshPlay,
    );
  }

  /// 商会拍卖出价。
  Future<YeSheActionResult> bidGuildAuction(int amount) {
    final id = _guildAuction?.id ?? 0;
    if (id <= 0) {
      return Future<YeSheActionResult>.value(
        const YeSheActionResult(success: false, message: '当前没有可出价的商会拍品'),
      );
    }
    return _perform(
      '商会拍卖出价',
      '出价已提交',
      () => _api.bidGuildAuction(auctionId: id, amount: amount),
      refreshStudy,
    );
  }

  /// 开始行商。
  Future<YeSheActionResult> startTraveling({
    required String cityCode,
    required int transportId,
    required int principal,
  }) => _perform(
    '开始行商',
    '行商已出发',
    () => _api.startTravelingMerchant(
      cityCode: cityCode,
      transportId: transportId,
      principal: principal,
    ),
    refreshPlay,
  );

  /// 结算行商。
  Future<YeSheActionResult> settleTraveling() {
    final id = _travelingMerchant?.activeTrip?.id ?? 0;
    if (id <= 0) {
      return Future<YeSheActionResult>.value(
        const YeSheActionResult(success: false, message: '当前没有可结算的行程'),
      );
    }
    return _perform(
      '结算行商',
      '行商已结算',
      () => _api.settleTravelingMerchant(id),
      refreshPlay,
    );
  }

  /// 招募门客。
  Future<YeSheActionResult> recruitRetainer() => _perform(
    '招募门客',
    '门客招募完成',
    _api.recruitTravelingMerchantRetainer,
    refreshPlay,
  );

  /// 刷新门客招募状态。
  Future<void> refreshRetainerRecruitStatus() async {
    if (!_canLoad()) return;
    try {
      final json = await _api.fetchTravelingMerchantRetainerRecruitStatus();
      final current = _retainers;
      _retainers = YeSheRetainers(
        items: current?.items ?? const <YeSheRetainer>[],
        qinggui: yeSheInt(json['qinggui']),
        pityCount: yeSheInt(json['pityCount']),
      );
      _notify();
    } catch (error) {
      _recordAuth(error);
    }
  }

  /// 祈愿。
  Future<YeSheActionResult> makeWish(int count) =>
      _perform('祈愿', '祈愿已完成', () => _api.makeWish(count), refreshDiscover);

  /// 望言祈愿。
  Future<YeSheActionResult> wangyanWish() =>
      _perform('望言祈愿', '望言祈愿已完成', _api.wangyanWish, refreshDiscover);

  /// 道观祈福。
  Future<YeSheActionResult> pray(String blessingType) => _perform(
    '道观祈福',
    '祈福已完成',
    () => _api.prayTaoistBlessing(blessingType),
    refreshDiscover,
  );

  /// 典当材料。
  Future<YeSheActionResult> pawnMaterial(int userPropId) =>
      _perform('典当材料', '材料已典当', () => _api.pawn(userPropId), refreshDiscover);

  /// 购买百杂铺物品。
  Future<YeSheActionResult> buyDailyItem({
    required int propId,
    int quantity = 1,
  }) => _perform(
    '购买百杂铺物品',
    '购买成功',
    () => _api.buyDailyShop(propId: propId, quantity: quantity),
    refreshDiscover,
  );

  /// 购买玉机阁物品。
  Future<YeSheActionResult> buyVoucherItem({
    required int propId,
    int quantity = 1,
  }) => _perform(
    '购买玉机阁物品',
    '购买成功',
    () => _api.buyVoucherShop(propId: propId, quantity: quantity),
    refreshDiscover,
  );

  /// 购买奇珍盒。
  Future<YeSheActionResult> buyVoucherBox(int quantity) => _perform(
    '购买奇珍盒',
    '奇珍盒已购买',
    () => _api.buyVoucherBox(quantity),
    refreshDiscover,
  );

  /// 互市坊上架。
  Future<YeSheActionResult> createMarketListing({
    required int propId,
    required int unitPrice,
    required int quantity,
  }) => _perform(
    '互市坊上架',
    '物品已上架',
    () => _api.createMutualMarketListing(
      propId: propId,
      unitPrice: unitPrice,
      quantity: quantity,
    ),
    refreshDiscover,
  );

  /// 购买互市坊挂单。
  Future<YeSheActionResult> buyMarketListing({
    required int listingId,
    int quantity = 1,
  }) => _perform(
    '购买互市坊物品',
    '购买成功',
    () => _api.buyMutualMarketListing(listingId: listingId, quantity: quantity),
    refreshDiscover,
  );

  /// 取消互市坊挂单。
  Future<YeSheActionResult> cancelMarketListing(int listingId) => _perform(
    '取消互市坊挂单',
    '挂单已取消',
    () => _api.cancelMutualMarketListing(listingId),
    refreshDiscover,
  );

  /// 投入徽章征集。
  Future<YeSheActionResult> joinMedalTreasure(int count) => _perform(
    '投入徽章征集',
    '徽章征集投入成功',
    () => _api.joinMedalTreasure(count),
    refreshDiscover,
  );

  /// 收藏想法。
  Future<YeSheActionResult> collectThought({
    required int markId,
    required int collectionType,
  }) => _perform(
    '收藏想法',
    '已收藏',
    () => _api.collectMark(markId: markId, collectionType: collectionType),
    refreshDiscover,
  );

  /// 取消收藏。
  Future<YeSheActionResult> uncollectThought({
    required int markId,
    required int collectionType,
  }) => _perform(
    '取消收藏',
    '已取消收藏',
    () => _api.uncollectMark(markId: markId, collectionType: collectionType),
    refreshDiscover,
  );

  Future<T?> _attempt<T>(
    String label,
    Future<YeSheJson> request,
    T Function(Map<String, dynamic>) parse,
    List<String> failures,
  ) async {
    try {
      return parse(await request);
    } catch (error) {
      _recordAuth(error);
      failures.add('$label：${_messageOf(error)}');
      return null;
    }
  }

  Future<YeSheActionResult> _perform(
    String actionName,
    String successMessage,
    Future<YeSheJson> Function() action,
    Future<void> Function() refresh,
  ) async {
    if (!signedIn) {
      return const YeSheActionResult(
        success: false,
        message: '请先登录阅微账号',
        unauthorized: true,
      );
    }
    if (_actionBusy) {
      return YeSheActionResult(
        success: false,
        message: '正在执行「$_actionName」，请稍后',
      );
    }
    _actionBusy = true;
    _actionName = actionName;
    _notify();
    try {
      final result = await action();
      await refresh();
      final remoteMessage = yeSheText(result['message']).trim();
      return YeSheActionResult(
        success: true,
        message: remoteMessage.isEmpty ? successMessage : remoteMessage,
      );
    } catch (error) {
      _recordAuth(error);
      return YeSheActionResult(
        success: false,
        message: _messageOf(error),
        unauthorized: error is YeSheException && error.unauthorized,
      );
    } finally {
      _actionBusy = false;
      _actionName = '';
      _notify();
    }
  }

  bool _canLoad() {
    if (_disposed) return false;
    if (!signedIn) {
      _authExpired = true;
      return false;
    }
    return true;
  }

  void _recordAuth(Object error) {
    if (error is YeSheException && error.unauthorized) {
      _authExpired = true;
    }
  }

  String? _failureText(List<String> failures) {
    if (failures.isEmpty) return null;
    return '部分内容加载失败：${failures.join('；')}';
  }

  String _messageOf(Object error) {
    if (error is YeSheException) return error.message;
    return '操作失败：$error';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsApi) _api.close();
    super.dispose();
  }
}

YeSheLiterarySociety? _societyFromJson(Map<String, dynamic> json) {
  final raw = json['society'];
  if (raw is! Map) return null;
  return YeSheLiterarySociety.fromJson(yeSheMap(raw));
}

List<YeSheCollectionEntry> _collectionsFromJson(Map<String, dynamic> json) {
  return <YeSheCollectionEntry>[
    for (final item in yeSheMapList(json['items']))
      YeSheCollectionEntry.fromJson(item),
  ];
}

YeSheDailyLore? _dailyLoreFromJson(Map<String, dynamic> json) {
  if (json.isEmpty || json['id'] == null) return null;
  return YeSheDailyLore.fromJson(json);
}

YeSheAuction? _auctionFromJson(Map<String, dynamic> json) {
  final raw = json['auction'];
  if (raw is! Map) return null;
  return YeSheAuction.fromJson(yeSheMap(raw));
}

YeSheGuildAuction? _guildAuctionFromJson(Map<String, dynamic> json) {
  final auction = YeSheGuildAuction.fromJson(json);
  return auction.hasAuction ? auction : null;
}

List<YeSheTravelTrip> _tripsFromJson(Map<String, dynamic> json) {
  return <YeSheTravelTrip>[
    for (final item in yeSheMapList(json['items']))
      YeSheTravelTrip.fromJson(item),
  ];
}

List<YeSheMaterial> _materialsFromJson(Map<String, dynamic> json) {
  return <YeSheMaterial>[
    for (final item in yeSheMapList(json['materials']))
      YeSheMaterial.fromJson(item),
  ];
}

List<YeSheRumor> _rumorsFromJson(Map<String, dynamic> json) {
  return <YeSheRumor>[
    for (final item in yeSheMapList(json['items'])) YeSheRumor.fromJson(item),
  ];
}

List<YeSheThought> _thoughtsFromJson(Map<String, dynamic> json) {
  return <YeSheThought>[
    for (final item in yeSheMapList(json['items'])) YeSheThought.fromJson(item),
  ];
}
