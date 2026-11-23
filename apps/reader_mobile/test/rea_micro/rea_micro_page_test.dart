import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_page.dart';

class _Controller extends ReaMicroController {
  _Controller()
    : super(library: LibraryStore.memory(), enableLanLoginServer: false);
  bool refreshing = false;
  @override
  bool get initialized => true;
  @override
  bool get signedIn => true;
  @override
  bool get busy => refreshing;
  @override
  String? get notice => '标注已是最新';
  @override
  String? get error => '自动刷新暂不可用';
  @override
  ReaMicroUser? get user => const ReaMicroUser(id: 123, nickName: '测试读者');
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refreshIfStale({
    Duration maxAge = const Duration(minutes: 5),
  }) async {}
  void setRefreshing(bool value) {
    refreshing = value;
    notifyListeners();
  }
}

void main() {
  testWidgets('同步页自动刷新不显示顶部提示或动画且账号位置固定', (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ReaMicroPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    final position = tester.getTopLeft(find.text('测试读者'));
    expect(find.byKey(const ValueKey('reamicro-notice')), findsNothing);
    expect(find.byKey(const ValueKey('reamicro-error')), findsNothing);
    controller.setRefreshing(true);
    await tester.pump();
    expect(tester.getTopLeft(find.text('测试读者')), position);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    controller.setRefreshing(false);
    await tester.pump();
    expect(tester.getTopLeft(find.text('测试读者')), position);
    expect(tester.takeException(), isNull);
  });
}
