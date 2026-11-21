import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 野社接口返回的 JSON 对象。
typedef YeSheJson = Map<String, dynamic>;

/// 野社接口异常。
class YeSheException implements Exception {
  /// 创建异常。
  const YeSheException(
    this.message, {
    this.statusCode,
    this.code,
    this.unauthorized = false,
  });

  /// 可展示给用户的错误信息。
  final String message;

  /// HTTP 状态码。
  final int? statusCode;

  /// 业务错误码。
  final int? code;

  /// 登录状态是否已经失效。
  final bool unauthorized;

  @override
  String toString() => message;
}

/// 野社接口集合，便于控制器测试时替换为内存实现。
abstract interface class YeSheApi {
  /// 读取社区账户状态。
  Future<YeSheJson> fetchCommunityStatus();

  /// 读取今日轶闻。
  Future<YeSheJson> fetchDailyLore();

  /// 完成今日轶闻。
  Future<YeSheJson> completeDailyLore(int userLoreId);

  /// 读取聚宝楼当前拍品。
  Future<YeSheJson> fetchAuction();

  /// 对聚宝楼拍品出价。
  Future<YeSheJson> bidAuction({required int id, required int amount});

  /// 读取今日樗蒲。
  Future<YeSheJson> fetchTodayGambling();

  /// 参与今日樗蒲。
  Future<YeSheJson> betGambling(int id);

  /// 领取樗蒲奖励。
  Future<YeSheJson> claimGamblingReward(int id);

  /// 读取个人名帖。
  Future<YeSheJson> fetchCommunityTitle();

  /// 升级名帖。
  Future<YeSheJson> upgradeCommunityTitle();

  /// 传承名帖。
  Future<YeSheJson> heritageCommunityTitle();

  /// 弃置当前名帖。
  Future<YeSheJson> abandonCommunityTitle();

  /// 读取本周祈愿提升。
  Future<YeSheJson> fetchWishUp();

  /// 进行一次祈愿。
  Future<YeSheJson> makeWish(int count);

  /// 进行一次望言祈愿。
  Future<YeSheJson> wangyanWish();

  /// 读取道观祈福状态。
  Future<YeSheJson> fetchTaoistBlessing();

  /// 道观祈福。
  Future<YeSheJson> prayTaoistBlessing(String blessingType);

  /// 读取今日期物典当次数。
  Future<YeSheJson> fetchPawnCount();

  /// 读取可用于典当的材料。
  Future<YeSheJson> fetchUserMaterials({String ids = ''});

  /// 典当一件材料。
  Future<YeSheJson> pawn(int userPropId);

  /// 读取行商状态。
  Future<YeSheJson> fetchTravelingMerchant();

  /// 读取行商历史。
  Future<YeSheJson> fetchTravelingMerchantHistory({
    int page = 1,
    int size = 20,
  });

  /// 开始一趟行商。
  Future<YeSheJson> startTravelingMerchant({
    required String cityCode,
    required int transportId,
    required int principal,
  });

  /// 结算一趟行商。
  Future<YeSheJson> settleTravelingMerchant(int tripId);

  /// 读取行商门客。
  Future<YeSheJson> fetchTravelingMerchantRetainers();

  /// 读取行商门客招募状态。
  Future<YeSheJson> fetchTravelingMerchantRetainerRecruitStatus();

  /// 招募一名行商门客。
  Future<YeSheJson> recruitTravelingMerchantRetainer();

  /// 读取商会。
  Future<YeSheJson> fetchMerchantGuilds();

  /// 读取商会拍卖。
  Future<YeSheJson> fetchGuildAuction();

  /// 对商会拍卖出价。
  Future<YeSheJson> bidGuildAuction({
    required int auctionId,
    required int amount,
  });

  /// 加入商会。
  Future<YeSheJson> joinMerchantGuild(int guildId);

  /// 退出商会。
  Future<YeSheJson> leaveMerchantGuild();

  /// 读取商会成员。
  Future<YeSheJson> fetchMerchantGuildMembers({
    int beforeUserId = 0,
    int size = 20,
  });

