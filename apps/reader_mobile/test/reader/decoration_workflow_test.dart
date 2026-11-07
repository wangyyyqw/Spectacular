import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_store.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/reader/reader_decoration_image_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/panels/decoration_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/selection/selection_layer.dart';

import '../support/reader_pump.dart';
import 'support/css_chapter_book.dart';

const _padding = EdgeInsets.fromLTRB(24, 40, 24, 40);

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

Future<_Fixture> _fixture(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final directory = Directory.systemTemp.createTempSync('decoration-flow-');
    final database = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: database,
      directoryProvider: () async => directory,
    );
    final bytes = buildCssChapterBook(
      body: '<h1>标题</h1><p>${'甲乙丙丁戊己庚辛壬癸' * 60}</p>',
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

Future<void> _show(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(320, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
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
          decorationImages: fixture.images,
          decorationRules: fixture.library.decorationRuleStore(fixture.book.id),
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
        find.text('装饰已保存').evaluate().isNotEmpty &&
            find
                .byKey(const ValueKey('decoration-editor-sheet'))
                .evaluate()
                .isEmpty ||
        find.text('装饰保存失败，请重试').evaluate().isNotEmpty ||
        find.text('当前位置不支持标注').evaluate().isNotEmpty,
    description: '装饰保存结果',
  );
  expect(
    find.text('装饰已保存'),
    findsOneWidget,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .join(' / '),
  );
}

void main() {
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

  testWidgets('320dp 六按钮菜单可换行，更多可收起，词典提示后可取消选区', (tester) async {
    final fixture = await _fixture(tester);
    addTearDown(() => tester.runAsync(fixture.close));
    await _show(tester, fixture);
    await _selectText(tester, fixture);
    final positions = <Offset>[];
    for (final action in [
      'mark',
      'thought',
      'decoration',
      'copy',
      'dictionary',
      'more',
    ]) {
      final finder = find.byKey(ValueKey('selection-action-$action'));
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.height, greaterThanOrEqualTo(44));
      positions.add(rect.center);
    }
    expect(positions[3].dy, greaterThan(positions[0].dy));
    await tester.tap(find.byKey(const ValueKey('selection-action-dictionary')));
    await tester.pumpAndSettle();
    expect(find.text('词典功能开发中'), findsOneWidget);
    final more = find.byKey(const ValueKey('selection-action-more'));
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('selection-action-select-all')),
      findsOneWidget,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('selection-action-select-all')),
      findsNothing,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-action-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);
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
    expect(find.text('装饰已保存'), findsOneWidget);
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
    expect(find.text('装饰已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
