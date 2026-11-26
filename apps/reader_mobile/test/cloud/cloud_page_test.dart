import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/cloud/cloud_accounts.dart';
import 'package:reader_mobile/cloud/cloud_import_page.dart';
import 'package:reader_mobile/cloud/cloud_models.dart';
import 'package:reader_mobile/library/library_store.dart';

class _Store implements CloudAccountStore {
  int saves = 0;
  @override
  Future<CloudAccount?> read(CloudDrive drive) async => null;
  @override
  Future<void> remove(CloudDrive drive) async {}
  @override
  Future<void> save(CloudAccount account) async {
    saves++;
  }
}

class _Drive implements CloudProviderApi {
  _Drive(this.browse);
  final Future<CloudListing> Function(String, String?) browse;
  @override
  CloudDrive get drive => CloudDrive.quark;
  @override
  String get rootId => '0';
  @override
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  }) => browse(folderId, cursor);
  @override
  Future<String> validate(CloudAccount account) async => '测试';
  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) async =>
      throw const CloudException('不用于该测试');
}

void main() {
  testWidgets('目录失败不显示旧文件，不保留选择或分页', (tester) async {
    final store = _Store();
    await tester.pumpWidget(
      MaterialApp(
        home: CloudFilesPage(
          provider: _Drive((folder, _) async {
            if (folder != '0') throw const CloudException('目录读取失败');
            return const CloudListing([
              CloudEntry(id: 'folder', name: '子目录', isFolder: true),
              CloudEntry(id: 'book', name: '旧文件.epub'),
            ], nextPage: '2');
          }),
          account: CloudAccount(CloudDrive.quark, {}),
          accounts: store,
          library: LibraryStore.memory(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('旧文件.epub'));
    await tester.pump();
    expect(find.text('导入选中（1）'), findsOneWidget);
    await tester.tap(find.text('子目录'));
    await tester.pumpAndSettle();
    expect(find.text('目录读取失败'), findsOneWidget);
    expect(find.text('旧文件.epub'), findsNothing);
    expect(find.text('加载更多'), findsNothing);
    expect(find.text('导入选中（0）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('返回账号页后迟到目录响应不重新保存凭据', (tester) async {
    final pending = Completer<CloudListing>();
    final store = _Store();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => CloudFilesPage(
                    provider: _Drive((_, _) => pending.future),
                    account: CloudAccount(CloudDrive.quark, {}),
                    accounts: store,
                    library: LibraryStore.memory(),
                  ),
                ),
              ),
              child: const Text('打开网盘'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开网盘'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    pending.complete(const CloudListing([]));
    await tester.pumpAndSettle();
    expect(find.text('打开网盘'), findsOneWidget);
    expect(store.saves, 0);
  });

  testWidgets('窄屏大字下网盘目录与选择操作没有溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: CloudFilesPage(
          provider: _Drive(
            (_, _) async => const CloudListing([
              CloudEntry(id: 'b', name: '一个较长的云端中文书籍名称.epub', size: 1000),
            ]),
          ),
          account: CloudAccount(CloudDrive.quark, {}),
          accounts: _Store(),
          library: LibraryStore.memory(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
