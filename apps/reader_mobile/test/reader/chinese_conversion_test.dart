import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/text/reader_text_conversion.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_chinese_converter.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:spectacular_opencc/opencc_native.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

List<PageBlock> _blocks(List<PageContent> pages) => pages
    .expand((page) => page.slices)
    .map((slice) => slice.block)
    .toSet()
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ReaderChineseConverter converter;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reader-opencc-');
    converter = ReaderChineseConverter(
      directoryProvider: () async => directory,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  test('实际原生 OpenCC 按词组区分皇后、头发和发展，官方词条优先于旧词典', () async {
    expect(await converter.load(ReaderChineseMode.original), isNull);
    final traditional = (await converter.load(ReaderChineseMode.traditional))!;
    final simplified = (await converter.load(ReaderChineseMode.simplified))!;
    expect(traditional.convert('皇后头发与数据库，发展😀').text, '皇后頭髮與數據庫，發展😀');
    expect(simplified.convert('皇后頭髮與數據庫，發展😀').text, '皇后头发与数据库，发展😀');
    expect(
      traditional.convert('乃偷咱焊襁鼗').text.length,
      6,
      reason: '旧字符表中粘连的多候选不得覆盖官方字符表',
    );
    expect(
      identical(
        await converter.load(ReaderChineseMode.traditional),
        traditional,
      ),
      isTrue,
    );
    final files = (await directory.list(recursive: true).toList())
        .map((file) => file.path.split(Platform.pathSeparator).last)
        .toSet();
    expect(
      files,
      containsAll(<String>[
        's2t.json',
        't2s.json',
        'STPhrases.ocd2',
        'STCharacters.ocd2',
        'TSPhrases.ocd2',
        'TSCharacters.ocd2',
      ]),
    );
    expect(
      () => convertOpencc('${directory.path}/missing.json', '测试'),
      throwsStateError,
      reason: '原生失败不得静默改用 Dart 转换器',
    );
  });

  test('正式引擎只转换排版树，行内词组、来源 CFI、原文锚点和缓存隔离正确', () async {
    final bytes = buildMultiChapterEpub(
      chapters: [
        '<p id="text">皇<span style="color:red">后头</span>发与数据库😀</p>',
        '<p>第二章头发与发展</p>',
      ],
      rawBody: true,
    );
    final source = await EpubChapterSource.open(
      bytes,
      contentVersion: 'opencc-engine',
    );
    addTearDown(source.close);
    await source.applyContentSize(width: 360, height: 600);
    final original = await source.loadAnchorChapter(0);
    final before = _blocks(await source.loadChapter(0));
    final originalBlock = before.singleWhere(
      (block) => block.layout.text.contains('数据库'),
    );
    final cfi = originalBlock.cfiAt(originalBlock.layout.text.indexOf('数据库'))!;
    final dependency = source.layoutDependency;
    source.applyTextConversion(
      await converter.load(ReaderChineseMode.traditional),
    );
    final converted = _blocks(await source.loadChapter(0));
    final block = converted.singleWhere(
      (block) => block.layout.text.contains('數據庫'),
    );
    expect(block.layout.text, '皇后頭髮與數據庫😀');
    expect(block.cfiAt(block.layout.text.indexOf('數據庫')), cfi);
    expect(block.offsetForCfi(cfi), block.layout.text.indexOf('數據庫'));
    expect((await source.loadAnchorChapter(0)).text, original.text);
    expect(
      (await source.loadAnchorChapter(0)).fingerprint,
      original.fingerprint,
    );
    expect(source.document.chapterXhtml(0), contains('后头'));
    expect(source.layoutDependency, isNot(dependency));
    expect(
      _blocks(await source.loadChapter(1))
          .map((block) => block.layout.text)
          .join(),
      contains('第二章頭髮與發展'),
    );
    source.applyTextConversion(null);
    expect(
      _blocks(await source.loadChapter(0))
          .map((block) => block.layout.text)
          .join(),
      contains('皇后头发与数据库😀'),
    );
    expect(source.layoutDependency, dependency);
  });

  testWidgets('菜单简繁入口紧邻日夜按钮，转换后按原文位置续读并保存偏好', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = LibraryStore.memory();
    final settingsStore = ReaderSettingsStore(library);
    final progress = MemoryReaderProgressStore();
    var closed = false;
    var settings = ReaderSettings.defaults;
    final bytes = buildTestEpub(
      paragraphs: [
        for (var index = 0; index < 30; index++) '第$index段，皇后头发与数据库，发展😀。' * 4,
      ],
    );
    Future<void> open() async {
      closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: EpubReaderPage(
            bytes: bytes,
            bookId: 'chinese-mode-flow',
            store: progress,
            settings: settings,
            onSettingsChanged: (value) {
              settings = value;
              settingsStore.save(value);
            },
            onClosed: () => closed = true,
          ),
        ),
      );
      await pumpReaderUntil(tester, find.byType(ReaderView));
    }

    await open();
    final session = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await pumpReaderTask(tester, session.next());
    await tester.pumpAndSettle();
    final cfi = session.currentCfi;
    final percent = session.readingPercent;
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('menu-chinese-conversion'));
    final dayNight = tester.getRect(
      find.byKey(const ValueKey('menu-daynight')),
    );
    expect(tester.getRect(button).left, dayNight.right);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('menu-chinese-traditional')),
    );
    await pumpReaderUntilComplete(
      tester,
      () =>
          tester.widget<ReaderPage>(find.byType(ReaderPage)).chineseMode ==
              ReaderChineseMode.traditional &&
          !session.loading,
      description: '原生繁体转换和正文重排',
    );
    expect(session.currentCfi, cfi);
    expect(session.readingPercent, percent);
    final convertedPages = await pumpReaderTask(tester, session.chapterPages());
    expect(
      _blocks(convertedPages).map((block) => block.layout.text).join(),
      contains('皇后頭髮與數據庫'),
    );
    expect(
      (await settingsStore.load()).chineseMode,
      ReaderChineseMode.traditional,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpReaderUntilComplete(tester, () => closed);
    await open();
    final reopened = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .chineseMode,
      ReaderChineseMode.traditional,
    );
    expect(reopened.currentCfi, cfi);
    expect(
      reopened.page!.slices.map((slice) => slice.block.layout.text).join(),
      contains('頭髮'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpReaderUntilComplete(tester, () => closed);
  });
}
