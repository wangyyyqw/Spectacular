import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/sync/sync_controller.dart';
import 'package:reader_mobile/sync/sync_models.dart';
import 'package:reader_mobile/sync/sync_page.dart';
import 'package:reader_mobile/sync/sync_secrets.dart';
import 'package:reader_mobile/sync/sync_storage.dart';
import 'package:reader_mobile/sync/sync_engine.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';

class _Secrets implements SyncSecretStore {
  final values = <String, SyncCredentials>{};
  bool fail = false;
  @override
  Future<SyncCredentials?> read(String identity) async => values[identity];
  @override
  Future<void> write(String identity, SyncCredentials credentials) async {
    if (fail) throw StateError('模拟安全存储失败');
    values[identity] = credentials;
  }
}

class _Storage implements SyncStorage {
  final files = <String, Uint8List>{};
  Future<void> Function(String)? beforeUpload;
  int connections = 0;
  bool fail = false;
  @override
  Future<Uint8List?> read(String key) async {
    if (key == 'library.json') connections++;
    if (fail) throw const HttpException('模拟网络失败');
    return files[key];
  }

  @override
  Future<void> upload(String key, File file, {bool createOnly = false}) async {
    await beforeUpload?.call(key);
    files[key] = await file.readAsBytes();
  }

  @override
  Future<List<String>> list(String directory) async =>
      files.keys
          .where((key) => key.startsWith('$directory/'))
          .map(
            (key) =>
                '$directory/${key.substring(directory.length + 1).split('/').first}',
          )
          .toSet()
          .toList()
        ..sort();
  @override
  Future<void> download(String key, File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(files[key]!);
  }

  @override
  Future<void> delete(String key) async {
    files.remove(key);
  }

  @override
  void close() {}
}

const _profile = SyncProfile(
  provider: SyncProvider.webdav,
  endpoint: 'http://localhost',
  automatic: false,
);

const _automaticProfile = SyncProfile(
  provider: SyncProvider.webdav,
  endpoint: 'http://localhost',
);

/// 界面测试只替换 I/O，真实创建、凭证保护和协议行为由下方控制器测试覆盖。
class _WidgetController extends SyncController {
  _WidgetController() : super(LibraryStore.memory(), secrets: _Secrets()) {
    profile = _profile;
  }
  bool created = false;
  @override
  bool get available => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<SyncCredentials> credentials() async => const SyncCredentials();
  @override
  Future<void> createLibrary(
    SyncProfile selected,
    SyncCredentials credentials, {
    required bool encrypted,
  }) async {
    created = true;
    profile = selected;
  }

  @override
  Future<SyncOutcome?> synchronize() async {
    message = '同步完成';
    return const SyncOutcome(uploaded: 0, downloaded: 0, conflicts: 0);
  }
}

