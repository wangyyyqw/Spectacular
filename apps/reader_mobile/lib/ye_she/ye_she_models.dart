/// 野社接口的数据模型。
///
/// 阅微服务端的数值字段同时存在字符串、整数和小数形式，列表与嵌套对象也
/// 可能缺省。所有解析集中在这里做兼容，页面和控制器只处理规范化的值。
library;

Map<String, dynamic> yeSheMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> yeSheMapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in value)
      if (item is Map) yeSheMap(item),
  ];
}

String yeSheText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

int yeSheInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = value?.toString().trim() ?? '';
  return int.tryParse(text) ?? double.tryParse(text)?.round() ?? 0;
}

double yeSheDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '') ?? 0;
}

bool yeSheBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

DateTime? yeSheTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) {
    var milliseconds = value.toInt();
    if (milliseconds > 0 && milliseconds < 100000000000) {
      milliseconds *= 1000;
    }
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final numeric = int.tryParse(text);
  if (numeric != null) return yeSheTime(numeric);
  return DateTime.tryParse(text);
}

/// 社区账户状态。
class YeSheAccountStatus {
  const YeSheAccountStatus({
    this.exp = 0,
    this.expMax = 0,
    this.level = 0,
    this.coin = 0,
    this.gem = 0,
    this.voucher = 0,
    this.travelingMerchantProfit = 0,
    this.travelingMerchantLoss = 0,
    this.auctionProfit = 0,
    this.auctionLoss = 0,
  });

  factory YeSheAccountStatus.fromJson(Map<String, dynamic> json) {
    return YeSheAccountStatus(
      exp: yeSheInt(json['exp']),
      expMax: yeSheInt(json['expMax']),
      level: yeSheInt(json['level']),
      coin: yeSheInt(json['coin']),
      gem: yeSheInt(json['gem']),
      voucher: yeSheInt(json['voucher']),
      travelingMerchantProfit: yeSheInt(json['travelingMerchantProfit']),
      travelingMerchantLoss: yeSheInt(json['travelingMerchantLoss']),
      auctionProfit: yeSheInt(json['auctionProfit']),
      auctionLoss: yeSheInt(json['auctionLoss']),
    );
  }

  final int exp;
  final int expMax;
  final int level;
  final int coin;
  final int gem;
  final int voucher;
  final int travelingMerchantProfit;
  final int travelingMerchantLoss;
  final int auctionProfit;
  final int auctionLoss;

  int get travelingMerchantNet =>
      travelingMerchantProfit - travelingMerchantLoss;

  int get auctionNet => auctionProfit - auctionLoss;
}

/// 名帖。
class YeSheTitle {
  const YeSheTitle({
    this.title = '',
    this.level = 0,
    this.heritagePityCount = 0,
    this.upgradePityCount = 0,
    this.sourceName = '',
  });

  factory YeSheTitle.fromJson(Map<String, dynamic> json) {
    return YeSheTitle(
      title: yeSheText(json['title']),
      level: yeSheInt(json['titleLevel']),
      heritagePityCount: yeSheInt(json['heritagePityCount']),
      upgradePityCount: yeSheInt(json['upgradePityCount']),
      sourceName: yeSheText(json['sourceName']),
    );
  }

  final String title;
  final int level;
  final int heritagePityCount;
  final int upgradePityCount;
  final String sourceName;

  String get displayName => title.isEmpty ? '尚未获得雅号' : title;
}

/// 有名称和标识的简单物品。
class YeSheNamedItem {
  const YeSheNamedItem({this.id = 0, this.propId = 0, this.name = ''});

  factory YeSheNamedItem.fromJson(Map<String, dynamic> json) {
    return YeSheNamedItem(
      id: yeSheInt(json['id']),
      propId: yeSheInt(json['propId']),
      name: yeSheText(json['name']),
    );
  }

  final int id;
  final int propId;
  final String name;

  int get identity => id > 0 ? id : propId;
}

/// 藏印。
class YeSheSeals {
  const YeSheSeals({
    this.items = const <YeSheNamedItem>[],
    this.inkPasteQuantity = 0,
  });

  factory YeSheSeals.fromJson(Map<String, dynamic> json) {
    return YeSheSeals(
      items: <YeSheNamedItem>[
        for (final item in yeSheMapList(json['seals']))
          YeSheNamedItem.fromJson(item),
      ],
      inkPasteQuantity: yeSheInt(json['inkPasteQuantity']),
    );
  }

  final List<YeSheNamedItem> items;
  final int inkPasteQuantity;
}

/// 花笺。
class YeSheNotelets {
  const YeSheNotelets({
    this.items = const <YeSheNamedItem>[],
    this.paperQuantity = 0,
  });

  factory YeSheNotelets.fromJson(Map<String, dynamic> json) {
    return YeSheNotelets(
      items: <YeSheNamedItem>[
        for (final item in yeSheMapList(json['notelets']))
          YeSheNamedItem.fromJson(item),
      ],
      paperQuantity: yeSheInt(json['paperQuantity']),
    );
  }

  final List<YeSheNamedItem> items;
  final int paperQuantity;
}

/// 徽章目录。
class YeSheMedals {
  const YeSheMedals({this.items = const <YeSheNamedItem>[]});

  factory YeSheMedals.fromJson(Map<String, dynamic> json) {
    return YeSheMedals(
      items: <YeSheNamedItem>[
        for (final item in yeSheMapList(json['medals']))
          YeSheNamedItem.fromJson(item),
      ],
    );
  }

  final List<YeSheNamedItem> items;
}

/// 名片。
class YeSheCallingCards {
  const YeSheCallingCards({this.items = const <YeSheNamedItem>[]});

  factory YeSheCallingCards.fromJson(Map<String, dynamic> json) {
    return YeSheCallingCards(
      items: <YeSheNamedItem>[
        for (final item in yeSheMapList(json['callingCards']))
          YeSheNamedItem.fromJson(item),
      ],
    );
  }

  final List<YeSheNamedItem> items;
}

/// 文会成员。
class YeSheSocietyMember {
  const YeSheSocietyMember({
    this.userId = 0,
    this.nickName = '',
    this.avatar = '',
    this.level = 0,
    this.weekScore = 0,
    this.isPresident = false,
    this.title = '',
    this.titleLevel = 0,
    this.recentBookName = '',
  });

  factory YeSheSocietyMember.fromJson(Map<String, dynamic> json) {
    return YeSheSocietyMember(
      userId: yeSheInt(json['userId']),
      nickName: yeSheText(json['nickName']),
      avatar: yeSheText(json['avatar']),
      level: yeSheInt(json['level']),
      weekScore: yeSheInt(json['weekScore']),
      isPresident: yeSheBool(json['isPresident']),
      title: yeSheText(json['title']),
      titleLevel: yeSheInt(json['titleLevel']),
      recentBookName: yeSheText(json['recentBookName']),
    );
  }

  final int userId;
  final String nickName;
  final String avatar;
  final int level;
  final int weekScore;
  final bool isPresident;
  final String title;
  final int titleLevel;
  final String recentBookName;
}

