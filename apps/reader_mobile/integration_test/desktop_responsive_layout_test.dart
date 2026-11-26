import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../test/support/test_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('响应式桌面验收等待超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 350));
}

Widget _app(HomeShell home, {bool dark = false}) => MaterialApp(
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (_, child) =>
      RepaintBoundary(key: const ValueKey('responsive-capture'), child: child),
  home: home,
);

Future<void> _capture(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
  if (!const bool.fromEnvironment('CAPTURE_DESKTOP_RESPONSIVE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('responsive-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory(
      '${Directory.systemTemp.path}/desktop-responsive-evidence',
    ).create(recursive: true);
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('响应式桌面截图：${file.path}');
  } finally {
    image.dispose();
  }
}

/// 隔离样书封面只用于布局验收，不写入用户书库或产品资源。
Future<Uint8List> _cover(String title, int index) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const colors = [
    Color(0xff324f46),
    Color(0xffa76349),
    Color(0xff40536a),
    Color(0xff7e4549),
    Color(0xffa98a50),
    Color(0xff535359),
  ];
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 300, 400),
    Paint()..color = colors[index % colors.length],
  );
  final titlePainter = TextPainter(
    text: TextSpan(
      text: title,
      style: const TextStyle(
        fontFamily: 'builtin_song',
        fontSize: 34,
        height: 1.5,
        color: Color(0xfffff4dc),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 236);
  titlePainter.paint(canvas, const Offset(32, 48));
  canvas.drawLine(
    const Offset(32, 275),
    const Offset(268, 275),
    Paint()
      ..color = const Color(0x99fff4dc)
      ..strokeWidth = 1,
  );
  final caption = TextPainter(
    text: const TextSpan(
      text: '阅读与日常\n墨屿 · 排版样书',
      style: TextStyle(fontSize: 15, height: 1.8, color: Color(0xfffff4dc)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  caption.paint(canvas, const Offset(32, 300));
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 400);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
    titlePainter.dispose();
    caption.dispose();
  }
}

Future<void> _select(WidgetTester tester, String label) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(NavigationRail),
          matching: find.byTooltip(label),
        )
        .hitTestable()
        .first,
  );
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('桌面响应式：封面上限、单本筛选、列表多选和各导航页缩窗', (tester) async {
    final root = await Directory.systemTemp.createTemp('desktop-responsive-');
    final database = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: database,
      directoryProvider: () async => root,
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final titles = [
      '山川与日常',
      '漫长的旅途',
      '阅读的回声',
      '城市札记',
      '草木之间',
      '深夜的灯',
      '一座小岛',
      '雨后的街道',
      '生活的形状',
      '远山来信',
      '书页里的光',
      '河流与时间',
      '慢下来的风景',
      '故事的另一面',
      '把日子写成诗',
      '星空下的散步',
      '自然的笔记',
      '再见春天',
    ];
    for (final (index, title) in titles.indexed) {
      final book = await library.importBytes(buildTestEpub(title: title));
      await library.replaceCover(
        book.id,
        await _cover(title, index),
        extension: 'png',
      );
    }
    final home = HomeShell(
      library: library,
      progressStore: MemoryReaderProgressStore(),
    );
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await tester.pumpWidget(_app(home));
    final covers = find.byKey(const ValueKey('book-card-cover'));
    await _until(tester, () => covers.evaluate().length >= 12);
    for (final size in [
      const Size(1360, 900),
      const Size(1920, 1000),
      const Size(960, 760),
      const Size(640, 760),
      const Size(320, 760),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      for (final cover in covers.evaluate()) {
        expect(
          tester.getSize(find.byWidget(cover.widget)).width,
          lessThanOrEqualTo(160.01),
        );
      }
      final grid = tester.getSize(find.byKey(const ValueKey('bookshelf-grid')));
      expect(grid.width, lessThanOrEqualTo(1440));
      expect(tester.takeException(), isNull);
      await _capture(tester, '书架-${size.width.toInt()}-日间');
    }
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final originalSize = tester.getSize(covers.first);
    await tester.tap(find.byKey(const ValueKey('bookshelf-search-field')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('bookshelf-search-field')),
      '山川与日常',
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(covers, findsOneWidget);
    expect(tester.getSize(covers), originalSize);
    await _capture(tester, '书架-单本搜索');
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpWidget(_app(home, dark: true));
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(tester, '书架-1360-夜间');
    await tester.tap(find.byKey(const ValueKey('bookshelf-multi-select')));
    await tester.pump();
    await tester.tap(covers.first);
    await tester.pump();
    expect(find.text('已选 1 本'), findsOneWidget);
    await _capture(tester, '书架-宽窗多选');
    await tester.binding.setSurfaceSize(const Size(390, 760));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(tester, '书架-窄窗多选');
    await tester.tap(find.byTooltip('退出多选'));
    await tester.binding.setSurfaceSize(const Size(1920, 1000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(tester, '书架-列表宽度');
    await tester.binding.setSurfaceSize(const Size(640, 760));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (final label in ['统计', '笔记', '编辑', '我的', '书架']) {
      await _select(tester, label);
      await _capture(tester, '$label-640-夜间');
    }
    expect((await library.list()).length, titles.length);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
