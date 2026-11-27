import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/ye_she/community_page.dart';
import 'package:reader_mobile/ye_she/ye_she_api_client.dart';
import 'package:reader_mobile/ye_she/ye_she_controller.dart';
import 'package:reader_mobile/ye_she/ye_she_models.dart';
import 'package:reader_mobile/ye_she/ye_she_page.dart';

void main() {
  testWidgets('野社首屏只加载文房，切换页签后再加载对应内容', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _DemoYeSheApi();
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: YeShePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('文房'), findsWidgets);
    expect(find.text('游艺'), findsOneWidget);
    expect(find.text('见闻'), findsOneWidget);
    expect(find.text('文会、清玩与榜上声名'), findsNothing);
    expect(find.text('白玉京'), findsWidgets);
    expect(find.text('青士'), findsWidgets);
    expect(find.text('名帖'), findsWidgets);
    expect(find.text('本周文会声望 71/120'), findsOneWidget);
    expect(find.text('我的收藏'), findsNothing);
    expect(find.text('社区想法'), findsNothing);
    expect(find.text('黄金台 · 徽章征集'), findsNothing);
    expect(api.calls, contains(#fetchCommunityStatus));
    expect(api.calls, contains(#fetchMyLiterarySociety));
    expect(api.calls, isNot(contains(#fetchTodayGambling)));
    expect(api.calls, isNot(contains(#fetchWishUp)));
    expect(api.calls, isNot(contains(#fetchPublicThoughts)));
    expect(api.calls, isNot(contains(#fetchMyCollections)));
    expect(api.calls, isNot(contains(#fetchMedalTreasure)));

    await tester.tap(find.text('游艺'));
    await tester.pumpAndSettle();
    expect(find.text('商会 · 财富'), findsOneWidget);
    expect(find.text('商会拍卖 · 青瓷笔洗'), findsOneWidget);
    expect(find.text('聚宝楼'), findsWidgets);
    expect(find.text('青瓷笔洗'), findsWidgets);
    expect(find.text('今日樗蒲'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('道观'),
      360,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('道观'), findsOneWidget);
    expect(api.calls, contains(#fetchTodayGambling));
    expect(api.calls, contains(#fetchMerchantGuilds));
    expect(api.calls, isNot(contains(#fetchWishUp)));
    expect(api.calls, isNot(contains(#fetchPublicThoughts)));

    await tester.tap(find.text('见闻'));
    await tester.pumpAndSettle();
    expect(find.text('祈愿 · 鹿鸣印'), findsOneWidget);
    expect(find.text('期物司'), findsOneWidget);
    expect(find.text('萃野纂闻《北寺浮图灾》'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('百杂铺'),
      320,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('百杂铺'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('玉机阁'),
      320,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('玉机阁'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('互市坊'),
      320,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('互市坊'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('唱经楼'),
      320,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('唱经楼'), findsOneWidget);
    expect(api.calls, contains(#fetchWishUp));
    expect(api.calls, isNot(contains(#fetchPublicThoughts)));
    expect(api.calls, isNot(contains(#fetchMyCollections)));
    expect(api.calls, isNot(contains(#fetchMedalTreasure)));
  });

  testWidgets('文房首屏直接显示行商与门客，不再提示尚未读取', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _DemoYeSheApi();
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: YeShePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(api.calls, contains(#fetchTravelingMerchant));
    expect(api.calls, contains(#fetchTravelingMerchantRetainers));
    expect(find.text('行商状态尚未读取'), findsNothing);
    expect(find.text('门客名册尚未读取'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('ye-she-merchant')),
      360,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('行程进行中'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('ye-she-retainers')),
      360,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('黄金台 · 门客'), findsOneWidget);
    expect(find.text('沈七'), findsOneWidget);
  });

  testWidgets('首帧读取中不显示暂不可用', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = YeSheController(
      tokenProvider: () => 'token',
      api: _HangingYeSheApi(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: YeShePage(controller: controller)),
    );
    await tester.pump();

    expect(find.text('正在读取…'), findsWidgets);
    expect(find.text('账户状态暂不可用'), findsNothing);
    expect(find.text('名帖信息暂不可用'), findsNothing);
  });

  testWidgets('典当成功后展示获得的铜钱', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _DemoYeSheApi(pawnCoin: 12);
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: YeShePage(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('ye-she-tab-discover')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('ye-she-pawn')),
      320,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey<String>('ye-she-material-11')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('典当成功 · 获得铜钱 12 文'), findsWidgets);
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
      find.text('唱经楼'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('唱经楼'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('野社标题与页签在明暗主题下均使用主题前景色', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final controller = YeSheController(
        tokenProvider: () => 'token',
        api: _DemoYeSheApi(),
      );
      addTearDown(controller.dispose);
      final theme = ThemeData(brightness: brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: YeShePage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      final tabBar = tester.widget<TabBar>(
        find.byKey(const ValueKey<String>('ye-she-tab-bar')),
      );
      expect(tabBar.labelColor, theme.colorScheme.onSurface);
      expect(tabBar.unselectedLabelColor, theme.colorScheme.onSurfaceVariant);
      expect(tabBar.labelColor, isNot(Colors.white));

      final title = tester.widget<Text>(
        find.byKey(const ValueKey<String>('ye-she-header-title')),
      );
      expect(title.style?.color, theme.colorScheme.onSurface);
    }
  });

  testWidgets('会长显示文会管理按钮，普通成员只能退出文会', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpSociety({
      required int currentUserId,
      required _DemoYeSheApi api,
    }) async {
      final controller = YeSheController(
        tokenProvider: () => 'token',
        api: api,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: YeShePage(controller: controller, currentUserId: currentUserId),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpSociety(
      currentUserId: 11,
      api: _DemoYeSheApi(presidentUserId: 11, memberUserId: 11),
    );
    expect(find.text('修改封面'), findsOneWidget);
    expect(find.text('移出成员'), findsOneWidget);
    expect(find.text('解散文会'), findsOneWidget);
    expect(find.text('退出文会'), findsNothing);

    await pumpSociety(
      currentUserId: 12,
      api: _DemoYeSheApi(presidentUserId: 11, memberUserId: 12),
    );
    expect(find.text('修改封面'), findsNothing);
    expect(find.text('移出成员'), findsNothing);
    expect(find.text('解散文会'), findsNothing);
    expect(find.text('退出文会'), findsOneWidget);

    await pumpSociety(
      currentUserId: 0,
      api: _DemoYeSheApi(presidentUserId: 11, memberUserId: 11),
    );
    expect(find.text('修改封面'), findsNothing);
    expect(find.text('移出成员'), findsNothing);
    expect(find.text('解散文会'), findsNothing);
    expect(find.text('退出文会'), findsNothing);
  });

  testWidgets('已领取文会周奖励时按钮与状态同步禁用', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = YeSheController(
      tokenProvider: () => 'token',
      api: _DemoYeSheApi(rewardStatus: 'CLAIMED', claimedRewardName: '鹿鸣印'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: YeShePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('已领取 鹿鸣印'), findsOneWidget);
    expect(find.text('本周已领取'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('ye-she-society-reward')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('行商进行中显示进度并隐藏结算与另起一程', (tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
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
    await tester.tap(find.byKey(const ValueKey<String>('ye-she-tab-play')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('ye-she-tab-study')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ye-she-merchant-progress')),
      findsOneWidget,
    );
    expect(find.text('行程进行中'), findsOneWidget);
    expect(find.text('结算行程'), findsNothing);
    expect(find.text('另起一程'), findsNothing);
  });

  testWidgets('名帖显示升级与传承所需材料及持有数量', (tester) async {
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

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('ye-she-title')),
        matching: find.text('本次消耗'),
      ),
      findsOneWidget,
    );
    expect(find.text('清酒'), findsOneWidget);
    expect(find.text('檀香'), findsOneWidget);
    expect(find.text('欹器'), findsOneWidget);
    expect(find.text('需要 1 · 拥有 1'), findsNWidgets(3));
    final upgrade = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '升级'),
    );
    final heritage = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '传承'),
    );
    expect(upgrade.onPressed, isNotNull);
    expect(heritage.onPressed, isNotNull);
  });

  testWidgets('材料不足时名帖升级与传承按钮不可用', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = YeSheController(
      tokenProvider: () => 'token',
      api: _DemoYeSheApi(
        materials: <Map<String, dynamic>>[
          <String, dynamic>{'propId': 11, 'name': '清酒', 'quantity': 1},
          <String, dynamic>{'propId': 13, 'name': '檀香', 'quantity': 1},
        ],
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: YeShePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('需要 1 · 拥有 0'), findsOneWidget);
    final upgrade = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '升级'),
    );
    final heritage = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '传承'),
    );
    expect(upgrade.onPressed, isNull);
    expect(heritage.onPressed, isNull);
  });

  testWidgets('社区顶部三栏按顺序展示公开想法、收藏与全站书评', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _DemoYeSheApi();
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);
    final account = _ReviewAccount();
    addTearDown(account.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CommunityPage(controller: controller, account: account),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('community-page')),
      findsOneWidget,
    );
    final tabs = find.descendant(
      of: find.byType(TabBar),
      matching: find.byType(Text),
    );
    expect(tester.widgetList<Text>(tabs).map((text) => text.data), [
      '想法',
      '收藏',
      '书评',
    ]);
    expect(find.text('收藏与阅微读者的公开想法'), findsNothing);
    expect(find.text('原文摘录'), findsNothing);
    expect(find.text('这段考据很有意思'), findsOneWidget);
    expect(find.textContaining('北寺浮图灾'), findsWidgets);
    expect(find.text('阅微读者'), findsWidgets);
    expect(api.calls, contains(#fetchMyCollections));
    expect(api.calls, contains(#fetchPublicThoughts));
    expect(account.pages, isEmpty);
    await tester.tap(find.byKey(const ValueKey('community-tab-collections')));
    await tester.pumpAndSettle();
    expect(find.text('原文摘录'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-tab-reviews')));
    await tester.pumpAndSettle();
    expect(account.pages, [1]);
    expect(find.text('公开书评正文'), findsOneWidget);
    expect(find.text('山河纪'), findsOneWidget);
  });

  testWidgets('想法滚过二十条自动续页，切栏与收藏后保留列表', (tester) async {
    final api = _PagedThoughtApi();
    final controller = YeSheController(tokenProvider: () => 'token', api: api);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: CommunityPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(api.pages, [1]);
    final list = find.byKey(const PageStorageKey('community-thoughts'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('想法 21'),
      440,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(api.pages, [1, 2]);
    expect(controller.thoughtFeed.items.length, 21);
    final position = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.tap(find.byKey(const ValueKey('community-tab-collections')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-tab-thoughts')));
    await tester.pumpAndSettle();
    final action = find.descendant(
      of: find
          .ancestor(of: find.text('想法 21'), matching: find.byType(Container))
          .first,
      matching: find.widgetWithText(TextButton, '收藏'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(api.calls, contains(#collectMark));
    expect(api.pages, [1, 2]);
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThanOrEqualTo(position - 1),
    );
    expect(find.text('想法 21'), findsOneWidget);
  });

  testWidgets('社区页未登录时显示登录提示', (tester) async {
    final controller = YeSheController(
      tokenProvider: () => '',
      api: _DemoYeSheApi(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CommunityPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('community-signed-out')),
      findsOneWidget,
    );
    expect(find.text('登录阅微后查看社区'), findsOneWidget);
  });
}

class _ReviewAccount extends ChangeNotifier implements ReaMicroController {
  final pages = <int>[];
  @override
  Listenable get pageRefresh => this;

  @override
  Future<List<ReaMicroBookReview>> loadReviewFlow({
    int? cloudBookId,
    int page = 1,
    int pageSize = 20,
  }) async {
    expect(cloudBookId, isNull);
    pages.add(page);
    return [
      ReaMicroBookReview.fromJson({
        'id': 91,
        'bookName': '山河纪',
        'comment': '公开书评正文',
      }),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PagedThoughtApi extends _DemoYeSheApi {
  final pages = <int>[];

  @override
  Future<YeSheJson> fetchPublicThoughts({
    int page = 1,
    int size = 20,
    String bookId = '',
    String cloudBookId = '',
  }) async {
    pages.add(page);
    return {
      'items': [
        for (var id = page == 1 ? 1 : 20; id <= (page == 1 ? 20 : 21); id++)
          {'id': id, 'note': '想法 $id'},
      ],
    };
  }
}

class _DemoYeSheApi implements YeSheApi {
  _DemoYeSheApi({
    List<Map<String, dynamic>>? materials,
    this.presidentUserId = 11,
    this.memberUserId = 11,
    this.rewardStatus = 'CLAIMABLE',
    this.claimedRewardName = '',
    this.pawnCoin = 12,
  }) : materials =
           materials ??
           <Map<String, dynamic>>[
             <String, dynamic>{
               'userPropId': 11,
               'propId': 11,
               'name': '清酒',
               'quantity': 1,
             },
             <String, dynamic>{
               'userPropId': 13,
               'propId': 13,
               'name': '檀香',
               'quantity': 1,
             },
             <String, dynamic>{
               'userPropId': 18,
               'propId': 18,
               'name': '欹器',
               'quantity': 1,
             },
           ];

  final Set<Symbol> calls = <Symbol>{};
  final List<Map<String, dynamic>> materials;
  final int presidentUserId;
  final int memberUserId;
  final String rewardStatus;
  final String claimedRewardName;
  final int pawnCoin;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
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
          <String, dynamic>{'id': 1, 'propId': 20, 'name': '麒麟印'},
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
          <String, dynamic>{'propId': 33, 'name': '鹿鸣印'},
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
          'presidentUserId': presidentUserId,
          'rewardStatus': rewardStatus,
          'claimedRewardName': claimedRewardName,
          'members': <Object?>[
            <String, dynamic>{
              'userId': memberUserId,
              'nickName': memberUserId == presidentUserId ? '社长' : '成员',
              'weekScore': 21,
              'isPresident': memberUserId == presidentUserId,
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
      return _value(<String, dynamic>{'materials': materials});
    }
    if (invocation.memberName == #pawn) {
      final userPropId = invocation.positionalArguments.first as int;
      for (final item in materials) {
        if (yeSheInt(item['userPropId']) == userPropId) {
          final quantity = yeSheInt(item['quantity']);
          item['quantity'] = quantity > 0 ? quantity - 1 : 0;
        }
      }
      return _value(<String, dynamic>{'coin': pawnCoin});
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

class _HangingYeSheApi implements YeSheApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<YeSheJson>().future;
}