/// 文会。
class YeSheLiterarySociety {
  const YeSheLiterarySociety({
    this.id = 0,
    this.name = '',
    this.isPublic = false,
    this.inviteCode = '',
    this.level = 0,
    this.exp = 0,
    this.memberLimit = 0,
    this.memberCount = 0,
    this.weekScore = 0,
    this.presidentUserId = 0,
    this.members = const <YeSheSocietyMember>[],
    this.rewardStatus = '',
    this.claimedRewardName = '',
    this.coverUrl = '',
  });

  factory YeSheLiterarySociety.fromJson(Map<String, dynamic> json) {
    return YeSheLiterarySociety(
      id: yeSheInt(json['id']),
      name: yeSheText(json['name']),
      isPublic: yeSheBool(json['isPublic']),
      inviteCode: yeSheText(json['inviteCode']),
      level: yeSheInt(json['level']),
      exp: yeSheInt(json['exp']),
      memberLimit: yeSheInt(json['memberLimit']),
      memberCount: yeSheInt(json['memberCount']),
      weekScore: yeSheInt(json['weekScore']),
      presidentUserId: yeSheInt(json['presidentUserId']),
      members: <YeSheSocietyMember>[
        for (final member in yeSheMapList(json['members']))
          YeSheSocietyMember.fromJson(member),
      ],
      rewardStatus: yeSheText(json['rewardStatus']),
      claimedRewardName: yeSheText(json['claimedRewardName']),
      coverUrl: yeSheText(json['coverUrl']),
    );
  }

  final int id;
  final String name;
  final bool isPublic;
  final String inviteCode;
  final int level;
  final int exp;
  final int memberLimit;
  final int memberCount;
  final int weekScore;
  final int presidentUserId;
  final List<YeSheSocietyMember> members;
  final String rewardStatus;
  final String claimedRewardName;
  final String coverUrl;

  /// 上周文会奖励是否已经领取。
  bool get hasClaimedWeeklyReward {
    final status = rewardStatus.trim().toUpperCase();
    return status == 'CLAIMED' ||
        (status.isEmpty && claimedRewardName.trim().isNotEmpty);
  }

  /// 是否有可领取的文会周奖励。
  bool get canClaimWeeklyReward =>
      !hasClaimedWeeklyReward &&
      rewardStatus.trim().toUpperCase() == 'CLAIMABLE';

  /// 与领取按钮同步的奖励状态文案。
  String get weeklyRewardStatusText {
    if (hasClaimedWeeklyReward) {
      final name = claimedRewardName.trim();
      return name.isEmpty ? '已领取' : '已领取 $name';
    }
    if (canClaimWeeklyReward) return '可领取';
    return '暂无奖励';
  }

  /// 领取周奖励按钮文案；不可领取时用于禁用态说明。
  String get weeklyRewardActionLabel {
    if (hasClaimedWeeklyReward) return '本周已领取';
    if (canClaimWeeklyReward) return '领取周奖励';
    return '暂无可领取奖励';
  }
}

/// 公开文会搜索结果。
class YeSheLiterarySocieties {
  const YeSheLiterarySocieties({
    this.items = const <YeSheLiterarySociety>[],
    this.total = 0,
  });

  factory YeSheLiterarySocieties.fromJson(Map<String, dynamic> json) {
    return YeSheLiterarySocieties(
      items: <YeSheLiterarySociety>[
        for (final item in yeSheMapList(json['items']))
          YeSheLiterarySociety.fromJson(item),
      ],
      total: yeSheInt(json['total']),
    );
  }

  final List<YeSheLiterarySociety> items;
  final int total;
}

/// 文会本周声望排行。
class YeSheLiterarySocietyScores {
  const YeSheLiterarySocietyScores({
    this.weekStart = '',
    this.totalScore = 0,
    this.maxScore = 0,
    this.members = const <YeSheSocietyMember>[],
  });

  factory YeSheLiterarySocietyScores.fromJson(Map<String, dynamic> json) {
    final members = <YeSheSocietyMember>[
      for (final member in yeSheMapList(json['members']))
        YeSheSocietyMember.fromJson(member),
    ]..sort((left, right) => right.weekScore.compareTo(left.weekScore));
    return YeSheLiterarySocietyScores(
      weekStart: yeSheText(json['weekStart']),
      totalScore: yeSheInt(json['totalScore']),
      maxScore: yeSheInt(json['maxScore']),
      members: members,
    );
  }

  final String weekStart;
  final int totalScore;
  final int maxScore;
  final List<YeSheSocietyMember> members;

  /// 当前声望占本周上限的比例。
  double get ratio => maxScore <= 0 ? 0 : (totalScore / maxScore).clamp(0, 1);
}

/// 商会等级权益。
class YeSheGuildLevel {
  const YeSheGuildLevel({
    this.level = 0,
    this.name = '',
    this.contribution = 0,
    this.depositPercent = 0,
    this.profitPercent = 0,
    this.lossPercent = 0,
    this.durationPercent = 0,
  });

  factory YeSheGuildLevel.fromJson(Map<String, dynamic> json) {
    return YeSheGuildLevel(
      level: yeSheInt(json['level']),
      name: yeSheText(json['name']),
      contribution: yeSheInt(json['contribution']),
      depositPercent: yeSheInt(json['depositPercent']),
      profitPercent: yeSheInt(json['profitPercent']),
      lossPercent: yeSheInt(json['lossPercent']),
      durationPercent: yeSheInt(json['durationPercent']),
    );
  }

  final int level;
  final String name;
  final int contribution;
  final int depositPercent;
  final int profitPercent;
  final int lossPercent;
  final int durationPercent;
}

/// 商会。
class YeSheMerchantGuild {
  const YeSheMerchantGuild({
    this.id = 0,
    this.code = '',
    this.name = '',
    this.balance = 0,
    this.memberCount = 0,
  });

  factory YeSheMerchantGuild.fromJson(Map<String, dynamic> json) {
    return YeSheMerchantGuild(
      id: yeSheInt(json['id']),
      code: yeSheText(json['code']),
      name: yeSheText(json['name']),
      balance: yeSheInt(json['balance']),
      memberCount: yeSheInt(json['memberCount']),
    );
  }

  final int id;
  final String code;
  final String name;
  final int balance;
  final int memberCount;
}

/// 当前商会成员身份。
class YeSheGuildMembership {
  const YeSheGuildMembership({
    this.guildId = 0,
    this.contribution = 0,
    this.level = 0,
  });

  factory YeSheGuildMembership.fromJson(Map<String, dynamic> json) {
    return YeSheGuildMembership(
      guildId: yeSheInt(json['guildId']),
      contribution: yeSheInt(json['contribution']),
      level: yeSheInt(json['level']),
    );
  }

  final int guildId;
  final int contribution;
  final int level;

  bool get joined => guildId > 0;
}

/// 商会列表。
class YeSheMerchantGuilds {
  const YeSheMerchantGuilds({
    this.guilds = const <YeSheMerchantGuild>[],
    this.levels = const <YeSheGuildLevel>[],
    this.membership,
    this.joinCost = 0,
  });

