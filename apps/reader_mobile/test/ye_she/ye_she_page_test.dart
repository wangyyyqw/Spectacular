import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/ye_she/ye_she_api_client.dart';
import 'package:reader_mobile/ye_she/ye_she_controller.dart';
import 'package:reader_mobile/ye_she/ye_she_page.dart';

void main() {
  testWidgets('野社展示三个页签与关键卡片', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = YeSheController(
      tokenProvider: () => 'token',
      api: _DemoYeSheApi(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: YeShePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('文房'), findsWidgets);
    expect(find.text('游艺'), findsOneWidget);
    expect(find.text('见闻'), findsOneWidget);
    expect(find.text('白玉京'), findsOneWidget);
    expect(find.text('青士'), findsOneWidget);
    expect(find.text('名帖'), findsWidgets);
    expect(find.text('本周文会声望 71/120'), findsOneWidget);
    expect(find.text('商会拍卖 · 青瓷笔洗'), findsOneWidget);

    await tester.tap(find.text('游艺'));
    await tester.pumpAndSettle();
    expect(find.text('萃野纂闻《北寺浮图灾》'), findsOneWidget);
    expect(find.text('蓬莱 · 路途中'), findsOneWidget);
    expect(find.text('青瓷笔洗'), findsOneWidget);

    await tester.tap(find.text('见闻'));
    await tester.pumpAndSettle();
    expect(find.text('祈愿 · 鹿鸣印'), findsOneWidget);
    expect(find.text('期物司'), findsOneWidget);
    expect(find.text('百杂铺'), findsOneWidget);
    expect(find.text('运'), findsOneWidget);
    expect(find.text('安'), findsOneWidget);
    expect(find.text('财'), findsOneWidget);
  });

  testWidgets('野社在窄屏下不产生布局溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = YeSheController(
      tokenProvider: () => 'token',
      api: _DemoYeSheApi(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: YeShePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('文房'), findsWidgets);
    await tester.tap(find.text('见闻'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('收藏者'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('收藏者'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _DemoYeSheApi implements YeSheApi {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchCommunityStatus) {
      return _value(<String, dynamic>{
        'exp': '120',
        'expMax': '360',
        'level': 2,
        'coin': '3541',
        'gem': '9',
        'voucher': '3',
        'travelingMerchantProfit': '1924',
        'travelingMerchantLoss': '890',
      });
    }
    if (invocation.memberName == #fetchCommunityTitle) {
      return _value(<String, dynamic>{
        'title': '青士',
        'titleLevel': 2,
        'sourceName': '藏印',
      });
    }
    if (invocation.memberName == #fetchUserSeals) {
      return _value(<String, dynamic>{
        'seals': <Object?>[
          <String, dynamic>{'id': 1, 'name': '麒麟印'},
        ],
        'inkPasteQuantity': '42',
      });
    }
    if (invocation.memberName == #fetchUserNotelets) {
      return _value(<String, dynamic>{
        'notelets': <Object?>[
          <String, dynamic>{'id': 2, 'name': '花笺'},
        ],
        'paperQuantity': '2',
      });
    }
    if (invocation.memberName == #fetchUserMedals) {
      return _value(<String, dynamic>{
        'medals': <Object?>[
          <String, dynamic>{'propId': 3, 'name': '徽章'},
        ],
      });
    }
    if (invocation.memberName == #fetchUserCallingCards) {
      return _value(<String, dynamic>{
        'callingCards': <Object?>[
          <String, dynamic>{'id': 4, 'name': '名帖'},
        ],
      });
    }
    if (invocation.memberName == #fetchMyLiterarySociety) {
      return _value(<String, dynamic>{
        'success': true,
        'society': <String, dynamic>{
          'id': 7,
          'name': '白玉京',
          'level': 2,
          'memberCount': 6,
          'memberLimit': 6,
          'weekScore': 71,
          'members': <Object?>[
            <String, dynamic>{
              'userId': 11,
              'nickName': '社长',
              'weekScore': 21,
              'isPresident': true,
            },
          ],
        },
      });
    }
    if (invocation.memberName == #fetchLiterarySocietyScores) {
      return _value(<String, dynamic>{
        'weekStart': '2026-11-16',
        'totalScore': '71',
        'maxScore': '120',
        'members': <Object?>[
          <String, dynamic>{'nickName': '社长', 'weekScore': '51'},
        ],
      });
    }
    if (invocation.memberName == #fetchMerchantGuilds) {
      return _value(<String, dynamic>{
        'guilds': <Object?>[
          <String, dynamic>{'id': 6, 'name': '蓬莱商会', 'memberCount': 16},
        ],
        'membership': <String, dynamic>{'guildId': 6, 'contribution': 9},
        'joinCost': '100',
      });
    }
    if (invocation.memberName == #fetchGuildAuction) {
      return _value(<String, dynamic>{
        'coin': '312',
        'auction': <String, dynamic>{
          'id': 9,
          'itemName': '青瓷笔洗',
          'itemDescription': '今日商会拍卖',
          'startingPrice': '100',
          'highestBid': '120',
          'minimumBid': '125',
          'canBid': true,
          'endTime': '1794909600',
        },
      });
    }
    if (invocation.memberName == #fetchMyCollections) {
      return _value(<String, dynamic>{
        'items': <Object?>[
          <String, dynamic>{
            'markId': 31,
            'collectionType': 1,
            'collectionName': '读书想法',
            'mark': <String, dynamic>{'quote': '原文摘录'},
          },
        ],
      });
    }
    if (invocation.memberName == #fetchDailyLore) {
      return _value(<String, dynamic>{
        'id': 12,
        'title': '萃野纂闻《北寺浮图灾》',
        'content': '一件旧事牵出城中传闻。',
        'category': '轶闻',
        'quality': '上品',
      });
    }
    if (invocation.memberName == #fetchAuction) {
      return _value(<String, dynamic>{
        'auction': <String, dynamic>{
          'id': 8,
          'objectName': '青瓷笔洗',
          'category': '文玩',
          'appraisal': '真品',
          'highestBid': '120',
          'canBid': true,
        },
      });
    }
    if (invocation.memberName == #fetchTodayGambling) {
      return _value(<String, dynamic>{'id': 9, 'name': '今日樗蒲', 'prize': '鹿鸣印'});
    }
    if (invocation.memberName == #fetchTravelingMerchant) {
      return _value(<String, dynamic>{
        'cities': <Object?>[
          <String, dynamic>{
            'code': 'penglai',
            'name': '蓬莱',
            'routeType': '长途商道',
          },
        ],
        'transports': <Object?>[
          <String, dynamic>{
            'id': 9,
            'name': '鸟船',
            'speedPercent': 20,
            'owned': true,
          },
        ],
        'activeTrip': <String, dynamic>{
          'id': 88,
          'cityCode': 'penglai',
          'transportId': 9,
          'principal': 45,
          'status': 'traveling',
          'totalDurationMinutes': 2880,
        },
      });
    }
    if (invocation.memberName == #fetchTravelingMerchantHistory) {
      return _value(<String, dynamic>{'items': <Object?>[]});
    }
    if (invocation.memberName == #fetchTravelingMerchantRetainers) {
      return _value(<String, dynamic>{
        'retainers': <Object?>[
          <String, dynamic>{
            'id': 2,
            'surname': '沈',
            'givenName': '七',
            'quality': '上品',
            'owned': true,
          },
        ],
        'qinggui': '3',
        'pityCount': '40',
      });
    }
    if (invocation.memberName == #fetchWishUp) {
      return _value(<String, dynamic>{
        'propId': '5',
        'propName': '鹿鸣印',
        'description': '鹿鸣印概率 UP',
      });
    }
    if (invocation.memberName == #fetchTaoistBlessing) {
      return _value(<String, dynamic>{
        'freePrayAvailable': true,
        'todayPrayCount': 0,
      });
    }
    if (invocation.memberName == #fetchPawnCount) {
      return _value(<String, dynamic>{
        'usedToday': 0,
        'maxPerDay': 3,
        'remaining': 3,
      });
    }
    if (invocation.memberName == #fetchUserMaterials) {
      return _value(<String, dynamic>{
        'materials': <Object?>[
          <String, dynamic>{'userPropId': 1, 'name': '兔毫', 'quantity': 2},
        ],
      });
    }
    if (invocation.memberName == #fetchDailyShop) {
      return _value(<String, dynamic>{
        'items': <Object?>[
          <String, dynamic>{
            'propId': 2,
            'name': '宣纸',
            'price': 30,
            'type': '材料',
          },
        ],
        'coin': 3541,
      });
    }
    if (invocation.memberName == #fetchVoucherShop) {
      return _value(<String, dynamic>{'items': <Object?>[]});
    }
    if (invocation.memberName == #fetchMutualMarket) {
      return _value(<String, dynamic>{
        'props': <Object?>[],
        'listings': <Object?>[],
        'myListings': <Object?>[],
        'coin': '3541',
      });
    }
    if (invocation.memberName == #fetchRumors) {
      return _value(<String, dynamic>{'items': <Object?>[]});
    }
    if (invocation.memberName == #fetchPublicThoughts) {
      return _value(<String, dynamic>{
        'items': <Object?>[
          <String, dynamic>{
            'id': 31,
            'bookName': '北寺浮图灾',
            'chapter': '第二章',
            'note': '这段考据很有意思',
            'userName': '阅微读者',
          },
        ],
      });
    }
    if (invocation.memberName == #fetchMedalTreasure) {
      return _value(<String, dynamic>{
        'id': 4,
        'medalName': '鹿鸣印',
        'currentCount': 12,
        'totalCount': 40,
        'userCount': 8,
      });
    }
    return _value(<String, dynamic>{});
  }

  Future<YeSheJson> _value(Map<String, dynamic> value) {
    return Future<YeSheJson>.value(value);
  }

  @override
  void close() {}
}