Future<(SyncController, _Secrets, _Storage)> _controller({
  _Storage? cloud,
}) async {
  final root = await Directory.systemTemp.createTemp('sync-controller-');
  final db = AppDatabase(NativeDatabase.memory());
  final secrets = _Secrets();
  final storage = cloud ?? _Storage();
  final library = LibraryStore(
    database: db,
    directoryProvider: () async => root,
  );
  final controller = SyncController(
    library,
    secrets: secrets,
    storageFactory: (_, _) => storage,
  );
  addTearDown(() async {
    controller.dispose();
    await db.close();
    await root.delete(recursive: true);
  });
  await controller.initialize();
  return (controller, secrets, storage);
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets('同步页提供两种后端、完整数据说明、可选加密并将创建请求交给控制器', (tester) async {
    final controller = _WidgetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: SyncPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('WebDAV'), findsOneWidget);
    expect(find.textContaining('统计页的时长'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('新同步库启用端到端加密'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('新同步库启用端到端加密'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('创建同步库'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    final create = find.widgetWithText(OutlinedButton, '创建同步库');
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('创建明文同步库'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
    expect(controller.created, isTrue);
    expect(controller.message, contains('同步完成'));
  });

  test('凭证和恢复密钥不进入 settings，重复保存保留基线', () async {
    final (controller, secrets, _) = await _controller();
    await controller.library.importBytes(buildTestEpub());
    const credentials = SyncCredentials(
      access: 'private-user',
      secret: 'private-password',
    );
    await controller.createLibrary(_profile, credentials, encrypted: false);
    await controller.synchronize();
    final key = (await controller.library.getSetting('sync.collection.v1'))!;
    final before = (await controller.library.getSetting('sync.state.$key'))!;
    await controller.saveProfile(_profile, credentials);
    expect(await controller.library.getSetting('sync.state.$key'), before);
    final profile = (await controller.library.getSetting('sync.profile.v1'))!;
    expect(profile, isNot(contains('private-password')));
    expect(profile, isNot(contains('private-user')));
    expect(secrets.values.values.single.secret, 'private-password');
  });

  test('安全存储失败不创建远端同步库，重复创建不覆盖已有凭证', () async {
    final (controller, secrets, storage) = await _controller();
    secrets.fail = true;
    await expectLater(
      controller.createLibrary(
        _profile,
        const SyncCredentials(secret: 'old'),
        encrypted: false,
      ),
      throwsStateError,
    );
    expect(storage.files, isEmpty);
    secrets.fail = false;
    await controller.createLibrary(
      _profile,
      const SyncCredentials(secret: 'old'),
      encrypted: false,
    );
    final before = storage.files['library.json'];
    await expectLater(
      controller.createLibrary(
        _profile,
        const SyncCredentials(secret: 'new'),
        encrypted: false,
      ),
      throwsFormatException,
    );
    expect(storage.files['library.json'], before);
    expect(secrets.values.values.single.secret, 'old');
  });

  test('同步失败向界面保留失败状态，不被当成成功', () async {
    final (controller, _, storage) = await _controller();
    await controller.saveProfile(_profile, const SyncCredentials());
    storage.fail = true;
    expect(await controller.synchronize(), isNull);
    expect(controller.message, contains('同步失败'));
    expect(controller.lastSync, isNull);
  });

  for (final pauseBeforeCompletion in [false, true]) {
    testWidgets(
      '慢速上传期间多次修改${pauseBeforeCompletion ? '在前台恢复后补发' : '合并为后续同步'}，另一台设备收到最终版本',
      (tester) async {
        final (controller, _, storage) = await pumpReaderTask(
          tester,
          _controller(),
        );
        final book = await pumpReaderTask(
          tester,
          controller.library.importBytes(buildTestEpub(title: '原始版本')),
        );
        await pumpReaderTask(
          tester,
          controller.createLibrary(
            _automaticProfile,
            const SyncCredentials(),
            encrypted: false,
          ),
        );
        final started = Completer<void>();
        final release = Completer<void>();
        storage.beforeUpload = (key) async {
          if (key.startsWith('personal/_sync/logs/') && !started.isCompleted) {
            started.complete();
            await release.future;
          }
        };
        final connections = storage.connections;
        final pending = controller.synchronize();
        await pumpReaderTask(tester, started.future);
        for (final title in ['中间版本', '最终版本']) {
          await pumpReaderTask(
            tester,
            controller.library.updateBookMetadata(
              book.id,
              title: title,
              author: '测试作者',
              description: '同步中的修改',
            ),
          );
        }
        await tester.pump(const Duration(seconds: 4));
        expect(controller.synchronize(), same(pending));
        if (pauseBeforeCompletion) controller.paused();
        release.complete();
        await pumpReaderTask(tester, pending);
        await tester.pump(const Duration(seconds: 4));
        if (pauseBeforeCompletion) {
          expect(storage.connections, connections + 1);
          controller.resumed();
          await tester.pump(const Duration(seconds: 4));
        }
        await pumpReaderUntilComplete(tester, () => !controller.syncing);
        expect(storage.connections, connections + 2);
        await tester.pump(const Duration(seconds: 4));
        expect(storage.connections, connections + 2);

        controller.paused();

        // 接收包含两版 EPUB 的导入与换版，在真实异步区等待文件和 isolate 完成。
        await tester.runAsync(() async {
          final (receiver, _, _) = await _controller(cloud: storage);
          await receiver.join(_profile, const SyncCredentials());
          expect((await receiver.synchronize())!.downloaded, 2);
          final received = await receiver.library.list();
          expect(received.single.title, '最终版本');
        });
      },
    );
  }

  testWidgets('关闭自动同步取消尚未触发的同步，手动同步仍然可用', (tester) async {
    final (controller, _, storage) = await pumpReaderTask(
      tester,
      _controller(),
    );
    await pumpReaderTask(
      tester,
      controller.createLibrary(
        _automaticProfile,
        const SyncCredentials(),
        encrypted: false,
      ),
    );
    final connections = storage.connections;
    await pumpReaderTask(
      tester,
      controller.saveProfile(_profile, const SyncCredentials()),
    );
    await tester.pump(const Duration(seconds: 4));
    await pumpReaderUntilComplete(tester, () => !controller.syncing);
    expect(storage.connections, connections);
    expect(await pumpReaderTask(tester, controller.synchronize()), isNotNull);
    expect(storage.connections, connections + 1);
  });

  testWidgets('临时模式禁用创建、连接测试与同步', (tester) async {
    final controller = SyncController(
      LibraryStore.memory(),
      secrets: _Secrets(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: SyncPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('临时模式已禁用同步'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('创建同步库'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '创建同步库'),
    );
    expect(button.onPressed, isNull);
  });
}
