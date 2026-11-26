import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/cloud/cloud_accounts.dart';
import 'package:reader_mobile/cloud/cloud_import_page.dart';
import 'package:reader_mobile/cloud/cloud_models.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

class _Store implements CloudAccountStore {
  int saves = 0;
  bool failRead = false;
  CloudAccount? account;
  @override
  Future<CloudAccount?> read(CloudDrive drive) async {
    if (failRead) throw StateError('安全存储暂时不可用');
    return account?.drive == drive ? account : null;
  }

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

Widget _app(Widget page, {Brightness brightness = Brightness.light}) =>
    RepaintBoundary(
      key: const ValueKey('网盘界面预览'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(brightness: brightness),
        home: page,
      ),
    );

CloudFilesPage _page(_Drive provider, {_Store? store}) => CloudFilesPage(
  provider: provider,
  account: CloudAccount(CloudDrive.quark, {}),
  accounts: store ?? _Store(),
  library: LibraryStore.memory(),
);

Future<void> _preview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_CLOUD_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('网盘界面预览')),
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
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_CLOUD_UI')) return;
    await (FontLoader(
      'builtin_song',
    )..addFont(rootBundle.load('assets/fonts/MoyuSerif-Regular.otf'))).load();
  });

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
    expect(find.text('下载并导入（1）'), findsOneWidget);
    await tester.tap(find.text('子目录'));
    await tester.pumpAndSettle();
    expect(find.text('目录读取失败'), findsOneWidget);
    expect(find.text('旧文件.epub'), findsNothing);
    expect(find.text('加载更多'), findsNothing);
    expect(find.text('下载并导入（0）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('网盘入口随壁纸取色和经典、MD3 风格切换', (tester) async {
    final library = LibraryStore.memory();
    final accounts = _Store();
    for (final style in AppUiStyle.values) {
      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xff934d75),
          brightness: brightness,
        );
        final theme = buildAppTheme(
          colorScheme: scheme,
          brightness: brightness,
          uiStyle: style,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: CloudImportPage(library: library, accounts: accounts),
          ),
        );
        await tester.pumpAndSettle();
        final tile = tester.widget<ListTile>(
          find.byKey(const ValueKey('cloud-quark')),
        );
        final decoration =
            (tile.leading! as Container).decoration! as BoxDecoration;
        expect(decoration.color, scheme.surfaceContainerLow);
        expect(decoration.borderRadius, ReaderUiStyle.controlRadiusOf(theme));
      }
    }
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
        theme: buildAppTheme(),
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

  testWidgets('账号读取失败可以重试且清除错误', (tester) async {
    final store = _Store()..failRead = true;
    await tester.pumpWidget(
      _app(CloudImportPage(library: LibraryStore.memory(), accounts: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法读取系统安全存储中的账号，请重试'), findsOneWidget);
    store.failRead = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('无法读取系统安全存储中的账号，请重试'), findsNothing);
    expect(find.byKey(const ValueKey('cloud-quark')), findsOneWidget);
  });

  testWidgets('连续点击同一账号只打开一次文件页，返回可再次进入', (tester) async {
    final store = _Store()..account = CloudAccount(CloudDrive.quark, {});
    var loads = 0;
    await tester.pumpWidget(
      _app(
        CloudImportPage(
          library: LibraryStore.memory(),
          accounts: store,
          providerFactory: (_, _) => _Drive((_, _) async {
            loads++;
            return const CloudListing([]);
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cloud-quark')));
    await tester.tap(find.byKey(const ValueKey('cloud-quark')));
    await tester.pumpAndSettle();
    expect(loads, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('把云端藏书带到书架'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloud-quark')));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('当前目录筛选与全选仅作用于匹配的书籍，其他选择保留', (tester) async {
    await tester.pumpWidget(
      _app(
        _page(
          _Drive(
            (_, _) async => const CloudListing([
              CloudEntry(id: 'a', name: '春日.epub', size: 100),
              CloudEntry(id: 'b', name: '秋日.TXT', size: 200),
              CloudEntry(id: 'c', name: '封面.png'),
              CloudEntry(id: 'folder', name: '其他书籍', isFolder: true),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('春日.epub'));
    await tester.enterText(find.byType(TextField), '秋日');
    await tester.pumpAndSettle();
    expect(find.text('春日.epub'), findsNothing);
    await tester.tap(find.text('全选当前结果'));
    await tester.pump();
    expect(find.text('下载并导入（2）'), findsOneWidget);
    await tester.tap(find.text('取消全选'));
    await tester.pump();
    expect(find.text('下载并导入（1）'), findsOneWidget);
    await tester.tap(find.byTooltip('清除筛选'));
    await tester.tap(find.text('仅看书籍'));
    await tester.pumpAndSettle();
    expect(find.text('封面.png'), findsNothing);
    expect(find.text('其他书籍'), findsOneWidget);
    expect(find.text('春日.epub'), findsOneWidget);
  });

  testWidgets('刷新失败保留当前文件和选择，重试从首页加载', (tester) async {
    var fail = false;
    final calls = <String?>[];
    await tester.pumpWidget(
      _app(
        _page(
          _Drive((_, cursor) async {
            calls.add(cursor);
            if (fail) throw const CloudException('连接已断开');
            return const CloudListing([
              CloudEntry(id: 'b', name: '春日.epub'),
            ], nextPage: '2');
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('春日.epub'));
    fail = true;
    await tester.tap(find.byTooltip('刷新目录'));
    await tester.pumpAndSettle();
    expect(find.text('春日.epub'), findsOneWidget);
    expect(find.text('下载并导入（1）'), findsOneWidget);
    expect(find.text('连接已断开'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, [null, null, null]);
    expect(find.text('连接已断开'), findsNothing);
  });

  testWidgets('分页失败重试原游标，追加去重并保留选择', (tester) async {
    var fail = true;
    final calls = <String?>[];
    await tester.pumpWidget(
      _app(
        _page(
          _Drive((_, cursor) async {
            calls.add(cursor);
            if (cursor == null) {
              return const CloudListing([
                CloudEntry(id: 'a', name: '春日.epub'),
              ], nextPage: '2');
            }
            if (fail) throw const CloudException('下一页读取失败');
            return const CloudListing([
              CloudEntry(id: 'a', name: '春日.epub'),
              CloudEntry(id: 'b', name: '秋日.txt'),
            ]);
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('春日.epub'));
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, [null, '2', '2']);
    expect(find.text('春日.epub'), findsOneWidget);
    expect(find.text('秋日.txt'), findsOneWidget);
    expect(find.text('下载并导入（1）'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets('系统返回先回上级目录并清理目录筛选', (tester) async {
    await tester.pumpWidget(
      _app(
        _page(
          _Drive(
            (folder, _) async => folder == '0'
                ? const CloudListing([
                    CloudEntry(id: 'folder', name: '书籍', isFolder: true),
                  ])
                : const CloudListing([CloudEntry(id: 'b', name: '春日.epub')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('书籍'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '无匹配');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('文件夹'), findsOneWidget);
    expect(find.text('春日.epub'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  testWidgets('账号入口和文件目录适配日夜主题、窄屏与键盘', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    for (final brightness in Brightness.values) {
      final store = _Store()
        ..account = CloudAccount(CloudDrive.quark, {}, name: '阅读账号');
      await tester.pumpWidget(
        _app(
          CloudImportPage(library: LibraryStore.memory(), accounts: store),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _preview(tester, '网盘入口-${brightness.name}');
      await tester.pumpWidget(
        _app(
          _page(
            _Drive(
              (_, _) async => const CloudListing([
                CloudEntry(id: 'folder', name: '我的藏书', isFolder: true),
                CloudEntry(id: 'a', name: '人间草木.epub', size: 2400000),
                CloudEntry(id: 'b', name: '山海之间.txt', size: 98651),
                CloudEntry(id: 'c', name: '阅读笔记.pdf', size: 220000),
              ]),
            ),
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('人间草木.epub'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _preview(tester, '文件目录-${brightness.name}');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
