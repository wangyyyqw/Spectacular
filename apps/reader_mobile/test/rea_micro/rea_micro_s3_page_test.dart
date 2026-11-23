import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_s3.dart';
import 'package:reader_mobile/rea_micro/rea_micro_s3_page.dart';

class _Account extends ReaMicroController {
  _Account()
    : super(library: LibraryStore.memory(), enableLanLoginServer: false);

  @override
  Future<ReaMicroS3CloudConfig> fetchCloudS3Config() async =>
      const ReaMicroS3CloudConfig(enabled: false, encryptedConfig: '');
  @override
  Future<ReaMicroStorageQuota> fetchStorageQuota() async =>
      const ReaMicroStorageQuota(
        capacityBytes: 1073741824,
        capacityGib: 1,
        credit: 143,
        usedBytes: 6291456,
      );
  @override
  Future<ReaMicroCreditLedgerPage> fetchCreditLedger({
    int page = 1,
    int pageSize = 20,
  }) async => const ReaMicroCreditLedgerPage(
    items: [
      ReaMicroCreditLedgerItem(
        action: '阅读',
        amount: 1,
        balanceAfter: 143,
        objectKey: '',
        operation: '阅读积分',
        createTime: 0,
      ),
    ],
    hasMore: false,
  );
}

void main() {
  testWidgets('同步方式位于容量上方，其他方式隐藏容量流水且保留输入', (tester) async {
    final account = _Account();
    addTearDown(account.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ReaMicroS3Page(controller: account)),
    );
    await tester.pumpAndSettle();
    final provider = find.byKey(const ValueKey('sync-provider-setting'));
    final quota = find.byKey(const ValueKey('sync-storage-quota'));
    final ledger = find.byKey(const ValueKey('sync-credit-ledger'));
    expect(quota, findsNothing);
    expect(ledger, findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, '服务端点'),
      'https://s3.example.test',
    );
    await tester.tap(provider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅微对象存储').last);
    await tester.pumpAndSettle();
    expect(quota, findsOneWidget);
    expect(ledger, findsOneWidget);
    expect(
      tester.getBottomLeft(provider).dy,
      lessThan(tester.getTopLeft(quota).dy),
    );
    await tester.tap(provider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自建 S3').last);
    await tester.pumpAndSettle();
    expect(quota, findsNothing);
    expect(ledger, findsNothing);
    expect(find.text('https://s3.example.test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