  factory YeSheMerchantGuilds.fromJson(Map<String, dynamic> json) {
    final rawMembership = json['membership'];
    return YeSheMerchantGuilds(
      guilds: <YeSheMerchantGuild>[
        for (final item in yeSheMapList(json['guilds']))
          YeSheMerchantGuild.fromJson(item),
      ],
      levels: <YeSheGuildLevel>[
        for (final item in yeSheMapList(json['levels']))
          YeSheGuildLevel.fromJson(item),
      ],
      membership: rawMembership is Map
          ? YeSheGuildMembership.fromJson(yeSheMap(rawMembership))
          : null,
      joinCost: yeSheInt(json['joinCost']),
    );
  }

  final List<YeSheMerchantGuild> guilds;
  final List<YeSheGuildLevel> levels;
  final YeSheGuildMembership? membership;
  final int joinCost;
}

/// 商会拍卖。
class YeSheGuildAuction {
  const YeSheGuildAuction({
    this.id = 0,
    this.guildId = 0,
    this.auctionDate = '',
    this.phase = '',
    this.itemKind = '',
    this.itemId = 0,
    this.itemName = '',
    this.itemDescription = '',
    this.itemQuality = '',
    this.startingPrice = 0,
    this.highestBid = 0,
    this.minimumBid = 0,
    this.startTime,
    this.endTime,
    this.serverTime,
    this.nextChangeTime,
    this.isLeading = false,
    this.frozenCoin = 0,
    this.canBid = false,
    this.unavailableReason = '',
    this.result = '',
    this.winnerUserId = 0,
    this.winnerName = '',
    this.bidCount = 0,
    this.bidEligibleTime,
    this.coin = 0,
  });

  factory YeSheGuildAuction.fromJson(Map<String, dynamic> json) {
    final auction = json['auction'] is Map
        ? yeSheMap(json['auction'])
        : const <String, dynamic>{};
    return YeSheGuildAuction(
      id: yeSheInt(auction['id']),
      guildId: yeSheInt(auction['guildId']),
      auctionDate: yeSheText(auction['auctionDate']),
      phase: yeSheText(auction['phase']),
      itemKind: yeSheText(auction['itemKind']),
      itemId: yeSheInt(auction['itemId']),
      itemName: yeSheText(auction['itemName']),
      itemDescription: yeSheText(auction['itemDescription']),
      itemQuality: yeSheText(auction['itemQuality']),
      startingPrice: yeSheInt(auction['startingPrice']),
      highestBid: yeSheInt(auction['highestBid']),
      minimumBid: yeSheInt(auction['minimumBid']),
      startTime: yeSheTime(auction['startTime']),
      endTime: yeSheTime(auction['endTime']),
      serverTime: yeSheTime(auction['serverTime']),
      nextChangeTime: yeSheTime(auction['nextChangeTime']),
      isLeading: yeSheBool(auction['isLeading']),
      frozenCoin: yeSheInt(auction['frozenCoin']),
      canBid: yeSheBool(auction['canBid']),
      unavailableReason: yeSheText(auction['unavailableReason']),
      result: yeSheText(auction['result']),
      winnerUserId: yeSheInt(auction['winnerUserId']),
      winnerName: yeSheText(auction['winnerName']),
      bidCount: yeSheInt(auction['bidCount']),
      bidEligibleTime: yeSheTime(auction['bidEligibleTime']),
      coin: yeSheInt(json['coin']),
    );
  }

  final int id;
  final int guildId;
  final String auctionDate;
  final String phase;
  final String itemKind;
  final int itemId;
  final String itemName;
  final String itemDescription;
  final String itemQuality;
  final int startingPrice;
  final int highestBid;
  final int minimumBid;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? serverTime;
  final DateTime? nextChangeTime;
  final bool isLeading;
  final int frozenCoin;
  final bool canBid;
  final String unavailableReason;
  final String result;
  final int winnerUserId;
  final String winnerName;
  final int bidCount;
  final DateTime? bidEligibleTime;
  final int coin;

  bool get hasAuction => id > 0 && itemName.trim().isNotEmpty;
}

/// 商会成员。
class YeSheGuildMember {
  const YeSheGuildMember({
    this.userId = 0,
    this.nickName = '',
    this.avatar = '',
    this.contribution = 0,
    this.level = 0,
    this.levelName = '',
  });

  factory YeSheGuildMember.fromJson(Map<String, dynamic> json) {
    return YeSheGuildMember(
      userId: yeSheInt(json['userId']),
      nickName: yeSheText(json['nickName']),
      avatar: yeSheText(json['avatar']),
      contribution: yeSheInt(json['contribution']),
      level: yeSheInt(json['level']),
      levelName: yeSheText(json['levelName']),
    );
  }

  final int userId;
  final String nickName;
  final String avatar;
  final int contribution;
  final int level;
  final String levelName;
}

/// 商会行商动态。
class YeSheGuildHistoryEntry {
  const YeSheGuildHistoryEntry({
    this.userId = 0,
    this.nickName = '',
    this.trip = '',
    this.avatar = '',
  });

  factory YeSheGuildHistoryEntry.fromJson(Map<String, dynamic> json) {
    return YeSheGuildHistoryEntry(
      userId: yeSheInt(json['userId']),
      nickName: yeSheText(json['nickName']),
      trip: yeSheText(json['trip']),
      avatar: yeSheText(json['avatar']),
    );
  }

  final int userId;
  final String nickName;
  final String trip;
  final String avatar;
}

/// 每日轶闻。
class YeSheDailyLore {
  const YeSheDailyLore({
    this.id = 0,
    this.loreId = '',
    this.title = '',
    this.content = '',
    this.category = '',
    this.type = '',
    this.quality = '',
    this.level = 0,
    this.exp = 0,
    this.gem = 0,
    this.propId = '',
    this.propName = '',
    this.propQuality = '',
    this.startTime,
    this.endTime,
    this.completeTime,
    this.claimed = false,
    this.isFinish = false,
  });

  factory YeSheDailyLore.fromJson(Map<String, dynamic> json) {
    return YeSheDailyLore(
      id: yeSheInt(json['id']),
      loreId: yeSheText(json['loreId']),
      title: yeSheText(json['title']),
      content: yeSheText(json['content']),
      category: yeSheText(json['category']),
      type: yeSheText(json['type']),
      quality: yeSheText(json['quality']),
      level: yeSheInt(json['level']),
      exp: yeSheInt(json['exp']),
      gem: yeSheInt(json['gem']),
      propId: yeSheText(json['propId']),
      propName: yeSheText(json['propName']),
      propQuality: yeSheText(json['propQuality']),
      startTime: yeSheTime(json['startTime']),
      endTime: yeSheTime(json['endTime']),
      completeTime: yeSheTime(json['completeTime']),
      claimed: yeSheBool(json['claimed']),
      isFinish: yeSheBool(json['isFinish']),
    );
  }

  final int id;
  final String loreId;
  final String title;
  final String content;
  final String category;
  final String type;
  final String quality;
  final int level;
  final int exp;
  final int gem;
  final String propId;
  final String propName;
  final String propQuality;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? completeTime;
  final bool claimed;
  final bool isFinish;
}

