import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/navigation_settings.dart';
import 'package:reader_mobile/home/navigation_settings_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_api_client.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_store.dart';

class _AccountApi implements ReaMicroApiClient {
  ReaMicroUser current = const ReaMicroUser(id: 1, nickName: '测试账号');
  @override
  Future<ReaMicroUser> fetchUser(String token) async => current;
  @override
  Future<List<ReaMicroChartPoint>> fetchReadTimeChart(
    String token, {
    int limit = 30,
  }) async => [];
  @override
  Future<ReaMicroS3CloudConfigResponse> fetchS3CloudConfig(
    String token,
  ) async =>
      const ReaMicroS3CloudConfigResponse(enabled: false, encryptedConfig: '');
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('发现默认隐藏，用户选择与发现提示处理结果可持久保存', () async {
    final library = LibraryStore.memory();
    final account = ReaMicroController(
      library: library,
      api: _AccountApi(),
      enableLanLoginServer: false,
    );
    final settings = NavigationSettings(library, account);
    addTearDown(account.dispose);
    addTearDown(settings.dispose);
    await settings.initialize();
    expect(settings.visible(HomeDestination.discover), isFalse);
    expect(settings.visible(HomeDestination.notes), isTrue);
    await settings.setVisible(HomeDestination.discover, true);
    await settings.setVisible(HomeDestination.notes, false);
    await settings.markDiscoveryPromptHandled();
    final restored = NavigationSettings(library, account);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.visible(HomeDestination.discover), isTrue);
    expect(restored.visible(HomeDestination.notes), isFalse);
    expect(restored.discoveryPromptHandled, isTrue);
  });

  testWidgets('非青士统计入口隐藏并置灰，权限刷新后恢复原选择', (tester) async {
    final library = LibraryStore.memory();
    await ReaMicroStore(library).saveToken('测试令牌');
    final api = _AccountApi();
    final account = ReaMicroController(
      library: library,
      api: api,
      enableLanLoginServer: false,
    );
    addTearDown(account.dispose);
    await account.initialize();
    final settings = NavigationSettings(library, account);
    addTearDown(settings.dispose);
    await settings.initialize();
    await tester.pumpWidget(
      MaterialApp(home: NavigationSettingsPage(settings: settings)),
    );
    final finder = find.byKey(const ValueKey('navigation-setting-stats'));
    expect(settings.visible(HomeDestination.stats), isFalse);
    expect(tester.widget<ReaderSwitchListTile>(finder).onChanged, isNull);
    await settings.setVisible(HomeDestination.stats, true);
    expect(settings.visible(HomeDestination.stats), isFalse);
    api.current = const ReaMicroUser(
      id: 1,
      nickName: '测试账号',
      userType: 3,
      vipExpireTime: '2027-01-01 00:00:00',
    );
    await account.refresh();
    await tester.pumpAndSettle();
    expect(settings.visible(HomeDestination.stats), isTrue);
    expect(tester.widget<ReaderSwitchListTile>(finder).onChanged, isNotNull);
    await account.logout();
    expect(settings.visible(HomeDestination.stats), isTrue);
  });

  test('青士判定使用账号类型与期限字段，缓存保留权限', () {
    for (final user in [
      const ReaMicroUser(
        id: 1,
        nickName: '',
        userType: 2,
        vipExpireTime: '2027-01-01',
      ),
      const ReaMicroUser(id: 1, nickName: '', userType: 3),
      const ReaMicroUser(
        id: 1,
        nickName: '',
        userType: 3,
        vipExpireTime: '0000-00-00 00:00:00',
      ),
    ]) {
      expect(user.hasQingShi, isFalse);
    }
    const user = ReaMicroUser(
      id: 1,
      nickName: '',
      userType: 3,
      vipExpireTime: '2027-01-01',
    );
    expect(ReaMicroUser.fromJson(user.toJson()).hasQingShi, isTrue);
  });
}
