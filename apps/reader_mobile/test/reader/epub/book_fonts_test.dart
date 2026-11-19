import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/text/font_coverage.dart';
import 'package:reader_core/epub/chapter/book_fonts.dart';
import 'package:reader_core/epub/chapter/book_resources.dart';

const _files = <String, String>{
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="content.opf"
media-type="application/oebps-package+xml"/></rootfiles></container>''',
  'content.opf': '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">book-font-view</dc:identifier><dc:title>字体视图</dc:title>
<dc:language>zh</dc:language></metadata><manifest>
<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine><itemref idref="c"/></spine></package>''',
  'c.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>正文</p></body></html>',
};

Future<EpubDocumentImpl> _document({Uint8List? font}) async {
  final archive = Archive();
  for (final entry in _files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  if (font != null) {
    archive.addFile(ArchiveFile('font.otf', font.length, font));
  }
  return (await openEpub(
    ZipEncoder().encodeBytes(archive),
    verifyCrc: false,
  )).document!;
}

class _GatedResources extends BookResources {
  _GatedResources(super.document);

  final gate = Completer<void>();
  int reads = 0;

  @override
  Future<Uint8List?> readFont(String url) async {
    reads += 1;
    await gate.future;
    return super.readFont(url);
  }
}

List<CssFontFace> _local(String family, String local) => [
  CssFontFace(family: family, sources: [CssFontSource.local(local)]),
];

void _registerUserCoverage(String family) {
  final bytes = File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytesSync();
  FontCoverageRegistry.register(family, FontCoverage.parse(bytes)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('只有真实族映射变化通知失效，冻结视图跨增量注册和关闭保持不变', () async {
    final resources = BookResources(await _document());
    addTearDown(resources.close);
    final changes = <Set<String>>[];
    final fonts = BookFonts(resources, onFontsChanged: changes.add);
    addTearDown(fonts.close);
    final empty = fonts.freeze();
    expect(fonts.freeze(), same(empty));
    final bookDependency = empty.userFontDependency({'more', 'alias'});
    await fonts.ensure(_local('Alias', '宋体'));
    final frozen = fonts.freeze();
    final alias = fonts.engineFamilies['alias']!;
    expect(
      ComputedStyle({'font-family': alias}).fontFamily,
      FontFamilyAliases.song,
    );
    expect(frozen, isNot(same(empty)));
    expect(fonts.freeze(), same(frozen));
    expect(
      frozen.userFontEnvironmentDependency,
      empty.userFontEnvironmentDependency,
    );
    await fonts.ensure(_local('Alias', '宋体'));
    expect(fonts.revision, 1);
    expect(changes, [
      {'alias'},
    ]);
    expect(fonts.engineFamilies, {'alias': alias});
    expect(fonts.embeddedEngineFamilies, isEmpty);
    expect(() => fonts.engineFamilies.clear(), throwsUnsupportedError);
    expect(
      () => fonts.embeddedEngineFamilies.add('other'),
      throwsUnsupportedError,
    );
    await fonts.ensure(_local('More', '黑体'));
    expect(empty.dependency({'alias'}), 'alias=alias');
    expect(frozen.dependency({'more', 'alias'}), 'alias=$alias,more=more');
    expect(
      fonts.freeze().dependency({'more', 'alias'}),
      'alias=$alias,more=${fonts.engineFamilies['more']}',
    );
    expect(
      fonts.freeze().userFontDependency({'alias', 'more'}),
      bookDependency,
      reason: '书内别名逐章登记只影响章节依赖，书级键不依赖登记顺序',
    );
    fonts.close();
    await fonts.ensure(_local('Closed', '宋体'));
    expect(changes, [
      {'alias'},
      {'more'},
    ]);
    expect(fonts.engineFamilies, isEmpty);
    expect(frozen.dependency({'alias'}), 'alias=$alias');
    expect(resources.isClosed, isFalse, reason: '字体服务不能关闭共享归档');
  });

  test('字体声明改写保留简写语义和 important，local 别名不阻止自定义字体', () async {
    final resources = BookResources(await _document());
    addTearDown(resources.close);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    addTearDown(fonts.close);
    final declarations = CssParser.parseInlineDeclarations(
      'font: italic bold 21px/1.4 Alias, serif !important; color: #123456',
    );
    expect(
      fonts.freeze().rewriteDeclarations(declarations),
      same(declarations),
    );
    await fonts.ensure(_local('Alias', '宋体'));
    final view = fonts.freeze();
    final rewritten = view.rewriteDeclarations(declarations);
    final computed = ComputedStyle({
      for (final item in rewritten) item.property: item.value,
    });
    expect(computed.fontFamilies, [fonts.engineFamilies['alias'], 'serif']);
    expect(computed.fontFamily, FontFamilyAliases.song);
    expect(computed.fontSize, 21);
    expect(computed.fontWeight, 700);
    expect(computed.values['font-style'], 'italic');
    expect(
      rewritten
          .where((item) => item.property != 'color')
          .every((item) => item.important),
      isTrue,
    );
    expect(rewritten.last, same(declarations.last));
    final selected = view.applyCustomFont(
      computed,
      const ReaderOverrides(fontFamily: 'user_view'),
    );
    expect(selected.fontFamily, 'user_view');
    expect(selected.fontSize, 21);
    expect(view.hasGlyph('楷体', 0x4E2D), isFalse);
    expect(view.hasGlyph('unknown', 0x4E2D), isTrue);
  });

  test('并发字体请求等待同次注册，内嵌覆盖和自定义字体策略使用冻结结果', () async {
    final font = File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytesSync();
    final resources = _GatedResources(await _document(font: font));
    addTearDown(resources.close);
    final changes = <Set<String>>[];
    final fonts = BookFonts(resources, onFontsChanged: changes.add);
    addTearDown(fonts.close);
    final faces = CssParser.parse(
      '@font-face {font-family: fixture; src: url("font.otf");}',
    ).fontFaces;
    final waiting = Future.wait([
      fonts.ensure(faces),
      fonts.ensure(faces),
      fonts.ensure(faces),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(resources.reads, 1);
    expect(fonts.engineFamilies, isEmpty);
    resources.gate.complete();
    await waiting;
    expect(resources.reads, 1);
    expect(changes, [
      {'fixture'},
    ]);
    final engine = fonts.engineFamilies['fixture']!;
    final frozen = fonts.freeze();
    expect(fonts.embeddedEngineFamilies, {engine});
    expect(frozen.hasGlyph(engine, 0x41), isTrue);
    expect(frozen.hasGlyph(engine, 0xE000), isFalse);
    final style = ComputedStyle({
      'font-family': 'fixture, serif',
      'font-size': '30px',
    });
    const selected = ReaderOverrides(fontFamily: 'user_view');
    expect(frozen.applyCustomFont(style, selected).fontFamilies, [
      engine,
      'serif',
    ]);
    expect(
      frozen
          .applyCustomFont(
            style,
            selected.copyWith(overrideEmbeddedFonts: true),
          )
          .fontFamily,
      'user_view',
    );
    fonts.close();
    expect(frozen.dependency({'fixture'}), 'fixture=$engine');
    expect(frozen.hasGlyph(engine, 0xE000), isFalse);
  });

  test('同族反复查询按各字符覆盖返回，不复用前一字符的结果', () async {
    final resources = BookResources(await _document());
    addTearDown(resources.close);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    addTearDown(fonts.close);
    const family = 'user_glyph_strategy_view';
    _registerUserCoverage(family);
    final view = fonts.freeze();
    for (var pass = 0; pass < 3; pass++) {
      expect(view.hasGlyph(family, 0x41), isTrue);
      expect(view.hasGlyph(family, 0xE000), isFalse);
      expect(view.hasGlyph(family, 0x4E2D), isTrue);
    }
  });

  test('用户覆盖按原始族名精确命中，优先于规范化别名', () async {
    final resources = BookResources(await _document());
    addTearDown(resources.close);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    addTearDown(fonts.close);
    _registerUserCoverage('  KaI  ');
    _registerUserCoverage('  SeRiF  ');
    final view = fonts.freeze();
    for (var pass = 0; pass < 2; pass++) {
      expect(view.hasGlyph('  KaI  ', 0x41), isTrue);
      expect(view.hasGlyph('kai', 0x41), isFalse);
      expect(view.hasGlyph('  SeRiF  ', 0xE000), isFalse);
      expect(view.hasGlyph('serif', 0xE000), isTrue);
    }
  });

  test('大量字体族切换后，覆盖结果和缺省回退策略保持一致', () async {
    final resources = BookResources(await _document());
    addTearDown(resources.close);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    addTearDown(fonts.close);
    const family = 'user_glyph_eviction_view';
    _registerUserCoverage(family);
    final view = fonts.freeze();
    final expected = {
      family: [true, false],
      '楷体': [false, false],
      'builtin_kai': [false, false],
      'unknown': [true, true],
      'builtin_song': [true, true],
    };
    void verify() {
      for (final entry in expected.entries) {
        expect(
          [view.hasGlyph(entry.key, 0x41), view.hasGlyph(entry.key, 0xE000)],
          entry.value,
          reason: entry.key,
        );
      }
    }

    verify();
    for (var index = 0; index < 80; index++) {
      expect(view.hasGlyph('unknown_family_$index', 0x41), isTrue);
    }
    verify();
  });

  test('在途关闭不回填字体状态或通知布局失效', () async {
    final resources = _GatedResources(await _document());
    final changes = <Set<String>>[];
    final fonts = BookFonts(resources, onFontsChanged: changes.add);
    final faces = CssParser.parse(
      '@font-face {font-family: closing; src: url("font.otf");}',
    ).fontFaces;
    final waiting = fonts.ensure(faces);
    await Future<void>.delayed(Duration.zero);
    expect(resources.reads, 1);
    fonts.close();
    resources.close();
    resources.gate.complete();
    await waiting;
    expect(fonts.engineFamilies, isEmpty);
    expect(fonts.embeddedEngineFamilies, isEmpty);
    expect(changes, isEmpty);
  });

  test('作者或行内引用的用户字体注册后依赖改变，其他族保持稳定', () async {
    final resources = BookResources(await _document());
    addTearDown(resources.close);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    addTearDown(fonts.close);
    const family = 'user_authored_font_view';
    final frozen = fonts.freeze();
    final missing = frozen.dependency({family});
    final missingBookDependency = frozen.userFontDependency({family});
    final previousEnvironment = frozen.userFontEnvironmentDependency;
    expect(frozen.hasGlyph(family, 0xE000), isTrue);
    _registerUserCoverage(family);
    final registered = fonts.freeze();
    expect(registered, isNot(same(frozen)));
    expect(registered.dependency({family}), isNot(missing));
    expect(
      registered.userFontDependency({family}),
      isNot(missingBookDependency),
    );
    expect(registered.dependency({family}), contains('availability=未确认'));
    expect(
      registered.userFontEnvironmentDependency,
      isNot(previousEnvironment),
    );
    expect(registered.userFontEnvironmentDependency, contains('$family='));
    expect(registered.dependency({'serif'}), frozen.dependency({'serif'}));
    expect(frozen.dependency({family}), missing, reason: '注册不修改已有作业快照');
    expect(registered.hasGlyph(family, 0x41), isTrue);
    expect(registered.hasGlyph(family, 0xE000), isFalse);
    expect(frozen.hasGlyph(family, 0xE000), isTrue, reason: '旧视图保留已查询的覆盖策略');
    expect(frozen.hasGlyph(family, 0xE001), isTrue, reason: '旧视图查询新字符仍使用旧覆盖');
    _registerUserCoverage(family);
    expect(fonts.freeze(), same(registered), reason: '重复登记相同覆盖不复制字体视图');
  });

  test('已注册用户族的实际加载失败分隔回退配置，已有冻结视图不受影响', () async {
    final resources = BookResources(await _document());
    addTearDown(resources.close);
    final changes = <Set<String>>[];
    final fonts = BookFonts(resources, onFontsChanged: changes.add);
    addTearDown(fonts.close);
    const family = 'user_available_font_view';
    _registerUserCoverage(family);
    final unknown = fonts.freeze();
    expect(fonts.setUserFontAvailability(family, true), isTrue);
    expect(fonts.setUserFontAvailability(family, true), isFalse);
    final ready = fonts.freeze();
    expect(ready, isNot(same(unknown)));
    expect(fonts.freeze(), same(ready));
    final readyKey = ready.dependency({family});
    final readyBookDependency = ready.userFontDependency({family});
    expect(readyKey, isNot(unknown.dependency({family})));
    expect(readyKey, contains('availability=可用'));
    expect(fonts.setUserFontAvailability(family, false), isTrue);
    final fallback = fonts.freeze();
    expect(fallback, isNot(same(ready)));
    expect(fallback.dependency({family}), isNot(readyKey));
    expect(fallback.userFontDependency({family}), isNot(readyBookDependency));
    expect(fallback.userFontDependency({family}), contains('availability=回退'));
    expect(fallback.dependency({family}), contains('availability=回退'));
    expect(FontCoverageRegistry.covers(family, 0x41), isTrue);
    expect(fallback.hasGlyph(family, 0x41), isTrue, reason: '作者的实际引用仍由引擎注册决定');
    expect(ready.dependency({family}), readyKey);
    expect(
      fallback.userFontEnvironmentDependency,
      ready.userFontEnvironmentDependency,
    );
    expect(changes, isEmpty, reason: '可用性登记不触发全局重排');
    fonts.close();
    expect(fonts.setUserFontAvailability(family, true), isFalse);
  });
}
