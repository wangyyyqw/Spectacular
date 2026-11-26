import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/cloud/cloud_accounts.dart';
import 'package:reader_mobile/cloud/cloud_download.dart';
import 'package:reader_mobile/cloud/cloud_import_controller.dart';
import 'package:reader_mobile/cloud/cloud_login_config.dart';
import 'package:reader_mobile/cloud/cloud_models.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/test_epub.dart';

class _Accounts implements CloudAccountStore {
  int saved = 0;
  @override
  Future<CloudAccount?> read(CloudDrive drive) async => null;
  @override
  Future<void> remove(CloudDrive drive) async {}
  @override
  Future<void> save(CloudAccount account) async {
    saved++;
  }
}

class _Provider implements CloudProviderApi {
  _Provider(this.source);
  final Future<CloudDownload> Function() source;
  @override
  CloudDrive get drive => CloudDrive.quark;
  @override
  String get rootId => '0';
  @override
  Future<String> validate(CloudAccount account) async => '测试账号';
  @override
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  }) async => const CloudListing([]);
  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) =>
      source();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUp(
    () => temporary = Directory.systemTemp.createTempSync('cloud-import-test-'),
  );
  tearDown(() {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  test('七家范围固定，凭据按官网存储类型识别，仿冒来源不能读取', () {
    expect(CloudDrive.values.map((drive) => drive.name), [
      'baidu',
      'quark',
      'aliyun',
      'pan123',
      'tianyi',
      'pikpak',
      'lanzou',
    ]);
    expect(
      CloudDrive.aliyun.canReadStorage(
        Uri.parse('https://www.alipan.com.evil.test/'),
      ),
      isFalse,
    );
    expect(
      CloudDrive.aliyun.canReadStorage(Uri.parse('http://www.alipan.com/')),
      isFalse,
    );
    expect(
      cloudLoginCandidate(CloudDrive.baidu, 'unrelated=value', null),
      isNull,
    );
    final account = cloudLoginCandidate(
      CloudDrive.aliyun,
      '',
      jsonEncode({
        'access_token': 'test-access',
        'refresh_token': 'test-refresh',
        'user_id': '1',
      }),
    );
    expect(account!.field('refreshToken'), 'test-refresh');
    expect(account.cookie, isEmpty);
    expect(
      cloudLoginCandidate(
        CloudDrive.pan123,
        '',
        '"long-test-token-123"',
      )!.field('accessToken'),
      'long-test-token-123',
    );
  });

  test('下载跨站跳转移除凭据，字节大小验证后保存', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return requests.length == 1
          ? http.Response(
              '',
              302,
              headers: {'location': 'https://cdn.example/book.txt'},
            )
          : http.Response('book', 200, headers: {'content-type': 'text/plain'});
    });
    final file = File('${temporary.path}/book.txt');
    await CloudBookDownload(client: client).save(
      CloudDownload(
        Uri.parse('https://drive.example/file'),
        headers: {
          'Cookie': 'private=value',
          'Authorization': 'Bearer test',
          'User-Agent': 'test',
        },
        size: 4,
      ),
      file,
      onProgress: (_, _) {},
    );
    expect(requests.first.headers['Cookie'], 'private=value');
    expect(
      requests.last.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('cookie')),
    );
    expect(
      requests.last.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(await file.readAsString(), 'book');
  });

  test('验证页和截断文件拒绝导入且删除下载残留', () async {
    for (final html in [true, false]) {
      final client = MockClient(
        (_) async => http.Response(
          'bad',
          200,
          headers: {
            'content-type': html ? 'text/html' : 'application/octet-stream',
          },
        ),
      );
      final file = File('${temporary.path}/bad.epub');
      await expectLater(
        CloudBookDownload(client: client).save(
          CloudDownload(Uri.parse('https://files.example/book'), size: 10),
          file,
          onProgress: (_, _) {},
        ),
        throwsA(
          isA<CloudException>().having(
            (error) => error.loginRequired,
            '验证页可直接重新登录',
            html,
          ),
        ),
      );
      expect(file.existsSync(), isFalse);
    }
  });

  test('分块下载先报告大小，取消后不再写入并删除残留', () async {
    final progress = <(int, int)>[];
    final download = CloudBookDownload(
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          200,
        ),
      ),
    );
    final file = File('${temporary.path}/cancelled.epub');
    await expectLater(
      download.save(
        CloudDownload(Uri.parse('https://files.example/book'), size: 4),
        file,
        onProgress: (received, total) {
          progress.add((received, total));
          if (received > 0) download.cancel();
        },
      ),
      throwsA(isA<CloudDownloadCancelled>()),
    );
    expect(progress, [(0, 4), (2, 4)]);
    expect(file.existsSync(), isFalse);
  });

  test('无响应长度的分块下载超过文件大小时立即停止，不上报超额进度', () async {
    final progress = <(int, int)>[];
    final file = File('${temporary.path}/oversized.epub');
    await expectLater(
      CloudBookDownload(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4, 5],
            ]),
            200,
          ),
        ),
      ).save(
        CloudDownload(Uri.parse('https://files.example/book'), size: 4),
        file,
        onProgress: (received, total) => progress.add((received, total)),
      ),
      throwsA(isA<CloudException>()),
    );
    expect(progress, [(0, 4), (2, 4)]);
    expect(file.existsSync(), isFalse);
  });

  test('正式队列转发导入进度，同批和重复选择不重复下载，退出清理暂存', () async {
    final epub = buildTestEpub(title: '云端山海');
    final library = LibraryStore.memory();
    final accounts = _Accounts();
    final controller = CloudImportController(
      provider: _Provider(
        () async => CloudDownload(
          Uri.parse('https://files.example/book'),
          size: epub.length,
        ),
      ),
      account: CloudAccount(CloudDrive.quark, {'cookie': '__pus=test'}),
      accounts: accounts,
      library: library,
      temporaryDirectory: () async => temporary,
      downloadFactory: () => CloudBookDownload(
        client: MockClient((_) async => http.Response.bytes(epub, 200)),
      ),
    );
    final importProgress = <double>[];
    controller.addListener(() {
      for (final item in controller.items) {
        if (item.status == CloudImportStatus.importing &&
            item.progress != null) {
          importProgress.add(item.progress!);
        }
      }
    });
    const file = CloudEntry(id: 'book', name: '山海.epub');
    await controller.start([
      file,
      file,
      const CloudEntry(id: 'ignored', name: 'video.mp4'),
    ]);
    expect(controller.items.single.status, CloudImportStatus.completed);
    expect(controller.items.single.progress, 1);
    expect(importProgress.where((value) => value > 0 && value < 1), isNotEmpty);
    expect((await library.list()).single.title, '云端山海');
    await controller.start([file]);
    expect(await library.list(), hasLength(1));
    expect(controller.items, hasLength(1));
    expect(accounts.saved, 1);
    await controller.start([const CloudEntry(id: 'copy', name: '副本.epub')]);
    expect(await library.list(), hasLength(1));
    expect(controller.items, hasLength(2));
    expect(accounts.saved, 2);
    await controller.close();
    expect(temporary.listSync(), isEmpty);
    controller.dispose();
  });

  test('下载失败后重试清除旧进度，重新选择取消任务沿用原任务', () async {
    final epub = buildTestEpub(title: '重试下载');
    final library = LibraryStore.memory();
    final retrySource = Completer<CloudDownload>();
    final resolvingRetry = Completer<void>();
    var attempts = 0;
    final controller = CloudImportController(
      provider: _Provider(() async {
        attempts++;
        if (attempts == 2) {
          resolvingRetry.complete();
          return retrySource.future;
        }
        return CloudDownload(
          Uri.parse('https://files.example/book'),
          size: epub.length,
        );
      }),
      account: CloudAccount(CloudDrive.quark, {}),
      accounts: _Accounts(),
      library: library,
      temporaryDirectory: () async => temporary,
      downloadFactory: () => CloudBookDownload(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.value(attempts == 1 ? [1, 2, 3] : epub),
            200,
          ),
        ),
      ),
    );
    const file = CloudEntry(id: 'book', name: '重试.epub');
    await controller.start([file]);
    final item = controller.items.single;
    expect(item.status, CloudImportStatus.failed);
    expect(item.received, 3);
    expect(item.total, epub.length);
    final retry = controller.retry(item);
    await resolvingRetry.future;
    expect(item.received, 0);
    expect(item.total, 0);
    expect(item.progress, isNull);
    expect(item.error, isNull);
    controller.cancel();
    retrySource.complete(
      CloudDownload(Uri.parse('https://files.example/book'), size: epub.length),
    );
    await retry;
    expect(item.status, CloudImportStatus.cancelled);
    await controller.start([file]);
    expect(controller.items.single, same(item));
    expect(item.status, CloudImportStatus.completed);
    expect((await library.list()).single.title, '重试下载');
    await controller.close();
    controller.dispose();
  });

  test('取链期间取消不下载、不导入并清理任务', () async {
    final pending = Completer<CloudDownload>();
    final started = Completer<void>();
    final library = LibraryStore.memory();
    var downloads = 0;
    final controller = CloudImportController(
      provider: _Provider(() {
        started.complete();
        return pending.future;
      }),
      account: CloudAccount(CloudDrive.quark, {}),
      accounts: _Accounts(),
      library: library,
      temporaryDirectory: () async => temporary,
      downloadFactory: () {
        downloads++;
        return CloudBookDownload();
      },
    );
    final operation = controller.start([
      const CloudEntry(id: 'book', name: 'book.epub'),
    ]);
    await started.future;
    controller.cancel();
    pending.complete(CloudDownload(Uri.parse('https://files.example/book')));
    await operation;
    expect(downloads, 0);
    expect(controller.items.single.status, CloudImportStatus.cancelled);
    expect(await library.list(), isEmpty);
    await controller.close();
    controller.dispose();
  });

  test('TXT 编码失败可复用已下载文件，选择编码后正式导入成功', () async {
    // ASCII 样本后接 GBK「第一章\n正文」，触发正式导入器的编码纠错。
    final bytes = [
      ...List.filled(65536, 0x61),
      0x0a,
      0xb5,
      0xda,
      0xd2,
      0xbb,
      0xd5,
      0xc2,
      0x0a,
      0xd5,
      0xfd,
      0xce,
      0xc4,
    ];
    var downloads = 0;
    final library = LibraryStore.memory();
    final controller = CloudImportController(
      provider: _Provider(
        () async => CloudDownload(
          Uri.parse('https://files.example/book'),
          size: bytes.length,
        ),
      ),
      account: CloudAccount(CloudDrive.quark, {}),
      accounts: _Accounts(),
      library: library,
      temporaryDirectory: () async => temporary,
      downloadFactory: () {
        downloads++;
        return CloudBookDownload(
          client: MockClient((_) async => http.Response.bytes(bytes, 200)),
        );
      },
    );
    await controller.start([const CloudEntry(id: 'txt', name: '编码纠错.txt')]);
    final item = controller.items.single;
    expect(item.status, CloudImportStatus.failed);
    expect(item.job!.encodingCandidates, isNotEmpty);
    expect(item.localFile!.existsSync(), isTrue);
    await controller.retry(item, encoding: 'GBK');
    expect(item.status, CloudImportStatus.completed);
    expect(item.error, isNull);
    expect(item.localFile, isNull);
    expect(downloads, 1);
    expect((await library.list()).single.title, '编码纠错');
    await controller.close();
    controller.dispose();
  });
}