/// 樗蒲。
class YeSheGambling {
  const YeSheGambling({
    this.id = 0,
    this.name = '',
    this.prize = '',
    this.people = 0,
    this.first = '',
    this.second = '',
    this.third = '',
    this.betStartTime,
    this.betEndTime,
    this.startTime,
    this.endTime,
    this.rewardStatus = '',
    this.canBet = false,
    this.myScore = 0,
    this.myDice = '',
    this.isEnded = false,
    this.canClaim = false,
    this.usedCount = 0,
    this.maxCount = 0,
    this.remainingCount = 0,
  });

  factory YeSheGambling.fromJson(Map<String, dynamic> json) {
    return YeSheGambling(
      id: yeSheInt(json['id']),
      name: yeSheText(json['name']),
      prize: yeSheText(json['prize']),
      people: yeSheInt(json['people']),
      first: yeSheText(json['first']),
      second: yeSheText(json['second']),
      third: yeSheText(json['third']),
      betStartTime: yeSheTime(json['betStartTime']),
      betEndTime: yeSheTime(json['betEndTime']),
      startTime: yeSheTime(json['startTime']),
      endTime: yeSheTime(json['endTime']),
      rewardStatus: yeSheText(json['rewardStatus']),
      canBet: yeSheBool(json['canBet']),
      myScore: yeSheInt(json['myScore']),
      myDice: yeSheText(json['myDice']),
      isEnded: yeSheBool(json['isEnded']),
      canClaim: yeSheBool(json['canClaim']),
      usedCount: yeSheInt(json['usedCount']),
      maxCount: yeSheInt(json['maxCount']),
      remainingCount: yeSheInt(json['remainingCount']),
    );
  }

  final int id;
  final String name;
  final String prize;
  final int people;
  final String first;
  final String second;
  final String third;
  final DateTime? betStartTime;
  final DateTime? betEndTime;
  final DateTime? startTime;
  final DateTime? endTime;
  final String rewardStatus;
  final bool canBet;
  final int myScore;
  final String myDice;
  final bool isEnded;
  final bool canClaim;
  final int usedCount;
  final int maxCount;
  final int remainingCount;
}

/// 聚宝楼拍品。
class YeSheAuction {
  const YeSheAuction({
    this.id = 0,
    this.objectId = '',
    this.objectName = '',
    this.category = '',
    this.appraisal = '',
    this.condition = '',
    this.material = '',
    this.aura = '',
    this.highestBid = 0,
    this.highestBidUserId = 0,
    this.myBid = 0,
    this.startTime,
    this.endTime,
    this.status = '',
    this.canBid = false,
    this.actualPrice = 0,
    this.winnerUserId = 0,
    this.highestBidNickName = '',
    this.highestBidAvatar = '',
  });

  factory YeSheAuction.fromJson(Map<String, dynamic> json) {
    return YeSheAuction(
      id: yeSheInt(json['id']),
      objectId: yeSheText(json['objectId']),
      objectName: yeSheText(json['objectName']),
      category: yeSheText(json['category']),
      appraisal: yeSheText(json['appraisal']),
      condition: yeSheText(json['condition']),
      material: yeSheText(json['material']),
      aura: yeSheText(json['aura']),
      highestBid: yeSheInt(json['highestBid']),
      highestBidUserId: yeSheInt(json['highestBidUserId']),
      myBid: yeSheInt(json['myBid']),
      startTime: yeSheTime(json['startTime']),
      endTime: yeSheTime(json['endTime']),
      status: yeSheText(json['status']),
      canBid: yeSheBool(json['canBid']),
      actualPrice: yeSheInt(json['actualPrice']),
      winnerUserId: yeSheInt(json['winnerUserId']),
      highestBidNickName: yeSheText(json['highestBidNickName']),
      highestBidAvatar: yeSheText(json['highestBidAvatar']),
    );
  }

  final int id;
  final String objectId;
  final String objectName;
  final String category;
  final String appraisal;
  final String condition;
  final String material;
  final String aura;
  final int highestBid;
  final int highestBidUserId;
  final int myBid;
  final DateTime? startTime;
  final DateTime? endTime;
  final String status;
  final bool canBid;
  final int actualPrice;
  final int winnerUserId;
  final String highestBidNickName;
  final String highestBidAvatar;
}

/// 祈愿提升。
class YeSheWishUp {
  const YeSheWishUp({
    this.propId = '',
    this.propName = '',
    this.weekStart = '',
    this.description = '',
  });

  factory YeSheWishUp.fromJson(Map<String, dynamic> json) {
    return YeSheWishUp(
      propId: yeSheText(json['propId']),
      propName: yeSheText(json['propName']),
      weekStart: yeSheText(json['weekStart']),
      description: yeSheText(json['description']),
    );
  }

  final String propId;
  final String propName;
  final String weekStart;
  final String description;
}

/// 道观祈福状态。
class YeSheTaoistBlessing {
  const YeSheTaoistBlessing({
    this.blessing,
    this.freePrayAvailable = false,
    this.todayPrayCount = 0,
  });

  factory YeSheTaoistBlessing.fromJson(Map<String, dynamic> json) {
    return YeSheTaoistBlessing(
      blessing: json['blessing'] is Map ? yeSheMap(json['blessing']) : null,
      freePrayAvailable: yeSheBool(json['freePrayAvailable']),
      todayPrayCount: yeSheInt(json['todayPrayCount']),
    );
  }

  final Map<String, dynamic>? blessing;
  final bool freePrayAvailable;
  final int todayPrayCount;

  String get blessingName {
    final value = blessing;
    if (value == null) return '';
    return yeSheText(
      value['name'] ?? value['blessingName'] ?? value['label'] ?? value['type'],
    );
  }

  String get blessingDescription {
    final value = blessing;
    if (value == null) return '';
    return yeSheText(
      value['description'] ??
          value['effectDescription'] ??
          value['effect'] ??
          value['value'],
    );
  }
}

/// 今日典当次数。
class YeShePawnCount {
  const YeShePawnCount({
    this.usedToday = 0,
    this.maxPerDay = 0,
    this.remaining = 0,
    this.isVip = false,
    this.specialPropId = '',
    this.specialPropName = '',
    this.specialPropQuality = '',
  });

  factory YeShePawnCount.fromJson(Map<String, dynamic> json) {
    return YeShePawnCount(
      usedToday: yeSheInt(json['usedToday']),
      maxPerDay: yeSheInt(json['maxPerDay']),
      remaining: yeSheInt(json['remaining']),
      isVip: yeSheBool(json['isVip']),
      specialPropId: yeSheText(json['specialPropId']),
      specialPropName: yeSheText(json['specialPropName']),
      specialPropQuality: yeSheText(json['specialPropQuality']),
    );
  }

  final int usedToday;
  final int maxPerDay;
  final int remaining;
  final bool isVip;
  final String specialPropId;
  final String specialPropName;
  final String specialPropQuality;
}

/// 可典当材料。
class YeSheMaterial {
  const YeSheMaterial({
    this.userPropId = 0,
    this.propId = 0,
    this.name = '',
    this.quality = '',
    this.quantity = 0,
  });

