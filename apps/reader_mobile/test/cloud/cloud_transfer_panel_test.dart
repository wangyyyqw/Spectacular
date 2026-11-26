import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/cloud/cloud_accounts.dart';
import 'package:reader_mobile/cloud/cloud_download.dart';
import 'package:reader_mobile/cloud/cloud_import_controller.dart';
import 'package:reader_mobile/cloud/cloud_models.dart';
import 'package:reader_mobile/cloud/cloud_transfer_panel.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

import '../support/test_epub.dart';

class _Accounts implements CloudAccountStore {
  @override
  Future<CloudAccount?> read(CloudDrive drive) async => null;
  @override
  Future<void> remove(CloudDrive drive) async {}
  @override
  Future<void> save(CloudAccount account) async {}
}

class _Provider implements CloudProviderApi {
  _Provider(this.source);
  final Future<CloudDownload> Function(CloudEntry) source;
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
      source(file);
}

Widget _app(
  CloudImportController controller, {
  ValueChanged<CloudImportItem>? onRetry,
  VoidCallback? onRelogin,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) => RepaintBoundary(
  key: const ValueKey('任务面板预览'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('夸克网盘')),
      body: Column(
        children: [
          const Expanded(child: Center(child: Text('全部文件'))),
          CloudTransferPanel(
            controller: controller,
            onRetry: onRetry ?? (_) {},
            onRelogin: onRelogin ?? () {},
          ),
        ],
      ),
    ),
  ),
);

Future<void> _preview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_CLOUD_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('任务面板预览')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('dist/cloud-ui-20261126')
      ..createSync(recursive: true);
    File('${directory.path}/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_CLOUD_UI')) return;
    await (FontLoader(
      'builtin_song',
    )..addFont(rootBundle.load('assets/fonts/MoyuSerif-Regular.otf'))).load();
  });
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('cloud-transfer-panel-');
  });
  tearDown(() {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  testWidgets('真实下载进度驱动任务面板，窄屏大字可取消当前及等待任务', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final epub = buildTestEpub(title: '进度验证');
    late Completer<void> firstChunk;
    late Completer<void> releaseDownload;
    final library = LibraryStore.memory();
    Stream<List<int>> content() async* {
      yield epub.sublist(0, epub.length ~/ 2);
      await releaseDownload.future;
      yield epub.sublist(epub.length ~/ 2);
    }

    final controller = CloudImportController(
      provider: _Provider(
        (_) async => CloudDownload(
          Uri.parse('https://files.example/book'),
          size: epub.length,
        ),
      ),
      account: CloudAccount(CloudDrive.quark, {}),
      accounts: _Accounts(),
      library: library,
      temporaryDirectory: () async => temporary,
      downloadFactory: () => CloudBookDownload(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(content(), 200),
        ),
      ),
    );
    controller.addListener(() {
      if (!firstChunk.isCompleted &&
          controller.items.any((item) => item.received > 0)) {
        firstChunk.complete();
      }
    });
    await tester.pumpWidget(_app(controller, textScale: 1.5));
    expect(find.text('查看任务'), findsNothing);
    late Future<void> operation;
    await tester.runAsync(() async {
      firstChunk = Completer<void>();
      releaseDownload = Completer<void>();
      operation = controller.start([
        const CloudEntry(id: 'active', name: '一部名称很长的中文云端书籍.epub'),
        const CloudEntry(id: 'queued', name: '下一本书.epub'),
      ]);
      await firstChunk.future.timeout(const Duration(seconds: 15));
    });
    await tester.pump();
    final item = controller.items.first;
    expect(item.status, CloudImportStatus.downloading);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(.5, .001),
    );
    expect(find.textContaining('已导入 0 / 2'), findsOneWidget);
    await tester.tap(find.text('查看任务'));
    await tester.pumpAndSettle();
    expect(find.text(item.label), findsOneWidget);
    expect(
      find.text(
        '${cloudFileSize(item.received)} / ${cloudFileSize(item.total)}',
      ),
      findsOneWidget,
    );
    expect(find.text('等待下载'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _preview(tester, 'transfer-tasks-narrow');
    await tester.tap(find.text('取消剩余'));
    await tester.runAsync(() async {
      releaseDownload.complete();
      await operation;
    });
    await tester.pumpAndSettle();
    expect(
      controller.items.every(
        (item) => item.status == CloudImportStatus.cancelled,
      ),
      isTrue,
    );
    expect(find.textContaining('已取消 2'), findsWidgets);
    expect(find.text('重试'), findsNWidgets(2));
    expect(find.text('取消剩余'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.close);
    controller.dispose();
  });

  testWidgets('真实导入完成后显示成功统计，不再显示下载进度或重试按钮', (tester) async {
    final epub = buildTestEpub(title: '下载完成');
    final library = LibraryStore.memory();
    final controller = CloudImportController(
      provider: _Provider(
        (_) async => CloudDownload(
          Uri.parse('https://files.example/book'),
          size: epub.length,
        ),
      ),
      account: CloudAccount(CloudDrive.quark, {}),
      accounts: _Accounts(),
      library: library,
      temporaryDirectory: () async => temporary,
      downloadFactory: () => CloudBookDownload(
        client: MockClient((_) async => http.Response.bytes(epub, 200)),
      ),
    );
    await tester.pumpWidget(_app(controller));
    await tester.runAsync(
      () => controller.start([const CloudEntry(id: 'done', name: '下载完成.epub')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('已导入 1 / 1'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('查看任务'));
    await tester.pumpAndSettle();
    expect(find.text('已导入书架'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('取消剩余'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.close);
    controller.dispose();
  });

  testWidgets('失败、登录失效及 TXT 编码错误分别路由正确操作并关闭任务列表', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // ASCII 检测样本后接 GBK「第一章\n正文」，触发真实编码纠错。
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
    final retries = <CloudImportItem>[];
    var relogins = 0;
    final controller = CloudImportController(
      provider: _Provider((file) async {
        if (file.id == 'failure') {
          throw const CloudException('下载连接中断，请重试');
        }
        if (file.id == 'login') {
          throw const CloudException('登录已失效，请重新登录', loginRequired: true);
        }
        return CloudDownload(
          Uri.parse('https://files.example/book'),
          size: bytes.length,
        );
      }),
      account: CloudAccount(CloudDrive.quark, {}),
      accounts: _Accounts(),
      library: LibraryStore.memory(),
      temporaryDirectory: () async => temporary,
      downloadFactory: () => CloudBookDownload(
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      ),
    );
    await tester.pumpWidget(
      _app(
        controller,
        onRetry: retries.add,
        onRelogin: () => relogins++,
        brightness: Brightness.dark,
      ),
    );
    await tester.runAsync(
      () => controller.start([
        const CloudEntry(id: 'failure', name: '连接中断.epub'),
        const CloudEntry(id: 'login', name: '需要重新登录.epub'),
        const CloudEntry(id: 'encoding', name: '选择正确文字编码.txt'),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('已导入 0 / 3 · 失败 3'), findsOneWidget);
    await tester.tap(find.text('查看任务'));
    await tester.pumpAndSettle();
    expect(find.text('选择编码'), findsOneWidget);
    await _preview(tester, 'transfer-tasks-errors-dark');
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(retries.single, same(controller.items[0]));
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('查看任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();
    expect(relogins, 1);
    expect(retries, hasLength(1));
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('查看任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择编码'));
    await tester.pumpAndSettle();
    expect(retries.last, same(controller.items[2]));
    expect(retries.last.job!.encodingCandidates, isNotEmpty);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.close);
    controller.dispose();
  });
}
