import 'dart:io';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_store.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/reader/reader_decoration_image_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/panels/decoration_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/reader_ui_diagnostics.dart';
import 'package:reader_ui/selection/selection_layer.dart';
import 'package:reader_ui/decorations/decoration_image_store.dart';
import 'package:reader_ui/decorations/decoration_image_codec.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/decoration_style.dart';

import '../support/reader_pump.dart';
import 'support/css_chapter_book.dart';

const _padding = EdgeInsets.fromLTRB(24, 40, 24, 40);
final _messages = <String>[];

class _CountingImages implements ReaderDecorationImageStore {
  _CountingImages(this.source);
  final ReaderDecorationImageStore source;
  final loaded = <String>[];
  @override
  Future<String?> pickImage() => source.pickImage();
  @override
  Future<Uint8List> loadImage(String path) async {
    final bytes = await source.loadImage(path);
    loaded.add(path);
    return bytes;
  }

  @override
  Future<void> removeUnused(Set<String> referencedPaths) =>
      source.removeUnused(referencedPaths);
}

class _Fixture {
  _Fixture(
    this.directory,
    this.database,
    this.library,
    this.book,
    this.source,
    this.releaseAnchors,
  );

  final Directory directory;
  final AppDatabase database;
  final LibraryStore library;
  final BookEntry book;
  final EpubChapterSource source;
  late final images = ReaderDecorationImages(
    directoryProvider: () async => directory,
  );
  final void Function() releaseAnchors;
  late ReaderSession session;

  Future<void> close() async {
    releaseAnchors();
    source.close();
    await database.close();
    directory.deleteSync(recursive: true);
  }
}

Future<_Fixture> _fixture(WidgetTester tester, {String? body}) async {
  return (await tester.runAsync(() async {
    final directory = Directory.systemTemp.createTempSync('decoration-flow-');
    final database = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: database,
      directoryProvider: () async => directory,
    );
    final bytes = buildCssChapterBook(
      body: body ?? '<h1>标题</h1><p>${'甲乙丙丁戊己庚辛壬癸' * 60}</p>',
      css:
          'body { margin:0; font-size:16px; } '
          'p,h1 { margin:0; line-height:1.5; }',
    );
    final imported = await library.importBytes(bytes);
    final book = (await library.bookById(imported.id))!;
    final source = await EpubChapterSource.open(
      bytes,
      contentWidth: 272,
      contentHeight: 440,
      verifyCrc: false,
    );
    final release = await bindReadingAnchorSource(
      database,
      book.id,
      source,
      book.contentRevision!,
    );
    return _Fixture(directory, database, library, book, source, release);
  }))!;
}

Future<void> _show(
  WidgetTester tester,
  _Fixture fixture, {
  ReaderDecorationImageStore? images,
  Future<void> Function(String)? onDictionary,
}) async {
  tester.view.physicalSize = const Size(320, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ReaderPage(
          source: fixture.source,
          store: MemoryReaderProgressStore(),
          bookId: fixture.book.id,
          contentRevision: fixture.book.contentRevision,
          annotations: fixture.library.annotationStore(fixture.book.id),
          decorations: fixture.library.decorationStore(
            fixture.book.id,
            images: fixture.images,
          ),
          decorationImages: images ?? fixture.images,
          onDictionary: onDictionary,
          decorationRules: fixture.library.decorationRuleStore(
            fixture.book.id,
            images: fixture.images,
          ),
          padding: _padding,
          overrides: const ReaderOverrides(),
          showPageFooter: false,
          onSessionReady: (session) => fixture.session = session,
        ),
      ),
    ),
  );
  await pumpReaderUntil(tester, find.byType(ReaderView));
}

Future<void> _selectText(WidgetTester tester, _Fixture fixture) async {
  final line = TextHitTester.lineBoxes(fixture.session.page!).first;
  final origin = tester.getTopLeft(find.byType(ReaderView));
  await tester.longPressAt(
    origin + _padding.topLeft + Offset(8, line.rect.center.dy),
  );
  await tester.pumpAndSettle();
  expect(find.byType(SelectionLayer), findsOneWidget);
}