  factory YeSheMaterial.fromJson(Map<String, dynamic> json) {
    return YeSheMaterial(
      userPropId: yeSheInt(json['userPropId']),
      propId: yeSheInt(json['propId']),
      name: yeSheText(json['name']),
      quality: yeSheText(json['quality']),
      quantity: yeSheInt(json['quantity']),
    );
  }

  final int userPropId;
  final int propId;
  final String name;
  final String quality;
  final int quantity;
}

/// 商店物品。
class YeSheShopItem {
  const YeSheShopItem({
    this.propId = 0,
    this.name = '',
    this.quality = '',
    this.type = '',
    this.price = 0,
    this.purchased = false,
  });

  factory YeSheShopItem.fromJson(Map<String, dynamic> json) {
    return YeSheShopItem(
      propId: yeSheInt(json['propId']),
      name: yeSheText(json['name']),
      quality: yeSheText(json['quality']),
      type: yeSheText(json['type']),
      price: yeSheInt(json['price']),
      purchased: yeSheBool(json['purchased']),
    );
  }

  final int propId;
  final String name;
  final String quality;
  final String type;
  final int price;
  final bool purchased;
}

/// 百杂铺。
class YeSheDailyShop {
  const YeSheDailyShop({
    this.items = const <YeSheShopItem>[],
    this.coin = 0,
    this.refreshPropQuantity = 0,
    this.refreshCount = 0,
  });

  factory YeSheDailyShop.fromJson(Map<String, dynamic> json) {
    return YeSheDailyShop(
      items: <YeSheShopItem>[
        for (final item in yeSheMapList(json['items']))
          YeSheShopItem.fromJson(item),
      ],
      coin: yeSheInt(json['coin']),
      refreshPropQuantity: yeSheInt(json['refreshPropQuantity']),
      refreshCount: yeSheInt(json['refreshCount']),
    );
  }

  final List<YeSheShopItem> items;
  final int coin;
  final int refreshPropQuantity;
  final int refreshCount;
}

/// 玉机阁。
class YeSheVoucherShop {
  const YeSheVoucherShop({this.items = const <YeSheShopItem>[]});

  factory YeSheVoucherShop.fromJson(Map<String, dynamic> json) {
    return YeSheVoucherShop(
      items: <YeSheShopItem>[
        for (final item in yeSheMapList(json['items']))
          YeSheShopItem.fromJson(item),
      ],
    );
  }

  final List<YeSheShopItem> items;
}

/// 互市坊可交易物品。
class YeSheMarketProp {
  const YeSheMarketProp({
    this.propId = 0,
    this.name = '',
    this.quality = '',
    this.ownedQuantity = 0,
    this.referencePrice = 0,
    this.minPrice = 0,
    this.maxPrice = 0,
    this.dynamicPriceEnabled = false,
  });

  factory YeSheMarketProp.fromJson(Map<String, dynamic> json) {
    return YeSheMarketProp(
      propId: yeSheInt(json['propId']),
      name: yeSheText(json['name']),
      quality: yeSheText(json['quality']),
      ownedQuantity: yeSheInt(json['ownedQuantity']),
      referencePrice: yeSheInt(json['referencePrice']),
      minPrice: yeSheInt(json['minPrice']),
      maxPrice: yeSheInt(json['maxPrice']),
      dynamicPriceEnabled: yeSheBool(json['dynamicPriceEnabled']),
    );
  }

  final int propId;
  final String name;
  final String quality;
  final int ownedQuantity;
  final int referencePrice;
  final int minPrice;
  final int maxPrice;
  final bool dynamicPriceEnabled;
}

/// 互市坊挂单。
class YeSheMarketListing {
  const YeSheMarketListing({
    this.id = 0,
    this.sellerUserId = 0,
    this.sellerName = '',
    this.propId = 0,
    this.propName = '',
    this.propQuality = '',
    this.unitPrice = 0,
    this.remainingQuantity = 0,
    this.soldQuantity = 0,
    this.status = '',
    this.expiresAt,
    this.mine = false,
  });

  factory YeSheMarketListing.fromJson(Map<String, dynamic> json) {
    return YeSheMarketListing(
      id: yeSheInt(json['id']),
      sellerUserId: yeSheInt(json['sellerUserId']),
      sellerName: yeSheText(json['sellerName']),
      propId: yeSheInt(json['propId']),
      propName: yeSheText(json['propName']),
      propQuality: yeSheText(json['propQuality']),
      unitPrice: yeSheInt(json['unitPrice']),
      remainingQuantity: yeSheInt(json['remainingQuantity']),
      soldQuantity: yeSheInt(json['soldQuantity']),
      status: yeSheText(json['status']),
      expiresAt: yeSheTime(json['expiresAt']),
      mine: yeSheBool(json['mine']),
    );
  }

  final int id;
  final int sellerUserId;
  final String sellerName;
  final int propId;
  final String propName;
  final String propQuality;
  final int unitPrice;
  final int remainingQuantity;
  final int soldQuantity;
  final String status;
  final DateTime? expiresAt;
  final bool mine;
}

/// 互市坊。
class YeSheMutualMarket {
  const YeSheMutualMarket({
    this.props = const <YeSheMarketProp>[],
    this.listings = const <YeSheMarketListing>[],
    this.myListings = const <YeSheMarketListing>[],
    this.coin = 0,
    this.soldHistory = const <Map<String, dynamic>>[],
  });

  factory YeSheMutualMarket.fromJson(Map<String, dynamic> json) {
    return YeSheMutualMarket(
      props: <YeSheMarketProp>[
        for (final item in yeSheMapList(json['props']))
          YeSheMarketProp.fromJson(item),
      ],
      listings: <YeSheMarketListing>[
        for (final item in yeSheMapList(json['listings']))
          YeSheMarketListing.fromJson(item),
      ],
      myListings: <YeSheMarketListing>[
        for (final item in yeSheMapList(json['myListings']))
          YeSheMarketListing.fromJson(item),
      ],
      coin: yeSheInt(json['coin']),
      soldHistory: yeSheMapList(json['soldHistory']),
    );
  }

  final List<YeSheMarketProp> props;
  final List<YeSheMarketListing> listings;
  final List<YeSheMarketListing> myListings;
  final int coin;
  final List<Map<String, dynamic>> soldHistory;
}

/// 行商城市。
class YeSheTravelCity {
  const YeSheTravelCity({
    this.id = 0,
    this.code = '',
    this.name = '',
    this.routeType = '',
    this.baseDurationMinutes = 0,
    this.requiredTransportType = '',
  });

  factory YeSheTravelCity.fromJson(Map<String, dynamic> json) {
    return YeSheTravelCity(
      id: yeSheInt(json['id']),
      code: yeSheText(json['code']),
      name: yeSheText(json['name']),
      routeType: yeSheText(json['routeType']),
      baseDurationMinutes: yeSheInt(json['baseDurationMinutes']),
      requiredTransportType: yeSheText(json['requiredTransportType']),
    );
  }

