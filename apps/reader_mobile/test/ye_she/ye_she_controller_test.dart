import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/ye_she/ye_she_api_client.dart';
import 'package:reader_mobile/ye_she/ye_she_controller.dart';

void main() {
  test('一个模块失败不会清空其他模块', () async {
    final api = _FakeYeSheApi()..failStatus = true;
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);

    await controller.loadAll();

    expect(controller.title?.title, '青士');
    expect(controller.studyError, contains('账户'));
    expect(controller.playError, isNull);
    expect(controller.discoverError, isNull);
  });

  test('写操作成功后刷新对应模块并返回服务端消息', () async {
    final api = _FakeYeSheApi();
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);
    await controller.loadAll();

    final result = await controller.upgradeTitle();

    expect(result.success, isTrue);
    expect(result.message, '名帖已升至 2 级');
    expect(controller.title?.level, 2);
    expect(api.titleRequests, greaterThanOrEqualTo(2));
  });

  test('401 会标记登录失效并返回未授权结果', () async {
    final api = _FakeYeSheApi()..unauthorizedAction = true;
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);

    final result = await controller.joinGuild(1);

    expect(result.success, isFalse);
    expect(result.unauthorized, isTrue);
    expect(controller.authExpired, isTrue);
  });

  test('加载文会声望与商会拍卖并提交商会出价', () async {
    final api = _FakeYeSheApi();
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);

    await controller.loadAll();

    expect(controller.societyScores?.totalScore, 71);
    expect(controller.guildAuction?.itemName, '青瓷笔洗');
    expect(controller.guildAuction?.minimumBid, 125);

    final result = await controller.bidGuildAuction(130);

    expect(result.success, isTrue);
    expect(api.lastGuildBid, 130);
    expect(api.lastGuildAuctionId, 9);
  });

  test('行商进行中不可结算或再次出发', () async {
    final api = _FakeYeSheApi();
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);

    await controller.refreshPlay();
    final start = await controller.startTraveling(
      cityCode: 'penglai',
      transportId: 9,
      principal: 100,
    );
    final settle = await controller.settleTraveling();

    expect(start.success, isFalse);
    expect(start.message, contains('行商进行中'));
    expect(settle.success, isFalse);
    expect(settle.message, contains('仍在途中'));
    expect(api.startTravelRequests, 0);
    expect(api.settleTravelRequests, 0);
  });
}

class _FakeYeSheApi implements YeSheApi {
  bool failStatus = false;
  bool unauthorizedAction = false;
  int _titleLevel = 1;
  int titleRequests = 0;
  int lastGuildAuctionId = 0;
  int lastGuildBid = 0;
  int startTravelRequests = 0;
  int settleTravelRequests = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchCommunityStatus) {
      if (failStatus) {
        return Future<YeSheJson>.error(const YeSheException('社区状态读取失败'));
      }
      return Future<YeSheJson>.value(<String, dynamic>{
        'level': 2,
        'coin': '3541',
      });
    }
    if (invocation.memberName == #fetchCommunityTitle) {
      titleRequests += 1;
      return Future<YeSheJson>.value(<String, dynamic>{
        'title': '青士',
        'titleLevel': _titleLevel,
      });
    }
    if (invocation.memberName == #upgradeCommunityTitle) {
      _titleLevel = 2;
      return Future<YeSheJson>.value(<String, dynamic>{'message': '名帖已升至 2 级'});
    }
    if (invocation.memberName == #fetchMyLiterarySociety) {
      return Future<YeSheJson>.value(<String, dynamic>{
        'society': <String, dynamic>{'id': 7, 'name': '白玉京'},
      });
    }
    if (invocation.memberName == #fetchLiterarySocietyScores) {
      return Future<YeSheJson>.value(<String, dynamic>{
        'weekStart': '2026-11-16',
        'totalScore': '71',
        'maxScore': '120',
      });
    }
    if (invocation.memberName == #fetchMerchantGuilds) {
      return Future<YeSheJson>.value(<String, dynamic>{
        'guilds': <Object?>[
          <String, dynamic>{'id': 1, 'name': '聚宝楼'},
        ],
        'membership': <String, dynamic>{'guildId': 1, 'contribution': 9},
      });
    }
    if (invocation.memberName == #fetchGuildAuction) {
      return Future<YeSheJson>.value(<String, dynamic>{
        'coin': '312',
        'auction': <String, dynamic>{
          'id': 9,
          'itemName': '青瓷笔洗',
          'minimumBid': 125,
          'canBid': true,
        },
      });
    }
    if (invocation.memberName == #bidGuildAuction) {
      lastGuildAuctionId = invocation.namedArguments[#auctionId] as int;
      lastGuildBid = invocation.namedArguments[#amount] as int;
      return Future<YeSheJson>.value(<String, dynamic>{'message': '出价成功'});
    }
    if (invocation.memberName == #fetchTravelingMerchant) {
      final now = DateTime.now();
      return Future<YeSheJson>.value(<String, dynamic>{
        'activeTrip': <String, dynamic>{
          'id': 88,
          'status': 'TRAVELING',
          'startTime': now
              .subtract(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
          'endTime': now
              .add(const Duration(minutes: 90))
              .millisecondsSinceEpoch,
        },
      });
    }
    if (invocation.memberName == #startTravelingMerchant) {
      startTravelRequests += 1;
      return Future<YeSheJson>.value(<String, dynamic>{'message': '行商已出发'});
    }
    if (invocation.memberName == #settleTravelingMerchant) {
      settleTravelRequests += 1;
      return Future<YeSheJson>.value(<String, dynamic>{'message': '行商已结算'});
    }
    if (invocation.memberName == #joinMerchantGuild) {
      if (unauthorizedAction) {
        return Future<YeSheJson>.error(
          const YeSheException('登录已失效', unauthorized: true),
        );
      }
      return Future<YeSheJson>.value(<String, dynamic>{'message': '已加入商会'});
    }
    return Future<YeSheJson>.value(<String, dynamic>{});
  }

  @override
  void close() {}
}