Future<void> _savePreset(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('selection-action-decoration')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('decoration-editor-sheet')), findsOneWidget);
  await tester.tap(find.byKey(ValueKey('decoration-preset-$name')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('decoration-save')));
  await pumpReaderUntilComplete(
    tester,
    () =>
        _messages.contains('装饰已保存') &&
            find
                .byKey(const ValueKey('decoration-editor-sheet'))
                .evaluate()
                .isEmpty ||
        _messages.contains('装饰保存失败，请重试') ||
        _messages.contains('当前位置不支持标注'),
    description: '装饰保存结果',
  );
  expect(
    _messages,
    contains('装饰已保存'),
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .join(' / '),
  );
}

void main() {
  setUp(() {
    _messages.clear();
    ReaderUiDiagnostics.onEvent = (event, fields) {
      if (event == 'reader_ui_message') {
        _messages.add(fields['message'] as String);
      }
    };
  });
  tearDown(() => ReaderUiDiagnostics.onEvent = null);
  testWidgets('词典交付真实选区原文，关闭后恢复菜单且不写入批注', (tester) async {
    final fixture = await _fixture(tester, body: '<p>测试词典原文</p>');
    addTearDown(() => tester.runAsync(fixture.close));
    String? selected;
    final closing = Completer<void>();
    await _show(
      tester,
      fixture,
      onDictionary: (text) async {
        selected = text;
        await closing.future;
      },
    );
    await _selectText(tester, fixture);
    await tester.tap(find.byKey(const ValueKey('selection-action-dictionary')));
    await tester.pump();
    expect(selected, isNotEmpty);
    expect('测试词典原文'.contains(selected!), isTrue);
    expect(
      find.byKey(const ValueKey('selection-action-dictionary')),
      findsNothing,
    );
    closing.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('selection-action-dictionary')),
      findsOneWidget,
    );
    expect(
      await fixture.database.select(fixture.database.annotations).get(),
      isEmpty,
    );
    expect(fixture.session.pageTurns, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('首次开书内置规则关闭，保留原字号且不加载高亮图片', (tester) async {
    final fixture = await _fixture(
      tester,
      body: '<p>“前段</p><p>后段”旁白<span>「作者行内」</span></p>',
    );
    addTearDown(() => tester.runAsync(fixture.close));
    final images = _CountingImages(fixture.images);
    await _show(tester, fixture, images: images);
    await pumpReaderTask(tester, fixture.source.loadChapter(0));
    final lines = TextHitTester.lineBoxes(fixture.session.page!);
    expect(lines, isNotEmpty);
    expect(
      lines.every(
        (line) => line.slice.block.layout.runs.every(
          (run) => (run.style.fontSize - 16).abs() < .01,
        ),
      ),
      isTrue,
    );
    expect(images.loaded, isEmpty);
    expect(fixture.source.chapterLayoutCount, 1);
    expect(fixture.session.pageTurns, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('主动开启内置对话规则在正式排版前应用，留白字号与原文位置保留', (tester) async {
    final fixture = await _fixture(
      tester,
      body: '<p>“前段</p><p>后段”旁白<span>「作者行内」</span></p>',
    );
    addTearDown(() => tester.runAsync(fixture.close));
    await tester.runAsync(() async {
      final store = fixture.library.decorationRuleStore(
        fixture.book.id,
        images: fixture.images,
      )!;
      for (final rule in await store.listRules()) {
        await store.saveRule(rule.copyWith(enabled: true));
      }
    });
    await _show(tester, fixture);
    await pumpReaderUntilComplete(tester, () {
      final page = fixture.session.page;
      return page != null &&
          TextHitTester.lineBoxes(page).any(
            (line) => line.slice.block.layout.runs.any(
              (run) => (run.style.fontSize - 14.4).abs() < .01,
            ),
          );
    }, description: '默认规则排版');
    final anchors = await tester.runAsync(
      () => fixture.source.loadAnchorChapter(0),
    );
    expect(anchors!.blocks.last.ruleProtected, isNotEmpty);
    final page = fixture.session.page!;
    expect(TextHitTester.lineBoxes(page).first.rect.height, greaterThan(16));
    expect(page.slices.first.block.startCfi, isNotNull);
    expect(
      await fixture.database.select(fixture.database.decorations).get(),
      isEmpty,
    );
    expect(
      await fixture.database.select(fixture.database.annotations).get(),
      isEmpty,
    );
    expect(fixture.session.pageTurns, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final regex in [false, true]) {
    testWidgets('${regex ? '正则' : '手工'}四字点九在真实阅读页预留空间，保留邻字与完整边角', (
      tester,
    ) async {
      final fixture = await _fixture(tester, body: '<p>前文彻底消失后文</p>');
      addTearDown(() => tester.runAsync(fixture.close));
      final decoded = (await tester.runAsync(
        () async => ReaderDecorationImageCodec.decode(
          await File('assets/textures/paper.png').readAsBytes(),
        ),
      ))!;
      addTearDown(decoded.image.dispose);
      const requested = ReaderDecorationNineSlice();
      final bytes = (await tester.runAsync(
        () => ReaderDecorationImageCodec.encodeNinePatch(
          decoded.image,
          requested,
        ),
      ))!;
      final saved = (await tester.runAsync(
        () => ReaderDecorationImageCodec.decode(bytes),
      ))!;
      addTearDown(saved.image.dispose);
      final config = saved.nineSlice!;
      final path = (await tester.runAsync(
        () => fixture.images.saveNinePatch(bytes),
      ))!;
      final block = (await tester.runAsync(
        () => fixture.source.loadAnchorChapter(0),
      ))!.blocks.single;
      final start = block.cfiAt(2)!;
      final end = block.cfiAt(6, end: true)!;
      await tester.runAsync(() async {
        if (regex) {
          final store = fixture.library.decorationRuleStore(
            fixture.book.id,
            images: fixture.images,
          )!;
          final group = (await store.listGroups()).first;
          await store.saveRule(
            ReaderDecorationRule(
              id: 'four-character-bubble',
              groupId: group.id,
              pattern: '彻底消失',
              isRegex: true,
              style: ReaderDecorationRuleStyle(
                backgroundImagePath: path,
                backgroundImageFit: ReaderDecorationImageFit.nineSlice,
              ),
            ),
          );
        } else {
          await fixture.library
              .decorationStore(fixture.book.id, images: fixture.images)!
              .add(
                startCfi: start,
                endCfi: end,
                quote: '彻底消失',
                style: ReaderDecorationStyle(
                  backgroundImagePath: path,
                  backgroundImageFit: ReaderDecorationImageFit.nineSlice,
                ),
              );
        }
      });
      final images = _CountingImages(fixture.images);
      await _show(tester, fixture, images: images);
      await pumpReaderUntilComplete(
        tester,
        () => fixture.session.page!.slices.single.block.layout.runs.any(
          (run) => run.inlinePadding.horizontal > 0,
        ),
        description: '点九占位重排完成',
      );
      final page = fixture.session.page!;
      final line = TextHitTester.lineBoxes(page).single;
      final text = TextHitTester.selectionRects(
        line,
        2,
        6,
      ).single.shift(line.rect.topLeft);
      final bounds = config.imageRectFor(
        text,
        Size(decoded.image.width.toDouble(), decoded.image.height.toDouble()),
      );
      final before = TextHitTester.selectionRects(line, 0, 2).single;
      final after = TextHitTester.selectionRects(line, 6, 8).single;
      expect(
        bounds.left + 0.01,
        greaterThanOrEqualTo(line.rect.left + before.right),
      );
      expect(
        bounds.right - 0.01,
        lessThanOrEqualTo(line.rect.left + after.left),
      );
      expect(bounds.top, greaterThanOrEqualTo(-0.01));
      expect(bounds.bottom, lessThanOrEqualTo(page.usedHeight + 0.01));
      expect(line.slice.block.offsetForCfi(start), 2);
      expect(line.slice.block.offsetForCfi(end), 6);
      expect(images.loaded.where((p) => p == path), [path]);
      expect(
        await fixture.database.select(fixture.database.decorations).get(),
        hasLength(regex ? 0 : 1),
      );
      expect(
        await fixture.database.select(fixture.database.annotations).get(),
        isEmpty,
      );
      expect(fixture.session.pageTurns, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('正则点九图片规则从真实存储加载背景，不生成手工记录', (tester) async {
    final fixture = await _fixture(tester);
    addTearDown(() => tester.runAsync(fixture.close));
    final path = (await tester.runAsync(
      () async => fixture.images.import(
        await File('assets/textures/paper.png').readAsBytes(),
      ),
    ))!;
    final store = fixture.library.decorationRuleStore(
      fixture.book.id,
      images: fixture.images,
    )!;
    await tester.runAsync(() async {
      final group = (await store.listGroups()).first;
      await store.saveRule(
        ReaderDecorationRule(
          id: 'regex-image',
          groupId: group.id,
          pattern: '甲乙|丙丁',
          isRegex: true,
          style: ReaderDecorationRuleStyle(
            backgroundImagePath: path,
            backgroundImageFit: ReaderDecorationImageFit.nineSlice,
            backgroundImageNineSlice: const ReaderDecorationNineSlice(),
            backgroundOpacity: 0.5,
          ),
        ),
      );
    });
    final images = _CountingImages(fixture.images);
    await _show(tester, fixture, images: images);
    await pumpReaderUntilComplete(
      tester,
      () => images.loaded.contains(path),
      description: '正则规则图片解码',
    );
    expect(images.loaded.where((p) => p == path), [
      path,
    ], reason: '多个命中复用同一份图片');
    expect(fixture.session.page, isNotNull);
    expect(fixture.session.pageTurns, 0);
    expect(
      await fixture.database.select(fixture.database.decorations).get(),
      isEmpty,
    );
    expect(
      await fixture.database.select(fixture.database.annotations).get(),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('320dp 六按钮菜单保持紧凑顺序，词典提示后可直接全选并取消', (tester) async {
    final fixture = await _fixture(tester);
    addTearDown(() => tester.runAsync(fixture.close));
    await _show(tester, fixture);
    await _selectText(tester, fixture);
    final positions = <Offset>[];
    for (final action in [
      'copy',
      'mark',
      'thought',
      'decoration',
      'dictionary',
      'select-all',
    ]) {
      final finder = find.byKey(ValueKey('selection-action-$action'));
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.height, greaterThanOrEqualTo(44));
      positions.add(rect.center);
    }
    expect(positions.map((position) => position.dy).toSet(), hasLength(1));
    for (var index = 1; index < positions.length; index++) {
      expect(positions[index].dx, greaterThan(positions[index - 1].dx));
    }
    await tester.tap(find.byKey(const ValueKey('selection-action-dictionary')));
    await tester.pumpAndSettle();
    expect(_messages, contains('请在词典设置中配置释义服务'));
    expect(find.byKey(const ValueKey('selection-action-more')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('selection-action-select-all')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectionLayer>(find.byType(SelectionLayer))
          .selection
          .start
          .charOffset,
      0,
    );
    await tester.tapAt(
      tester.getRect(find.byType(ReaderView)).centerRight - const Offset(8, 0),
    );
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);
    expect(fixture.session.pageTurns, 0);
    expect(
      await fixture.database.select(fixture.database.annotations).get(),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('手工装饰经真实存储保存并在独立装饰页展示，背景不重排', (tester) async {
    final fixture = await _fixture(tester);
    addTearDown(() => tester.runAsync(fixture.close));
    await _show(tester, fixture);
    final original = fixture.session.page!.slices.first.block.layout;
    await _selectText(tester, fixture);
    await _savePreset(tester, 'sticky');
    expect(_messages, contains('装饰已保存'));
    final saved =
        (await fixture.library.decorationStore(fixture.book.id)!.list()).single;
    expect(saved.style.backgroundColor, 0xFFFFF3C4);
    expect(saved.style.borderLeft.width, 1);
    expect(fixture.session.page!.slices.first.block.layout, same(original));
    expect(
      await fixture.database.select(fixture.database.annotations).get(),
      isEmpty,
    );
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-entry-toc')));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('drawer-tab-decorations')).hitTestable(),
    );
    await tester.tap(find.byKey(const ValueKey('drawer-tab-decorations')));
    await pumpReaderUntil(tester, find.byType(ReaderDecorationPanel));
    expect(find.byType(ReaderDecorationPanel), findsOneWidget);
    expect(find.byKey(ValueKey('decoration-row-${saved.id}')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('decoration-rules-entry')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('drawer-tab-highlights')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('字体装饰保存后重排，并回到原 CFI 所在文字', (tester) async {
    final fixture = await _fixture(tester);
    addTearDown(() => tester.runAsync(fixture.close));
    await _show(tester, fixture);
    final original = fixture.session.page!.slices.first.block.layout;
    final anchor = fixture.session.currentCfi!;
    await _selectText(tester, fixture);
    await _savePreset(tester, 'emphasis');
    final item =
        (await fixture.library.decorationStore(fixture.book.id)!.list()).single;
    expect(item.style.fontWeight, 700);
    final layout = fixture.session.page!.slices.first.block.layout;
    expect(layout, isNot(same(original)));
    expect(layout.runs.any((run) => run.style.fontWeight == 700), isTrue);
    expect(cfiBase(fixture.session.currentCfi!), cfiBase(anchor));
    expect(_messages, contains('装饰已保存'));
    expect(tester.takeException(), isNull);
  });
}