  final int id;
  final String code;
  final String name;
  final String routeType;
  final int baseDurationMinutes;
  final String requiredTransportType;
}

/// 行商船只。
class YeSheTransport {
  const YeSheTransport({
    this.id = 0,
    this.code = '',
    this.name = '',
    this.transportType = '',
    this.speedPercent = 0,
    this.carryingCapacity = 0,
    this.traitCode = '',
    this.traitName = '',
    this.owned = false,
  });

  factory YeSheTransport.fromJson(Map<String, dynamic> json) {
    return YeSheTransport(
      id: yeSheInt(json['id']),
      code: yeSheText(json['code']),
      name: yeSheText(json['name']),
      transportType: yeSheText(json['transportType']),
      speedPercent: yeSheInt(json['speedPercent']),
      carryingCapacity: yeSheInt(json['carryingCapacity']),
      traitCode: yeSheText(json['traitCode']),
      traitName: yeSheText(json['traitName']),
      owned: yeSheBool(json['owned']),
    );
  }

  final int id;
  final String code;
  final String name;
  final String transportType;
  final int speedPercent;
  final int carryingCapacity;
  final String traitCode;
  final String traitName;
  final bool owned;
}

/// 行商宝物。
class YeSheTreasure {
  const YeSheTreasure({
    this.id = 0,
    this.code = '',
    this.name = '',
    this.effectType = '',
    this.effectValue = 0,
    this.rare = '',
    this.owned = false,
  });

  factory YeSheTreasure.fromJson(Map<String, dynamic> json) {
    return YeSheTreasure(
      id: yeSheInt(json['id']),
      code: yeSheText(json['code']),
      name: yeSheText(json['name']),
      effectType: yeSheText(json['effectType']),
      effectValue: yeSheInt(json['effectValue']),
      rare: yeSheText(json['rare']),
      owned: yeSheBool(json['owned']),
    );
  }

  final int id;
  final String code;
  final String name;
  final String effectType;
  final int effectValue;
  final String rare;
  final bool owned;
}

/// 行商行程。
class YeSheTravelTrip {
  const YeSheTravelTrip({
    this.id = 0,
    this.cityCode = '',
    this.transportId = 0,
    this.principal = 0,
    this.plannedDurationMinutes = 0,
    this.totalDurationMinutes = 0,
    this.status = '',
    this.startTime,
    this.endTime,
    this.eventType = '',
    this.eventTitle = '',
    this.eventContent = '',
    this.profitPercent = 0,
    this.settlementAmount = 0,
    this.rewardTransportId = 0,
    this.rewardTreasure = '',
    this.blessingName = '',
    this.blessingEffectType = '',
    this.blessingEffectValue = 0,
    this.eventSubTypeCode = '',
    this.eventSubTypeName = '',
    this.guildBonus = 0,
  });

  factory YeSheTravelTrip.fromJson(Map<String, dynamic> json) {
    return YeSheTravelTrip(
      id: yeSheInt(json['id']),
      cityCode: yeSheText(json['cityCode']),
      transportId: yeSheInt(json['transportId']),
      principal: yeSheInt(json['principal']),
      plannedDurationMinutes: yeSheInt(json['plannedDurationMinutes']),
      totalDurationMinutes: yeSheInt(json['totalDurationMinutes']),
      status: yeSheText(json['status']),
      startTime: yeSheTime(json['startTime']),
      endTime: yeSheTime(json['endTime']),
      eventType: yeSheText(json['eventType']),
      eventTitle: yeSheText(json['eventTitle']),
      eventContent: yeSheText(json['eventContent']),
      profitPercent: yeSheDouble(json['profitPercent']),
      settlementAmount: yeSheInt(json['settlementAmount']),
      rewardTransportId: yeSheInt(json['rewardTransportId']),
      rewardTreasure: yeSheText(json['rewardTreasure']),
      blessingName: yeSheText(json['blessingName']),
      blessingEffectType: yeSheText(json['blessingEffectType']),
      blessingEffectValue: yeSheInt(json['blessingEffectValue']),
      eventSubTypeCode: yeSheText(json['eventSubTypeCode']),
      eventSubTypeName: yeSheText(json['eventSubTypeName']),
      guildBonus: yeSheInt(json['guildBonus']),
    );
  }

  final int id;
  final String cityCode;
  final int transportId;
  final int principal;
  final int plannedDurationMinutes;
  final int totalDurationMinutes;
  final String status;
  final DateTime? startTime;
  final DateTime? endTime;
  final String eventType;
  final String eventTitle;
  final String eventContent;
  final double profitPercent;
  final int settlementAmount;
  final int rewardTransportId;
  final String rewardTreasure;
  final String blessingName;
  final String blessingEffectType;
  final int blessingEffectValue;
  final String eventSubTypeCode;
  final String eventSubTypeName;
  final int guildBonus;

  /// 服务端已完成行程结算。
  bool get isSettled => status.trim().toUpperCase() == 'SETTLED';

  /// 当前是否有尚未结算的进行中行程。
  bool get inProgress => !isSettled;

  /// 是否允许调用结算接口；与阅微一致，仅 SETTLED 行程可以结算。
  bool get canSettle => isSettled;

  /// 按起止时间计算行程进度，缺失时间时视为尚未出发。
  double progressAt(DateTime now) {
    final start = startTime;
    final end = endTime;
    if (start == null || end == null) return isSettled ? 1 : 0;
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return now.isBefore(end) ? 0 : 1;
    final elapsed = now.difference(start).inMilliseconds / total;
    return elapsed.clamp(0.0, 1.0);
  }

  /// 阅微原生行商阶段：路途中、已抵达、归途中、已返回。
  String stageAt(DateTime now) {
    if (isSettled) return '已返回';
    final progress = progressAt(now);
    if (progress <= 0.5) return '路途中';
    if (progress < 0.6) return '已抵达';
    return '归途中';
  }
}

/// 行商总状态。
class YeSheTravelingMerchant {
  const YeSheTravelingMerchant({
    this.cities = const <YeSheTravelCity>[],
    this.transports = const <YeSheTransport>[],
    this.activeTrip,
    this.noTransportCapacity = '',
    this.treasures = const <YeSheTreasure>[],
  });

  factory YeSheTravelingMerchant.fromJson(Map<String, dynamic> json) {
    final rawTrip = json['activeTrip'];
    return YeSheTravelingMerchant(
      cities: <YeSheTravelCity>[
        for (final item in yeSheMapList(json['cities']))
          YeSheTravelCity.fromJson(item),
      ],
      transports: <YeSheTransport>[
        for (final item in yeSheMapList(json['transports']))
          YeSheTransport.fromJson(item),
      ],
      activeTrip: rawTrip is Map
          ? YeSheTravelTrip.fromJson(yeSheMap(rawTrip))
          : null,
      noTransportCapacity: yeSheText(json['noTransportCapacity']),
      treasures: <YeSheTreasure>[
        for (final item in yeSheMapList(json['treasures']))
          YeSheTreasure.fromJson(item),
      ],
    );
  }

