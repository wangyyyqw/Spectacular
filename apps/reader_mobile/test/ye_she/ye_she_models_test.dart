import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/ye_she/ye_she_models.dart';

void main() {
  test('账户与文会数值兼容字符串和缺省字段', () {
    final status = YeSheAccountStatus.fromJson(<String, dynamic>{
      'exp': '120',
      'expMax': 360,
      'level': '2',
      'coin': '3541',
      'gem': '9',
      'voucher': '3',
      'travelingMerchantProfit': '1924',
      'travelingMerchantLoss': '890',
      'auctionProfit': '30',
      'auctionLoss': '8',
    });
    final society = YeSheLiterarySociety.fromJson(<String, dynamic>{
      'id': '7',
      'name': '白玉京',
      'level': '2',
      'memberCount': 6,
      'memberLimit': '6',
      'weekScore': '71',
      'members': <Object?>[
        <String, dynamic>{
          'userId': '11',
          'nickName': '社长',
          'weekScore': '21',
          'isPresident': true,
        },
      ],
    });

    expect(status.exp, 120);
    expect(status.expMax, 360);
    expect(status.level, 2);
    expect(status.travelingMerchantNet, 1034);
    expect(status.auctionNet, 22);
    expect(society.name, '白玉京');
    expect(society.memberCount, 6);
    expect(society.members.single.isPresident, isTrue);
  });

  test('行商嵌套对象、空列表与缺失字段可解析', () {
    final merchant = YeSheTravelingMerchant.fromJson(<String, dynamic>{
      'cities': <Object?>[
        <String, dynamic>{
          'id': '1',
          'code': 'penglai',
          'name': '蓬莱',
          'routeType': '长途商道',
          'baseDurationMinutes': '2880',
          'requiredTransportType': 'boat',
        },
      ],
      'transports': <Object?>[
        <String, dynamic>{
          'id': '9',
          'name': '鸟船',
          'speedPercent': '20',
          'owned': 1,
        },
      ],
      'activeTrip': <String, dynamic>{
        'id': '88',
        'cityCode': 'penglai',
        'transportId': '9',
        'principal': '45',
        'status': 'traveling',
        'profitPercent': '12.5',
      },
      'noTransportCapacity': '',
    });

    expect(merchant.cities.single.name, '蓬莱');
    expect(merchant.transports.single.owned, isTrue);
    expect(merchant.activeTrip?.id, 88);
    expect(merchant.activeTrip?.profitPercent, 12.5);
    expect(merchant.treasures, isEmpty);
  });

  test('公开想法与收藏摘要读取可选内容', () {
    final thought = YeSheThought.fromJson(<String, dynamic>{
      'id': '31',
      'bookName': '北寺浮图灾',
      'chapter': '第二章',
      'quote': '',
      'note': '这段考据很有意思',
      'userName': '阅微读者',
      'updatedAt': '1763380800000',
      'synced': 'true',
    });
    final collection = YeSheCollectionEntry.fromJson(<String, dynamic>{
      'markId': '31',
      'collectionType': '1',
      'mark': <String, dynamic>{'quote': '原文摘录'},
    });

    expect(thought.id, 31);
    expect(thought.text, '这段考据很有意思');
    expect(thought.synced, isTrue);
    expect(thought.updatedAt, isNotNull);
    expect(collection.markId, 31);
    expect(collection.summary, '原文摘录');
  });

  test('文会声望按周贡献排序并解析商会拍卖嵌套对象', () {
    final scores = YeSheLiterarySocietyScores.fromJson(<String, dynamic>{
      'weekStart': '2026-11-16',
      'totalScore': '71',
      'maxScore': '120',
      'members': <Object?>[
        <String, dynamic>{'nickName': '乙', 'weekScore': '20'},
        <String, dynamic>{'nickName': '甲', 'weekScore': '51'},
      ],
    });
    final auction = YeSheGuildAuction.fromJson(<String, dynamic>{
      'coin': '312',
      'auction': <String, dynamic>{
        'id': '9',
        'guildId': '1',
        'phase': 'BIDDING',
        'itemName': '青瓷笔洗',
        'startingPrice': '100',
        'highestBid': '120',
        'minimumBid': '125',
        'isLeading': true,
        'canBid': true,
        'endTime': '1794909600',
      },
    });

    expect(scores.members.first.nickName, '甲');
    expect(scores.ratio, closeTo(71 / 120, 0.001));
    expect(auction.hasAuction, isTrue);
    expect(auction.minimumBid, 125);
    expect(auction.coin, 312);
    expect(auction.isLeading, isTrue);
    expect(auction.endTime, isNotNull);
  });

  test('五类排行榜解析列表、主指标与当前用户排名', () {
    final read = YeSheRankBoard.fromJson(<String, dynamic>{
      'rankDate': '2026-11-17',
      'list': <Object?>[
        <String, dynamic>{
          'rank': '1',
          'userId': '9',
          'nickName': '甲',
          'duration': '3660',
          'title': '青士',
          'titleLevel': '2',
        },
      ],
      'my': <String, dynamic>{'rank': '8', 'duration': '600'},
    }, YeSheRankKind.readDuration);
    final wealth = YeSheRankBoard.fromJson(<String, dynamic>{
      'list': <Object?>[
        <String, dynamic>{
          'rank': 2,
          'nickName': '乙',
          'totalAmount': '900',
          'totalProfit': '1000',
          'totalLoss': '100',
        },
      ],
      'my': <String, dynamic>{'rank': 3, 'totalAmount': '700'},
    }, YeSheRankKind.wealth);
    final title = YeSheRankBoard.fromJson(<String, dynamic>{
      'list': <Object?>[
        <String, dynamic>{'rank': 1, 'nickName': '丙', 'titleLevel': 5},
      ],
      'my': <String, dynamic>{'rank': 0, 'titleLevel': 2},
    }, YeSheRankKind.communityTitle);

    expect(read.rankDate, '2026-11-17');
    expect(read.entries.single.nickName, '甲');
    expect(read.entries.single.value, 3660);
    expect(read.my.rank, 8);
    expect(read.my.value, 600);
    expect(wealth.entries.single.value, 900);
    expect(wealth.entries.single.totalProfit, 1000);
    expect(wealth.my.value, 700);
    expect(title.entries.single.value, 5);
    expect(title.my.rank, 0);
  });
}