  /// 读取商会行商记录。
  Future<YeSheJson> fetchMerchantGuildHistory({
    int beforeId = 0,
    int size = 20,
  });

  /// 读取百杂铺。
  Future<YeSheJson> fetchDailyShop();

  /// 读取玉机阁。
  Future<YeSheJson> fetchVoucherShop();

  /// 购买百杂铺商品。
  Future<YeSheJson> buyDailyShop({required int propId, required int quantity});

  /// 购买玉机阁商品。
  Future<YeSheJson> buyVoucherShop({
    required int propId,
    required int quantity,
  });

  /// 购买奇珍盒。
  Future<YeSheJson> buyVoucherBox(int quantity);

  /// 读取互市坊。
  Future<YeSheJson> fetchMutualMarket();

  /// 在互市坊上架材料。
  Future<YeSheJson> createMutualMarketListing({
    required int propId,
    required int unitPrice,
    required int quantity,
  });

  /// 购买互市坊挂单。
  Future<YeSheJson> buyMutualMarketListing({
    required int listingId,
    required int quantity,
  });

  /// 取消互市坊挂单。
  Future<YeSheJson> cancelMutualMarketListing(int listingId);

  /// 读取唱经楼传闻。
  Future<YeSheJson> fetchRumors({int page = 1, int size = 20});

  /// 读取我的收藏。
  Future<YeSheJson> fetchMyCollections({int page = 1, int size = 50});

  /// 读取藏印。
  Future<YeSheJson> fetchUserSeals();

  /// 读取花笺。
  Future<YeSheJson> fetchUserNotelets();

  /// 读取徽章。
  Future<YeSheJson> fetchUserMedals();

  /// 读取名片。
  Future<YeSheJson> fetchUserCallingCards();

  /// 盖章到一条书评。
  Future<YeSheJson> stampSeal({required int sealId, required int reviewId});

  /// 使用花笺到一条书评。
  Future<YeSheJson> stampNotelet({
    required int noteletId,
    required int reviewId,
  });

  /// 使用名片。
  Future<YeSheJson> useCallingCard(int callingCardId);

  /// 读取我的文会。
  Future<YeSheJson> fetchMyLiterarySociety();

  /// 读取公开文会。
  Future<YeSheJson> fetchLiterarySocieties({int page = 1, int size = 20});

  /// 创建文会。
  Future<YeSheJson> createLiterarySociety({
    required String name,
    required bool isPublic,
  });

  /// 通过邀请码加入文会。
  Future<YeSheJson> joinLiterarySociety(String inviteCode);

  /// 加入公开文会。
  Future<YeSheJson> joinPublicLiterarySociety(int societyId);

  /// 退出文会。
  Future<YeSheJson> quitLiterarySociety();

  /// 解散文会。
  Future<YeSheJson> dissolveLiterarySociety();

  /// 移出文会成员。
  Future<YeSheJson> kickLiterarySocietyMember(int userId);

  /// 更新文会封面。
  Future<YeSheJson> updateLiterarySocietyCover(String coverUrl);

  /// 领取文会每周奖励。
  Future<YeSheJson> claimLiterarySocietyWeeklyReward();

  /// 读取文会声望。
  Future<YeSheJson> fetchLiterarySocietyScores();

  /// 读取徽章征集。
  Future<YeSheJson> fetchMedalTreasure();

  /// 投入徽章征集。
  Future<YeSheJson> joinMedalTreasure(int count);

  /// 读取公开读书想法。
  Future<YeSheJson> fetchPublicThoughts({
    int page = 1,
    int size = 20,
    String bookId = '',
    String cloudBookId = '',
  });

  /// 收藏读书想法。
  Future<YeSheJson> collectMark({
    required int markId,
    required int collectionType,
  });

  /// 取消收藏读书想法。
  Future<YeSheJson> uncollectMark({
    required int markId,
    required int collectionType,
  });

  /// 读取收藏某条想法的用户。
  Future<YeSheJson> fetchMarkCollectors({
    required int markId,
    int page = 1,
    int size = 20,
  });

  /// 阅读时长榜。
  Future<YeSheJson> fetchReadDurationRank();