  final List<YeSheTravelCity> cities;
  final List<YeSheTransport> transports;
  final YeSheTravelTrip? activeTrip;
  final String noTransportCapacity;
  final List<YeSheTreasure> treasures;
}

/// 行商门客。
class YeSheRetainer {
  const YeSheRetainer({
    this.id = 0,
    this.code = '',
    this.surname = '',
    this.givenName = '',
    this.courtesyName = '',
    this.description = '',
    this.cityCode = '',
    this.eventType = '',
    this.subTypeCode = '',
    this.effectType = '',
    this.effectValue = 0,
    this.quality = '',
    this.duplicateCount = 0,
    this.owned = false,
    this.cityName = '',
    this.effectDescription = '',
  });

  factory YeSheRetainer.fromJson(Map<String, dynamic> json) {
    return YeSheRetainer(
      id: yeSheInt(json['id']),
      code: yeSheText(json['code']),
      surname: yeSheText(json['surname']),
      givenName: yeSheText(json['givenName']),
      courtesyName: yeSheText(json['courtesyName']),
      description: yeSheText(json['description']),
      cityCode: yeSheText(json['cityCode']),
      eventType: yeSheText(json['eventType']),
      subTypeCode: yeSheText(json['subTypeCode']),
      effectType: yeSheText(json['effectType']),
      effectValue: yeSheInt(json['effectValue']),
      quality: yeSheText(json['quality']),
      duplicateCount: yeSheInt(json['duplicateCount']),
      owned: yeSheBool(json['owned']),
      cityName: yeSheText(json['cityName']),
      effectDescription: yeSheText(json['effectDescription']),
    );
  }

  final int id;
  final String code;
  final String surname;
  final String givenName;
  final String courtesyName;
  final String description;
  final String cityCode;
  final String eventType;
  final String subTypeCode;
  final String effectType;
  final int effectValue;
  final String quality;
  final int duplicateCount;
  final bool owned;
  final String cityName;
  final String effectDescription;

  String get displayName {
    final name = '$surname$givenName'.trim();
    if (name.isNotEmpty) return name;
    return courtesyName.trim().isEmpty ? code : courtesyName;
  }
}

/// 门客名册。
class YeSheRetainers {
  const YeSheRetainers({
    this.items = const <YeSheRetainer>[],
    this.qinggui = 0,
    this.pityCount = 0,
  });

  factory YeSheRetainers.fromJson(Map<String, dynamic> json) {
    return YeSheRetainers(
      items: <YeSheRetainer>[
        for (final item in yeSheMapList(json['retainers']))
          YeSheRetainer.fromJson(item),
      ],
      qinggui: yeSheInt(json['qinggui']),
      pityCount: yeSheInt(json['pityCount']),
    );
  }

  final List<YeSheRetainer> items;
  final int qinggui;
  final int pityCount;

  List<YeSheRetainer> get owned => <YeSheRetainer>[
    for (final item in items)
      if (item.owned) item,
  ];
}

/// 唱经楼传闻。
class YeSheRumor {
  const YeSheRumor({
    this.id = 0,
    this.userId = 0,
    this.nickName = '',
    this.avatar = '',
    this.type = '',
    this.content = '',
    this.createTime,
  });

  factory YeSheRumor.fromJson(Map<String, dynamic> json) {
    return YeSheRumor(
      id: yeSheInt(json['id']),
      userId: yeSheInt(json['userId']),
      nickName: yeSheText(json['nickName']),
      avatar: yeSheText(json['avatar']),
      type: yeSheText(json['type']),
      content: yeSheText(json['content']),
      createTime: yeSheTime(json['createTime']),
    );
  }

  final int id;
  final int userId;
  final String nickName;
  final String avatar;
  final String type;
  final String content;
  final DateTime? createTime;
}

/// 公开读书想法。
class YeSheThought {
  const YeSheThought({
    this.id = 0,
    this.userId = 0,
    this.bookId = '',
    this.bookName = '',
    this.bookAuthor = '',
    this.bookCover = '',
    this.chapter = '',
    this.kind = '',
    this.chapterIndex = 0,
    this.startCfi = '',
    this.endCfi = '',
    this.quote = '',
    this.note = '',
    this.style = '',
    this.color = '',
    this.synced = false,
    this.createdAt,
    this.updatedAt,
    this.userName = '',
    this.userAvatar = '',
    this.userLevel = 0,
    this.title = '',
    this.titleLevel = 0,
  });

  factory YeSheThought.fromJson(Map<String, dynamic> json) {
    return YeSheThought(
      id: yeSheInt(json['id']),
      userId: yeSheInt(json['userId']),
      bookId: yeSheText(json['bookId']),
      bookName: yeSheText(json['bookName']),
      bookAuthor: yeSheText(json['bookAuthor']),
      bookCover: yeSheText(json['bookCover']),
      chapter: yeSheText(json['chapter']),
      kind: yeSheText(json['kind']),
      chapterIndex: yeSheInt(json['chapterIndex']),
      startCfi: yeSheText(json['startCfi']),
      endCfi: yeSheText(json['endCfi']),
      quote: yeSheText(json['quote']),
      note: yeSheText(json['note']),
      style: yeSheText(json['style']),
      color: yeSheText(json['color']),
      synced: yeSheBool(json['synced']),
      createdAt: yeSheTime(json['createdAt']),
      updatedAt: yeSheTime(json['updatedAt']),
      userName: yeSheText(json['userName']),
      userAvatar: yeSheText(json['userAvatar']),
      userLevel: yeSheInt(json['userLevel']),
      title: yeSheText(json['title']),
      titleLevel: yeSheInt(json['titleLevel']),
    );
  }

  final int id;
  final int userId;
  final String bookId;
  final String bookName;
  final String bookAuthor;
  final String bookCover;
  final String chapter;
  final String kind;
  final int chapterIndex;
  final String startCfi;
  final String endCfi;
  final String quote;
  final String note;
  final String style;
  final String color;
  final bool synced;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String userName;
  final String userAvatar;
  final int userLevel;
  final String title;
  final int titleLevel;

  String get text => note.trim().isNotEmpty ? note : quote;
}

/// 我的收藏。
class YeSheCollectionEntry {
  const YeSheCollectionEntry({
    this.id = 0,
    this.markId = 0,
    this.collectionType = 0,
    this.mark = const <String, dynamic>{},
    this.collectedAt,
    this.collectionName = '',
  });

  factory YeSheCollectionEntry.fromJson(Map<String, dynamic> json) {
    return YeSheCollectionEntry(
      id: yeSheInt(json['id']),
      markId: yeSheInt(json['markId']),
      collectionType: yeSheInt(json['collectionType']),
      mark: json['mark'] is Map
          ? yeSheMap(json['mark'])
          : const <String, dynamic>{},
      collectedAt: yeSheTime(json['collectedAt']),
      collectionName: yeSheText(json['collectionName']),
    );
  }

  final int id;
  final int markId;
  final int collectionType;
  final Map<String, dynamic> mark;
  final DateTime? collectedAt;
  final String collectionName;

  /// 被收藏条目所属书名。
  String get bookName => yeSheText(mark['bookName']);

