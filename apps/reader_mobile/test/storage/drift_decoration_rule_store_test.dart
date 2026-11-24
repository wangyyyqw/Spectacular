import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/reader/reader_decoration_image_store.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/decoration_style.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/decorations/decoration_rule_defaults.dart';

import '../library/fixtures/revision_epub.dart';

ReaderDecorationRule _rule(String id, String groupId, {int order = 0}) =>
    ReaderDecorationRule(
      id: id,
      groupId: groupId,
      pattern: '中文',
      sortOrder: order,
      style: const ReaderDecorationRuleStyle(color: 0xff123456),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase db;
  late LibraryStore library;
  late BookEntry book;
  late ReaderDecorationImages images;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('decoration-rules-');
    images = ReaderDecorationImages(directoryProvider: () async => directory);
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    book = await library.importBytes(buildRevisionTestEpub());
  });

  tearDown(() async {
    await db.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('默认组幂等创建，本书和全局隔离，默认组固定末尾', () async {
    final store = library.decorationRuleStore(book.id, images: images)!;
    final defaults = await store.listGroups();
    expect(defaults, hasLength(2));
    expect(defaults.every((group) => group.isDefault), isTrue);
    expect(await store.listGroups(), hasLength(2));
    final localDefault = defaults.singleWhere((group) => group.bookId != null);
    await store.saveGroup(
      ReaderDecorationRuleGroup(id: 'one', bookId: book.id, name: '第一组'),
    );
    await store.saveGroup(
      ReaderDecorationRuleGroup(
        id: 'two',
        bookId: book.id,
        name: '第二组',
        sortOrder: 1,
      ),
    );
    await store.reorderGroups([localDefault.id, 'two', 'one']);
    final local = (await store.listGroups())
        .where((group) => group.bookId != null)
        .toList();
    expect(local.map((group) => group.id), ['two', 'one', localDefault.id]);
    await expectLater(
      store.removeGroup(localDefault.id),
      throwsFormatException,
    );
    final other = await library.importBytes(
      buildRevisionTestEpub(title: '规则另一书'),
    );
    final otherStore = library.decorationRuleStore(other.id, images: images)!;
    final groups = await otherStore.listGroups();
    expect(groups, hasLength(2));
    expect(groups.any((group) => group.id == 'one'), isFalse);
    await expectLater(
      otherStore.saveGroup(
        ReaderDecorationRuleGroup(id: 'one', bookId: other.id, name: '越界'),
      ),
      throwsFormatException,
    );
  });

  test('内置规则仅初始化一次，样式引用可编辑并保留本书全局选择', () async {
    final store = library.decorationRuleStore(book.id, images: images)!;
    final preferences = store as ReaderDecorationRulePreferences;
    final rules = await store.listRules();
    expect(rules.map((r) => r.id), [
      'double_quote_dialogue',
      'single_quote_phrase',
    ]);
    expect(rules.every((rule) => !rule.enabled), isTrue);
    expect(rules.first.style.typography.paddingLeft, 16);
    await store.removeRule(rules.first.id);
    expect(await store.listRules(), hasLength(1));
    await preferences.saveStyle(
      ReaderDecorationNamedStyle(
        id: readerDecorationBuiltInStyles.last.id,
        name: '夜间颜色',
        style: const ReaderDecorationRuleStyle(color: 0xFF112233),
        builtIn: true,
      ),
    );
    expect(
      (await store.listRules()).single.style.forTheme(true).color,
      0xFF112233,
    );
    await preferences.saveGlobalRuleSelection({});
    expect(await preferences.loadGlobalRuleSelection(), isEmpty);
    await preferences.saveGlobalRuleSelection(null);
    expect(await preferences.loadGlobalRuleSelection(), isNull);
    expect(await store.listRules(), hasLength(1));
  });

  test('重开书与新书初始化保留用户已开启的内置全局规则', () async {
    final store = library.decorationRuleStore(book.id, images: images)!;
    final rules = await store.listRules();
    await store.saveRule(rules.first.copyWith(enabled: true));
    final reopened = library.decorationRuleStore(book.id, images: images)!;
    final reloaded = await reopened.listRules();
    expect(reloaded.first.enabled, isTrue);
    expect(reloaded.last.enabled, isFalse);
    final other = await library.importBytes(
      buildRevisionTestEpub(title: '默认开关另一书'),
    );
    final otherRules = await library
        .decorationRuleStore(other.id, images: images)!
        .listRules();
    expect(otherRules, hasLength(2));
    expect(otherRules.first.enabled, isTrue);
    expect(otherRules.last.enabled, isFalse);
  });

  test('删除非默认组把规则移到同作用域默认组末尾，保留样式与排序', () async {
    final store = library.decorationRuleStore(book.id, images: images)!;
    final target = (await store.listGroups()).singleWhere(
      (group) => group.bookId != null,
    );
    await store.saveGroup(
      ReaderDecorationRuleGroup(id: 'source', bookId: book.id, name: '来源组'),
    );
    await store.saveRule(_rule('existing', target.id, order: 7));
    await store.saveRule(_rule('second', 'source', order: 2));
    await store.saveRule(_rule('first', 'source', order: 1));
    await store.removeGroup('source');
    expect(
      (await store.listGroups()).any((group) => group.id == 'source'),
      isFalse,
    );
    final rules = (await store.listRules())
        .where((r) => r.groupId == target.id)
        .toList();
    expect(rules.map((rule) => rule.id), ['existing', 'first', 'second']);
    expect(rules.every((rule) => rule.groupId == target.id), isTrue);
    expect(rules.last.style.color, 0xff123456);
    await store.reorderRules(target.id, ['second', 'existing', 'first']);
    expect(
      (await store.listRules())
          .where((r) => r.groupId == target.id)
          .map((rule) => rule.id),
      ['second', 'existing', 'first'],
    );
    await expectLater(
      store.reorderRules(target.id, ['first', 'first']),
      throwsFormatException,
    );
  });

  test('保存拦截无效正则，编辑开关与删除，不保存匹配结果', () async {
    final store = library.decorationRuleStore(book.id, images: images)!;
    final group = (await store.listGroups()).first;
    await expectLater(
      store.saveRule(
        _rule('bad', group.id).copyWith(pattern: '[', isRegex: true),
      ),
      throwsFormatException,
    );
    expect((await store.listRules()).any((r) => r.id == 'bad'), isFalse);
    await store.saveRule(
      _rule('ok', group.id).copyWith(pattern: r'\p{L}+', isRegex: true),
    );
    await store.saveRule(
      _rule('ok', group.id).copyWith(enabled: false, name: '停用文字'),
    );
    final rules = (await store.listRules()).where((r) => r.id == 'ok').toList();
    expect(rules, hasLength(1));
    expect(rules.single.enabled, isFalse);
    expect(rules.single.name, '停用文字');
    expect(await db.select(db.decorations).get(), isEmpty);
    expect(await db.select(db.annotations).get(), isEmpty);
    await store.removeRule('ok');
    expect((await store.listRules()).any((r) => r.id == 'ok'), isFalse);
  });

  test('彻底删书级联清理本书组与规则，不触碰全局规则', () async {
    final store = library.decorationRuleStore(book.id, images: images)!;
    final groups = await store.listGroups();
    final global = groups.singleWhere((group) => group.bookId == null);
    final local = groups.singleWhere((group) => group.bookId != null);
    await store.saveRule(_rule('global', global.id));
    await store.saveRule(_rule('local', local.id));
    await (db.delete(
      db.books,
    )..where((table) => table.uuid.equals(book.id))).go();
    expect((await db.select(db.decorationRules).get()).map((row) => row.id), [
      'global',
    ]);
    expect(
      (await db.select(db.decorationRuleGroups).get()).map((row) => row.id),
      [global.id],
    );
  });

  test('自动规则高亮与点九配置完整落库重读，不产生手工装饰或标注', () async {
    final store = library.decorationRuleStore(book.id, images: images)!;
    final group = (await store.listGroups()).first;
    const style = ReaderDecorationRuleStyle(
      backgroundImagePath: '/local/bubble.png',
      backgroundImageFit: ReaderDecorationImageFit.nineSlice,
      backgroundImageNineSlice: ReaderDecorationNineSlice(scale: 1.2),
      highlight: ReaderDecorationHighlight(
        style: ReaderAnnotationStyle.wavyUnderline,
        color: 0xFF12AB34,
        opacity: 0.6,
        strokeWidth: 2.5,
      ),
    );
    await store.saveRule(_rule('highlight', group.id).copyWith(style: style));
    final reloaded = library.decorationRuleStore(book.id, images: images)!;
    expect(
      (await reloaded.listRules())
          .singleWhere((r) => r.id == 'highlight')
          .style
          .toJson(),
      style.toJson(),
    );
    expect(await db.select(db.decorations).get(), isEmpty);
    expect(await db.select(db.annotations).get(), isEmpty);
  });
}