  /// 财富榜。
  Future<YeSheJson> fetchWealthRank();

  /// 聚宝楼拍卖榜。
  Future<YeSheJson> fetchAuctionRank();

  /// 收藏价值榜。
  Future<YeSheJson> fetchCollectionValueRank();

  /// 名帖榜。
  Future<YeSheJson> fetchCommunityTitleRank();

  /// 释放网络客户端。
  void close();
}

/// 阅微野社 HTTP 接口实现。
class YeSheApiClient implements YeSheApi {
  /// 创建客户端。
  YeSheApiClient({
    required this.tokenProvider,
    http.Client? client,
    this.baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 12),
    this.retryDelay = const Duration(milliseconds: 300),
  }) : _client = client ?? http.Client();

  /// 阅微开放接口根地址。
  static const String defaultBaseUrl = 'https://api.reamicro.zhendong.ltd/';

  final http.Client _client;

  /// 当前阅微令牌提供者。
  final String? Function() tokenProvider;

  /// 接口根地址。
  final String baseUrl;

  /// 单次请求超时。
  final Duration timeout;

  /// 读请求失败后的重试间隔。
  final Duration retryDelay;

  /// 会改变服务端数据的接口；这些请求不缓存也不自动重试。
  static const Set<String> _mutationEndpoints = <String>{
    'rest/community/complete-daily-lore',
    'rest/community/bid-auction',
    'rest/community/bet-gambling',
    'rest/community/get-gambling-reward',
    'rest/community/upgrade-community-title',
    'rest/community/heritage-community-title',
    'rest/community/abandon-community-title',
    'rest/community/wish',
    'rest/community/wangyan-wish',
    'rest/community/pray-taoist-blessing',
    'rest/community/pawn',
    'rest/community/start-traveling-merchant',
    'rest/community/settle-traveling-merchant',
    'rest/community/recruit-traveling-merchant-retainer',
    'rest/community/bid-guild-auction',
    'rest/community/join-merchant-guild',
    'rest/community/leave-merchant-guild',
    'rest/community/buy-daily-shop',
    'rest/community/buy-voucher-box',
    'rest/community/create-mutual-market-listing',
    'rest/community/buy-mutual-market-listing',
    'rest/community/cancel-mutual-market-listing',
    'rest/community/stamp-seal',
    'rest/community/stamp-notelet',
    'rest/community/use-calling-card',
    'rest/community/create-literary-society',
    'rest/community/join-literary-society',
    'rest/community/join-public-literary-society',
    'rest/community/quit-literary-society',
    'rest/community/dissolve-literary-society',
    'rest/community/kick-literary-society-member',
    'rest/community/update-literary-society-cover',
    'rest/community/claim-literary-society-weekly-reward',
    'rest/community/join-medal-treasure',
    'rest/community/collect-mark',
    'rest/community/uncollect-mark',
  };

  static const Duration _cacheTtl = Duration(seconds: 30);
  static const int _maxCacheEntries = 96;
  static final LinkedHashMap<String, _YeSheCacheEntry> _responseCache =
      LinkedHashMap<String, _YeSheCacheEntry>();

  /// 清理进程内读缓存；测试和切换账号时可主动调用。
  static void clearCache() => _responseCache.clear();

  @override
  Future<YeSheJson> fetchCommunityStatus() =>
      _post('rest/community/get-user-community-status');

  @override
  Future<YeSheJson> fetchDailyLore() => _post('rest/community/get-daily-lore');

  @override
  Future<YeSheJson> completeDailyLore(int userLoreId) => _post(
    'rest/community/complete-daily-lore',
    body: <String, Object?>{'userLoreId': userLoreId},
  );

  @override
  Future<YeSheJson> fetchAuction() => _post('rest/community/get-auction');

  @override
  Future<YeSheJson> bidAuction({required int id, required int amount}) => _post(
    'rest/community/bid-auction',
    body: <String, Object?>{'id': id, 'amount': amount},
  );

  @override
  Future<YeSheJson> fetchTodayGambling() =>
      _post('rest/community/get-today-gambling');

  @override
  Future<YeSheJson> betGambling(int id) =>
      _post('rest/community/bet-gambling', body: <String, Object?>{'id': id});

  @override
  Future<YeSheJson> claimGamblingReward(int id) => _post(
    'rest/community/get-gambling-reward',
    body: <String, Object?>{'id': id},
  );

  @override
  Future<YeSheJson> fetchCommunityTitle() =>
      _post('rest/community/get-community-title');

  @override
  Future<YeSheJson> upgradeCommunityTitle() =>
      _post('rest/community/upgrade-community-title');

  @override
  Future<YeSheJson> heritageCommunityTitle() =>
      _post('rest/community/heritage-community-title');

  @override
  Future<YeSheJson> abandonCommunityTitle() =>
      _post('rest/community/abandon-community-title');

  @override
  Future<YeSheJson> fetchWishUp() => _post('rest/community/get-wish-up');

  @override
  Future<YeSheJson> makeWish(int count) =>
      _post('rest/community/wish', body: <String, Object?>{'count': count});

  @override
  Future<YeSheJson> wangyanWish() => _post('rest/community/wangyan-wish');

  @override
  Future<YeSheJson> fetchTaoistBlessing() =>
      _post('rest/community/get-taoist-blessing');

  @override
  Future<YeSheJson> prayTaoistBlessing(String blessingType) => _post(
    'rest/community/pray-taoist-blessing',
    body: <String, Object?>{'blessingType': blessingType},
  );

  @override
  Future<YeSheJson> fetchPawnCount() => _post('rest/community/get-pawn-count');

  @override
  Future<YeSheJson> fetchUserMaterials({String ids = ''}) => _post(
    'rest/community/get-user-materials',
    body: <String, Object?>{'ids': ids},
  );

  @override
  Future<YeSheJson> pawn(int userPropId) => _post(
    'rest/community/pawn',
    body: <String, Object?>{'userPropId': userPropId},
  );

  @override
  Future<YeSheJson> fetchTravelingMerchant() =>
      _post('rest/community/get-traveling-merchant');

  @override
  Future<YeSheJson> fetchTravelingMerchantHistory({
    int page = 1,
    int size = 20,
  }) => _post(
    'rest/community/get-traveling-merchant-history',
    body: <String, Object?>{'page': page, 'size': size},
  );

  @override
  Future<YeSheJson> startTravelingMerchant({
    required String cityCode,
    required int transportId,
    required int principal,
  }) => _post(
    'rest/community/start-traveling-merchant',
    body: <String, Object?>{
      'cityCode': cityCode,
      'transportId': transportId,
      'principal': principal,
    },
  );

  @override
  Future<YeSheJson> settleTravelingMerchant(int tripId) => _post(
    'rest/community/settle-traveling-merchant',
    body: <String, Object?>{'tripId': tripId},
  );

  @override
  Future<YeSheJson> fetchTravelingMerchantRetainers() =>
      _post('rest/community/get-traveling-merchant-retainers');

  @override
  Future<YeSheJson> fetchTravelingMerchantRetainerRecruitStatus() =>
      _post('rest/community/get-traveling-merchant-retainer-recruit-status');

  @override
  Future<YeSheJson> recruitTravelingMerchantRetainer() =>
      _post('rest/community/recruit-traveling-merchant-retainer');

  @override
  Future<YeSheJson> fetchMerchantGuilds() =>
      _post('rest/community/get-merchant-guilds');

  @override
  Future<YeSheJson> fetchGuildAuction() =>
      _post('rest/community/get-guild-auction');

  @override
  Future<YeSheJson> bidGuildAuction({
    required int auctionId,
    required int amount,
  }) => _post(
    'rest/community/bid-guild-auction',
    body: <String, Object?>{'auctionId': auctionId, 'amount': amount},
  );

  @override
  Future<YeSheJson> joinMerchantGuild(int guildId) => _post(
    'rest/community/join-merchant-guild',
    body: <String, Object?>{'guildId': guildId},
  );

  @override
  Future<YeSheJson> leaveMerchantGuild() =>
      _post('rest/community/leave-merchant-guild');

  @override
  Future<YeSheJson> fetchMerchantGuildMembers({
    int beforeUserId = 0,
    int size = 20,
  }) => _post(
    'rest/community/get-merchant-guild-members',
    body: <String, Object?>{'beforeUserId': beforeUserId, 'size': size},
  );

  @override
  Future<YeSheJson> fetchMerchantGuildHistory({
    int beforeId = 0,
    int size = 20,
  }) => _post(
    'rest/community/get-merchant-guild-history',
    body: <String, Object?>{'beforeId': beforeId, 'size': size},
  );

  @override
  Future<YeSheJson> fetchDailyShop() => _post('rest/community/get-daily-shop');

  @override
  Future<YeSheJson> fetchVoucherShop() =>
      _post('rest/community/get-voucher-shop');

  @override
  Future<YeSheJson> buyDailyShop({
    required int propId,
    required int quantity,
  }) => _post(
    'rest/community/buy-daily-shop',
    body: <String, Object?>{'propId': propId, 'quantity': quantity},
  );

  @override
  Future<YeSheJson> buyVoucherShop({
    required int propId,
    required int quantity,
  }) => _post(
    // 阅微客户端用 BuyVoucherShopReq 请求体调用百杂铺购买接口；
    // 服务端没有独立的 buy-voucher-shop 路由。
    'rest/community/buy-daily-shop',
    body: <String, Object?>{'propId': propId, 'quantity': quantity},
  );

  @override
  Future<YeSheJson> buyVoucherBox(int quantity) => _post(
    'rest/community/buy-voucher-box',
    body: <String, Object?>{'quantity': quantity},
  );

  @override
  Future<YeSheJson> fetchMutualMarket() =>
      _post('rest/community/get-mutual-market');

  @override
  Future<YeSheJson> createMutualMarketListing({
    required int propId,
    required int unitPrice,
    required int quantity,
  }) => _post(
    'rest/community/create-mutual-market-listing',
    body: <String, Object?>{
      'propId': propId,
      'unitPrice': unitPrice,
      'quantity': quantity,
    },
  );

  @override
  Future<YeSheJson> buyMutualMarketListing({
    required int listingId,
    required int quantity,
  }) => _post(
    'rest/community/buy-mutual-market-listing',
    body: <String, Object?>{'listingId': listingId, 'quantity': quantity},
  );

  @override
  Future<YeSheJson> cancelMutualMarketListing(int listingId) => _post(
    'rest/community/cancel-mutual-market-listing',
    body: <String, Object?>{'listingId': listingId},
  );

  @override
  Future<YeSheJson> fetchRumors({int page = 1, int size = 20}) => _post(
    'rest/community/get-rumors',
    body: <String, Object?>{'page': page, 'size': size},
  );

  @override
  Future<YeSheJson> fetchMyCollections({int page = 1, int size = 50}) => _post(
    'rest/community/get-my-collections',
    body: <String, Object?>{'page': page, 'size': size},
  );

  @override
  Future<YeSheJson> fetchUserSeals() => _post('rest/community/get-user-seals');

  @override
  Future<YeSheJson> fetchUserNotelets() =>
      _post('rest/community/get-user-notelets');

  @override
  Future<YeSheJson> fetchUserMedals() =>
      _post('rest/community/get-user-medals');

  @override
  Future<YeSheJson> fetchUserCallingCards() =>
      _post('rest/community/get-user-calling-cards');

  @override
  Future<YeSheJson> stampSeal({required int sealId, required int reviewId}) =>
      _post(
        'rest/community/stamp-seal',
        body: <String, Object?>{'sealId': sealId, 'reviewId': reviewId},
      );

  @override
  Future<YeSheJson> stampNotelet({
    required int noteletId,
    required int reviewId,
  }) => _post(
    'rest/community/stamp-notelet',
    body: <String, Object?>{'noteletId': noteletId, 'reviewId': reviewId},
  );

  @override
  Future<YeSheJson> useCallingCard(int callingCardId) => _post(
    'rest/community/use-calling-card',
    body: <String, Object?>{'callingCardId': callingCardId},
  );

  @override
  Future<YeSheJson> fetchMyLiterarySociety() =>
      _post('rest/community/get-my-literary-society');

  @override
  Future<YeSheJson> fetchLiterarySocieties({int page = 1, int size = 20}) =>
      _post(
        'rest/community/get-literary-societies',
        body: <String, Object?>{'page': page, 'size': size},
      );

  @override
  Future<YeSheJson> createLiterarySociety({
    required String name,
    required bool isPublic,
  }) => _post(
    'rest/community/create-literary-society',
    body: <String, Object?>{'name': name, 'isPublic': isPublic},
  );

  @override
  Future<YeSheJson> joinLiterarySociety(String inviteCode) => _post(
    'rest/community/join-literary-society',
    body: <String, Object?>{'inviteCode': inviteCode},
  );

  @override
  Future<YeSheJson> joinPublicLiterarySociety(int societyId) => _post(
    'rest/community/join-public-literary-society',
    body: <String, Object?>{'societyId': societyId},
  );

  @override
  Future<YeSheJson> quitLiterarySociety() =>
      _post('rest/community/quit-literary-society');

  @override
  Future<YeSheJson> dissolveLiterarySociety() =>
      _post('rest/community/dissolve-literary-society');

  @override
  Future<YeSheJson> kickLiterarySocietyMember(int userId) => _post(
    'rest/community/kick-literary-society-member',
    body: <String, Object?>{'userId': userId},
  );

  @override
  Future<YeSheJson> updateLiterarySocietyCover(String coverUrl) => _post(
    'rest/community/update-literary-society-cover',
    body: <String, Object?>{'coverUrl': coverUrl},
  );

  @override
  Future<YeSheJson> claimLiterarySocietyWeeklyReward() =>
      _post('rest/community/claim-literary-society-weekly-reward');

  @override
  Future<YeSheJson> fetchLiterarySocietyScores() =>
      _post('rest/community/get-literary-society-scores');

  @override
  Future<YeSheJson> fetchMedalTreasure() =>
      _post('rest/community/get-medal-treasure');

  @override
  Future<YeSheJson> joinMedalTreasure(int count) => _post(
    'rest/community/join-medal-treasure',
    body: <String, Object?>{'count': count},
  );

  @override
  Future<YeSheJson> fetchPublicThoughts({
    int page = 1,
    int size = 20,
    String bookId = '',
    String cloudBookId = '',
  }) => _post(
    'rest/community/get-public-thoughts',
    body: <String, Object?>{
      'page': page,
      'size': size,
      'bookId': bookId,
      'cloudBookId': cloudBookId,
    },
  );

  @override
  Future<YeSheJson> collectMark({
    required int markId,
    required int collectionType,
  }) => _post(
    'rest/community/collect-mark',
    body: <String, Object?>{'markId': markId, 'collectionType': collectionType},
  );

  @override
  Future<YeSheJson> uncollectMark({
    required int markId,
    required int collectionType,
  }) => _post(
    'rest/community/uncollect-mark',
    body: <String, Object?>{'markId': markId, 'collectionType': collectionType},
  );

  @override
  Future<YeSheJson> fetchMarkCollectors({
    required int markId,
    int page = 1,
    int size = 20,
  }) => _post(
    'rest/community/get-mark-collectors',
    body: <String, Object?>{'markId': markId, 'page': page, 'size': size},
  );

  @override
  Future<YeSheJson> fetchReadDurationRank() =>
      _post('rest/rank/get-read-duration-rank');

  @override
  Future<YeSheJson> fetchWealthRank() => _post('rest/rank/get-wealth-rank');

  @override
  Future<YeSheJson> fetchAuctionRank() => _post('rest/rank/get-auction-rank');

  @override
  Future<YeSheJson> fetchCollectionValueRank() =>
      _post('rest/rank/get-collection-value-rank');

  @override
  Future<YeSheJson> fetchCommunityTitleRank() =>
      _post('rest/rank/get-community-title-rank');

  Future<YeSheJson> _post(
    String endpoint, {
    Map<String, Object?> body = const <String, Object?>{},
  }) async {
    final token = tokenProvider()?.trim();
    if (token == null || token.isEmpty) {
      throw const YeSheException('请先登录阅微账号', unauthorized: true);
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'platform': Platform.isIOS || Platform.isMacOS ? 'ios' : 'android',
      'Authorization': 'Bearer $token',
    };
    final mutation = _mutationEndpoints.contains(endpoint);
    final cacheKey = '$token|$endpoint|${jsonEncode(body)}';
    if (!mutation) {
      final cached = _responseCache.remove(cacheKey);
      if (cached != null) {
        if (DateTime.now().difference(cached.storedAt) <= _cacheTtl) {
          _responseCache[cacheKey] = cached;
          return cached.data;
        }
      }
    }
    final response = await _sendWithRetry(
      Uri.parse('$baseUrl$endpoint'),
      headers,
      jsonEncode(body),
      retryable: !mutation,
    );

    final raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? decoded;
    try {
      decoded = raw.isEmpty ? null : jsonDecode(raw);
    } on FormatException {
      throw YeSheException(
        '阅微野社接口返回了无法解析的数据（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    final map = decoded is Map<String, dynamic> ? decoded : null;
    final code = map == null ? null : _intValue(map['code']);
    final message = map == null
        ? null
        : _stringValue(map['message'] ?? map['msg']);
    final unauthorized =
        response.statusCode == 401 ||
        response.statusCode == 403 ||
        code == 401 ||
        code == 403;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YeSheException(
        message?.trim().isNotEmpty == true
            ? message!.trim()
            : '阅微野社接口请求失败（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
        code: code,
        unauthorized: unauthorized,
      );
    }
    if (code != null && code != 0 && code != 200) {
      throw YeSheException(
        message?.trim().isNotEmpty == true
            ? message!.trim()
            : '阅微野社接口返回业务码 $code',
        statusCode: response.statusCode,
        code: code,
        unauthorized: code == 401 || code == 403,
      );
    }
    if (map == null) {
      throw YeSheException(
        '阅微野社接口返回的数据格式不正确（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    final data = map['data'];
    final YeSheJson result;
    if (data is Map<String, dynamic>) {
      result = data;
    } else if (data is Map) {
      result = _mapValue(data);
    } else if (data is List) {
      result = <String, dynamic>{
        'items': List<Object?>.from(data),
        'message': message ?? '',
      };
    } else {
      result = <String, dynamic>{'value': ?data, 'message': message ?? ''};
    }
    if (mutation) {
      _responseCache.clear();
    } else {
      _remember(cacheKey, result);
    }
    return result;
  }

  Future<http.Response> _sendWithRetry(
    Uri uri,
    Map<String, String> headers,
    String body, {
    required bool retryable,
  }) async {
    final attempts = retryable ? 2 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _client
            .post(uri, headers: headers, body: body)
            .timeout(timeout);
        if (retryable &&
            attempt + 1 < attempts &&
            _retryableStatus(response.statusCode)) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        return response;
      } on TimeoutException {
        if (retryable && attempt + 1 < attempts) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        throw const YeSheException('阅微野社接口请求超时，请稍后重试');
      } on SocketException {
        if (retryable && attempt + 1 < attempts) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        throw const YeSheException('无法连接阅微服务器，请检查网络');
      } on http.ClientException catch (error) {
        if (retryable && attempt + 1 < attempts) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        throw YeSheException('阅微野社接口请求失败：${error.message}');
      }
    }
    throw const YeSheException('阅微野社接口请求失败，请稍后重试');
  }

  static bool _retryableStatus(int statusCode) =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;

  static void _remember(String key, YeSheJson data) {
    _responseCache.remove(key);
    _responseCache[key] = _YeSheCacheEntry(data, DateTime.now());
    while (_responseCache.length > _maxCacheEntries) {
      _responseCache.remove(_responseCache.keys.first);
    }
  }

  @override
  void close() => _client.close();
}

class _YeSheCacheEntry {
  const _YeSheCacheEntry(this.data, this.storedAt);

  final YeSheJson data;
  final DateTime storedAt;
}

Map<String, dynamic> _mapValue(Map<dynamic, dynamic> value) {
  return <String, dynamic>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '') ?? 0;
}

String? _stringValue(Object? value) => value is String ? value : null;