  /// 被收藏条目的书封。
  String get bookCover => yeSheText(mark['bookCover']);

  /// 被收藏条目的作者昵称。
  String get userName => yeSheText(mark['userName']);

  /// 被收藏条目的作者头像。
  String get userAvatar => yeSheText(mark['userAvatar']);

  String get _note => yeSheText(mark['note']);

  String get _quote => yeSheText(mark['quote']);

  String get summary {
    if (_note.trim().isNotEmpty) return _note;
    if (_quote.trim().isNotEmpty) return _quote;
    return bookName.trim().isEmpty ? '已收藏的想法' : bookName;
  }
}

/// 徽章征集。
class YeSheMedalTreasure {
  const YeSheMedalTreasure({
    this.id = 0,
    this.medalPropId = 0,
    this.medalName = '',
    this.medalQuality = '',
    this.totalCount = 0,
    this.currentCount = 0,
    this.userCount = 0,
    this.status = '',
    this.winnerUserId = 0,
    this.previousWinnerUserId = 0,
    this.previousWinnerNickName = '',
    this.previousWinnerAvatar = '',
  });

  factory YeSheMedalTreasure.fromJson(Map<String, dynamic> json) {
    return YeSheMedalTreasure(
      id: yeSheInt(json['id']),
      medalPropId: yeSheInt(json['medalPropId']),
      medalName: yeSheText(json['medalName']),
      medalQuality: yeSheText(json['medalQuality']),
      totalCount: yeSheInt(json['totalCount']),
      currentCount: yeSheInt(json['currentCount']),
      userCount: yeSheInt(json['userCount']),
      status: yeSheText(json['status']),
      winnerUserId: yeSheInt(json['winnerUserId']),
      previousWinnerUserId: yeSheInt(json['previousWinnerUserId']),
      previousWinnerNickName: yeSheText(json['previousWinnerNickName']),
      previousWinnerAvatar: yeSheText(json['previousWinnerAvatar']),
    );
  }

  final int id;
  final int medalPropId;
  final String medalName;
  final String medalQuality;
  final int totalCount;
  final int currentCount;
  final int userCount;
  final String status;
  final int winnerUserId;
  final int previousWinnerUserId;
  final String previousWinnerNickName;
  final String previousWinnerAvatar;
}

/// 阅微排行榜类型。
enum YeSheRankKind {
  /// 阅读时长榜。
  readDuration('阅读时长'),

  /// 财富榜。
  wealth('财富'),

  /// 聚宝楼拍卖榜。
  auction('聚宝楼'),

  /// 收藏价值榜。
  collectionValue('收藏价值'),

  /// 名帖榜。
  communityTitle('名帖');

  const YeSheRankKind(this.label);

  /// 页面展示名称。
  final String label;
}

/// 排行榜条目。
class YeSheRankEntry {
  const YeSheRankEntry({
    this.rank = 0,
    this.userId = 0,
    this.nickName = '',
    this.avatar = '',
    this.level = 0,
    this.title = '',
    this.titleLevel = 0,
    this.value = 0,
    this.totalProfit = 0,
    this.totalLoss = 0,
    this.totalAmount = 0,
    this.upgradePityCount = 0,
    this.callingCardId,
  });

  factory YeSheRankEntry.fromJson(
    Map<String, dynamic> json,
    YeSheRankKind kind,
  ) {
    return YeSheRankEntry(
      rank: yeSheInt(json['rank']),
      userId: yeSheInt(json['userId']),
      nickName: yeSheText(json['nickName']),
      avatar: yeSheText(json['avatar']),
      level: yeSheInt(json['level']),
      title: yeSheText(json['title']),
      titleLevel: yeSheInt(json['titleLevel']),
      value: _rankValue(json, kind),
      totalProfit: yeSheInt(json['totalProfit']),
      totalLoss: yeSheInt(json['totalLoss']),
      totalAmount: yeSheInt(json['totalAmount']),
      upgradePityCount: yeSheInt(json['upgradePityCount']),
      callingCardId: json['callingCardId'] == null
          ? null
          : yeSheInt(json['callingCardId']),
    );
  }

  final int rank;
  final int userId;
  final String nickName;
  final String avatar;
  final int level;
  final String title;
  final int titleLevel;

  /// 当前榜单的主指标：阅读时长、财富总额、拍卖额、收藏价值或名帖等级。
  final int value;

  final int totalProfit;
  final int totalLoss;
  final int totalAmount;
  final int upgradePityCount;
  final int? callingCardId;
}

/// 当前用户在榜单中的位置。
class YeSheRankMy {
  const YeSheRankMy({
    this.rank = 0,
    this.value = 0,
    this.totalProfit = 0,
    this.totalLoss = 0,
    this.totalAmount = 0,
    this.titleLevel = 0,
    this.upgradePityCount = 0,
  });

  factory YeSheRankMy.fromJson(Map<String, dynamic> json, YeSheRankKind kind) {
    return YeSheRankMy(
      rank: yeSheInt(json['rank']),
      value: _rankValue(json, kind),
      totalProfit: yeSheInt(json['totalProfit']),
      totalLoss: yeSheInt(json['totalLoss']),
      totalAmount: yeSheInt(json['totalAmount']),
      titleLevel: yeSheInt(json['titleLevel']),
      upgradePityCount: yeSheInt(json['upgradePityCount']),
    );
  }

  final int rank;
  final int value;
  final int totalProfit;
  final int totalLoss;
  final int totalAmount;
  final int titleLevel;
  final int upgradePityCount;
}

/// 一类排行榜的完整结果。
class YeSheRankBoard {
  const YeSheRankBoard({
    required this.kind,
    this.rankDate = '',
    this.entries = const <YeSheRankEntry>[],
    this.my = const YeSheRankMy(),
  });

  factory YeSheRankBoard.fromJson(
    Map<String, dynamic> json,
    YeSheRankKind kind,
  ) {
    final rawList = json['list'] ?? json['items'];
    return YeSheRankBoard(
      kind: kind,
      rankDate: yeSheText(json['rankDate']),
      entries: <YeSheRankEntry>[
        for (final item in yeSheMapList(rawList))
          YeSheRankEntry.fromJson(item, kind),
      ],
      my: YeSheRankMy.fromJson(yeSheMap(json['my']), kind),
    );
  }

  final YeSheRankKind kind;
  final String rankDate;
  final List<YeSheRankEntry> entries;
  final YeSheRankMy my;
}

int _rankValue(Map<String, dynamic> json, YeSheRankKind kind) {
  return switch (kind) {
    YeSheRankKind.readDuration => yeSheInt(json['duration']),
    YeSheRankKind.wealth ||
    YeSheRankKind.auction => yeSheInt(json['totalAmount']),
    YeSheRankKind.collectionValue => yeSheInt(json['collectionValue']),
    YeSheRankKind.communityTitle => yeSheInt(json['titleLevel']),
  };
}

/// 一次写操作结果。
class YeSheActionResult {
  const YeSheActionResult({
    required this.success,
    required this.message,
    this.unauthorized = false,
  });

  final bool success;
  final String message;
  final bool unauthorized;
}
