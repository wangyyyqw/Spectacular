import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:spectacular_epub_tools/src/features/decrypt/decrypt.dart';
import 'package:spectacular_epub_tools/src/features/encrypt/encrypt.dart';
import 'package:spectacular_epub_tools/src/features/encrypt_decrypt_base/encrypt_decrypt_base.dart';
import 'package:spectacular_epub_tools/src/features/encrypt_font/encrypt_font.dart';
import 'package:spectacular_epub_tools/src/features/font_subset/font_subset.dart';
import 'package:spectacular_epub_tools/src/features/font_subset/harfbuzz_subsetter.dart';
import 'package:spectacular_epub_tools/src/features/image_watermark/image_watermark.dart';
import 'package:spectacular_epub_tools/src/features/img_compress/img_compress.dart';
import 'package:spectacular_epub_tools/src/features/img_to_webp/img_to_webp.dart';
import 'package:spectacular_epub_tools/src/features/list_font_targets/list_font_targets.dart';
import 'package:spectacular_epub_tools/src/features/ttf_font_encryptor/ttf_font_encryptor.dart';
import 'package:spectacular_epub_tools/src/features/ttf_subsetter/ttf_subsetter.dart';
import 'package:spectacular_epub_tools/src/features/webp_to_img/webp_to_img.dart';
import 'package:xml/xml.dart';

import 'support/media_fixture.dart';

late Directory _temporary;

String _path(String name) => p.join(_temporary.path, name);

void main() {
  setUp(() async {
    _temporary = await Directory.systemTemp.createTemp('media_tools_');
  });
  tearDown(() => _temporary.delete(recursive: true));

  test('压缩真实图片并回写 OPF、XHTML、CSS 引用', _testCompression);
  for (final format in [img.Format.uint8, img.Format.uint16]) {
    test('透明 PNG 压缩保留全部像素：${format.name}', () => _testTransparency(format));
  }
  test('压缩保持 GIF、APNG 动画的原始数据', _testAnimatedCompression);
  test('隐形水印可读取 UTF-8 文本并保留透明度', _testWatermark);
  test('本地 cwebp 转换 JPG、PNG、BMP，WebP 可转回图片', _testWebpRoundTrip);
  test('缺少 cwebp 明确报错且不生成输出', _testMissingCwebp);
  test('WebP 转图片保持动图原件', _testAnimatedWebp);
  for (final extension in ['ttf', 'otf']) {
    test('字体子集实际保留 $extension 的 GSUB、轮廓和排版', () => _testFontSubset(extension));
  }
  test('HarfBuzz 原生资产在后台 isolate 可用', _testBackgroundSubset);
  for (final codePoint in [66, 0x20000]) {
    test('TTF 回退保留 $codePoint 的复合字形和校验和', () => _testTtfFallback(codePoint));
  }
  test('字体加密保留明文 cmap、影子字形和有效校验和', _testFontEncryption);
  test('字体目标实际存在，定向加密不损坏未选章节', _testSelectedFontEncryption);
  test('名称加密、解密精确还原资源和各目录引用', _testNameRoundTrip);
  test('兼容解密没有还原映射的旧名称混淆 EPUB', _testLegacyNames);
}

Future<void> _testCompression() async {
  final image = mediaImage();
  final archive = mediaEpub(
    resources: {
      'OEBPS/images/opaque.png': img.encodePng(image, level: 0),
      'OEBPS/images/photo.jpeg': img.encodeJpg(image, quality: 100),
    },
    body:
        '<img src="../images/opaque.png?size=1#crop"/>'
        '<img src="../images/photo.jpeg"/>',
    stylesheet: 'body { background: url("../images/opaque.png"); }',
  );
  await writeMediaEpub(_path('input.epub'), archive);
  final log = await ImgCompressOperation.execute(
    epubPath: _path('input.epub'),
    outputPath: _path('output.epub'),
    jpegQuality: 60,
  );
  expect(log, contains('错误 0 张'));
  final output = await readMediaEpub(_path('output.epub'));
  expect(output.findFile('OEBPS/images/opaque.png'), isNull);
  for (final name in ['opaque.jpg', 'photo.jpg']) {
    final decoded = img.decodeJpg(
      output.findFile('OEBPS/images/$name')!.content,
    );
    expect((decoded!.width, decoded.height), (96, 80));
  }
  expect(
    mediaText(output, 'OEBPS/text/ch1.xhtml'),
    contains('opaque.jpg?size=1#crop'),
  );
  expect(mediaText(output, 'OEBPS/styles/style.css'), contains('opaque.jpg'));
  final opf = XmlDocument.parse(mediaText(output, 'OEBPS/content.opf'));
  final item = opf
      .findAllElements('item', namespaceUri: '*')
      .firstWhere((item) => item.getAttribute('href') == 'images/opaque.jpg');
  expect(item.getAttribute('media-type'), 'image/jpeg');
}

Future<void> _testTransparency(img.Format format) async {
  final original = mediaImage(transparent: true, format: format);
  await writeMediaEpub(
    _path('input.epub'),
    mediaEpub(
      resources: {'OEBPS/images/alpha.png': img.encodePng(original, level: 0)},
    ),
  );
  await ImgCompressOperation.execute(
    epubPath: _path('input.epub'),
    outputPath: _path('output.epub'),
  );
  final output = await readMediaEpub(_path('output.epub'));
  final decoded = img.decodePng(
    output.findFile('OEBPS/images/alpha.png')!.content,
  )!;
  expect(decoded.format, original.format);
  expect(decoded.getBytes(), orderedEquals(original.getBytes()));
  expect(output.findFile('OEBPS/images/alpha.jpg'), isNull);
}

Uint8List _animatedPng() {
  final image = mediaImage()..frameDuration = 100;
  image.addFrame(mediaImage(transparent: true)..frameDuration = 200);
  return img.encodePng(image);
}

Future<void> _testAnimatedCompression() async {
  final animation = mediaImage()..frameDuration = 100;
  animation.addFrame(mediaImage(transparent: true)..frameDuration = 200);
  final resources = {
    'OEBPS/images/animation.gif': img.encodeGif(animation),
    'OEBPS/images/animation.png': _animatedPng(),
  };
  expect(img.decodePng(resources['OEBPS/images/animation.png']!)!.numFrames, 2);
  expect(img.decodeGif(resources['OEBPS/images/animation.gif']!)!.numFrames, 2);
  await writeMediaEpub(_path('input.epub'), mediaEpub(resources: resources));
  await ImgCompressOperation.execute(
    epubPath: _path('input.epub'),
    outputPath: _path('output.epub'),
  );
  final output = await readMediaEpub(_path('output.epub'));
  for (final entry in resources.entries) {
    expect(output.findFile(entry.key)!.content, orderedEquals(entry.value));
  }
}

Future<void> _testWatermark() async {
  final source = mediaImage(transparent: true);
  await writeMediaEpub(
    _path('input.epub'),
    mediaEpub(
      resources: {
        'OEBPS/images/alpha.png': img.encodePng(source),
        'OEBPS/images/photo.jpg': img.encodeJpg(mediaImage()),
      },
      body: '<img src="../images/photo.jpg"/><img src="../images/alpha.png"/>',
    ),
  );
  final log = await ImageWatermarkOperation.embed(
    epubPath: _path('input.epub'),
    outputPath: _path('output.epub'),
    watermarkText: '本地水印：测试 🌿',
  );
  expect(log, contains('写入 2 张'));
  expect(
    await ImageWatermarkOperation.inspect(epubPath: _path('output.epub')),
    contains('找到 2 张'),
  );
  expect(
    await ImageWatermarkOperation.inspect(epubPath: _path('output.epub')),
    contains('本地水印：测试 🌿'),
  );
  final output = await readMediaEpub(_path('output.epub'));
  final decoded = img.decodePng(
    output.findFile('OEBPS/images/alpha.png')!.content,
  )!;
  expect(
    decoded.map((pixel) => pixel.a).toList(),
    orderedEquals(source.map((pixel) => pixel.a).toList()),
  );
  expect(
    img.decodePng(output.findFile('OEBPS/images/photo.png')!.content),
    isNotNull,
  );
  expect(mediaText(output, 'OEBPS/text/ch1.xhtml'), contains('photo.png'));
  final opf = XmlDocument.parse(mediaText(output, 'OEBPS/content.opf'));
  expect(
    opf
        .findAllElements('item', namespaceUri: '*')
        .where((item) => item.getAttribute('href') == 'images/photo.png')
        .single
        .getAttribute('media-type'),
    'image/png',
  );
}

Future<Archive> _convertWebpFixtures() async {
  await writeMediaEpub(
    _path('input.epub'),
    mediaEpub(
      resources: {
        'OEBPS/images/photo.jpg': img.encodeJpg(mediaImage()),
        'OEBPS/images/alpha.png': img.encodePng(mediaImage(transparent: true)),
        'OEBPS/images/bitmap.bmp': img.encodeBmp(mediaImage()),
        'OEBPS/images/animation.png': _animatedPng(),
      },
      body: '<img src="../images/alpha.png"/><img src="../images/bitmap.bmp"/>',
      stylesheet: 'body { background: url("../images/photo.jpg"); }',
    ),
  );
  final log = await ImgToWebpOperation.execute(
    epubPath: _path('input.epub'),
    outputPath: _path('webp.epub'),
  );
  expect(log, contains('转换 3 张'));
  expect(log, contains('跳过 1 张'));
  expect(log, contains('错误 0 张'));
  return readMediaEpub(_path('webp.epub'));
}

Future<void> _testWebpRoundTrip() async {
  final converted = await _convertWebpFixtures();
  for (final name in ['photo', 'alpha', 'bitmap']) {
    final bytes = converted.findFile('OEBPS/images/$name.webp')!.content;
    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    final decoded = img.decodeWebP(bytes)!;
    expect((decoded.width, decoded.height), (96, 80));
  }
  final alpha = img.decodeWebP(
    converted.findFile('OEBPS/images/alpha.webp')!.content,
  )!;
  expect(
    alpha.map((pixel) => pixel.a).toList(),
    orderedEquals(
      mediaImage(transparent: true).map((pixel) => pixel.a).toList(),
    ),
  );
  expect(
    mediaText(converted, 'OEBPS/styles/style.css'),
    contains('photo.webp'),
  );
  expect(mediaText(converted, 'OEBPS/text/ch1.xhtml'), contains('bitmap.webp'));
  final log = await WebpToImgOperation.execute(
    epubPath: _path('webp.epub'),
    outputPath: _path('restored.epub'),
  );
  expect(log, contains('转换 3 张'));
  final restored = await readMediaEpub(_path('restored.epub'));
  expect(
    img.decodePng(restored.findFile('OEBPS/images/alpha.png')!.content),
    isNotNull,
  );
  for (final name in ['photo', 'bitmap']) {
    expect(
      img.decodeJpg(restored.findFile('OEBPS/images/$name.jpg')!.content),
      isNotNull,
    );
  }
  expect(
    restored.findFile('OEBPS/images/animation.png')!.content,
    orderedEquals(converted.findFile('OEBPS/images/animation.png')!.content),
  );
}

Future<void> _testMissingCwebp() async {
  await writeMediaEpub(
    _path('input.epub'),
    mediaEpub(
      resources: {'OEBPS/images/photo.png': img.encodePng(mediaImage())},
    ),
  );
  final dart = p.normalize(
    p.join(
      p.dirname(Platform.resolvedExecutable),
      '..',
      '..',
      '..',
      'dart-sdk',
      'bin',
      Platform.isWindows ? 'dart.exe' : 'dart',
    ),
  );
  final result = await Process.run(
    dart,
    [
      '--packages=.dart_tool/package_config.json',
      'test/support/media_missing_cwebp.dart',
      _path('input.epub'),
      _path('missing.epub'),
    ],
    environment: {
      'PATH': _temporary.path,
      'CWEBP_PATH': _path('missing-cwebp'),
    },
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  expect(result.stdout, contains('明确报错'));
  expect(File(_path('missing.epub')).existsSync(), isFalse);
}

Uint8List _webpChunk(String tag, List<int> bytes) {
  final size = ByteData(4)..setUint32(0, bytes.length, Endian.little);
  return Uint8List.fromList([
    ...ascii.encode(tag),
    ...size.buffer.asUint8List(),
    ...bytes,
    if (bytes.length.isOdd) 0,
  ]);
}

List<int> _uint24(int value) => [
  value & 255,
  (value >> 8) & 255,
  (value >> 16) & 255,
];

Uint8List _animatedWebp(Uint8List original) {
  final frameChunks = BytesBuilder();
  final data = ByteData.sublistView(original);
  for (var offset = 12; offset < original.length;) {
    final tag = ascii.decode(original.sublist(offset, offset + 4));
    final length = data.getUint32(offset + 4, Endian.little);
    final end = offset + 8 + length + (length & 1);
    if ({'VP8 ', 'VP8L', 'ALPH'}.contains(tag)) {
      frameChunks.add(original.sublist(offset, end));
    }
    offset = end;
  }
  final chunks = [
    ..._webpChunk('VP8X', [2, 0, 0, 0, ..._uint24(95), ..._uint24(79)]),
    ..._webpChunk('ANIM', [255, 255, 255, 255, 0, 0]),
    for (final duration in [100, 200])
      ..._webpChunk('ANMF', [
        ..._uint24(0),
        ..._uint24(0),
        ..._uint24(95),
        ..._uint24(79),
        ..._uint24(duration),
        2,
        ...frameChunks.toBytes(),
      ]),
  ];
  return _webpChunk('RIFF', [...ascii.encode('WEBP'), ...chunks]);
}

Future<void> _testAnimatedWebp() async {
  final converted = await _convertWebpFixtures();
  final animation = _animatedWebp(
    converted.findFile('OEBPS/images/photo.webp')!.content,
  );
  expect(img.decodeWebP(animation)!.numFrames, 2);
  await writeMediaEpub(
    _path('animated.epub'),
    mediaEpub(
      resources: {
        'OEBPS/images/animation.webp': animation,
        'OEBPS/images/still.webp': converted
            .findFile('OEBPS/images/photo.webp')!
            .content,
      },
    ),
  );
  final log = await WebpToImgOperation.execute(
    epubPath: _path('animated.epub'),
    outputPath: _path('output.epub'),
  );
  expect(log, contains('跳过 1 张'));
  final output = await readMediaEpub(_path('output.epub'));
  expect(
    output.findFile('OEBPS/images/animation.webp')!.content,
    orderedEquals(animation),
  );
  expect(
    img.decodeJpg(output.findFile('OEBPS/images/still.jpg')!.content),
    isNotNull,
  );
}

Future<void> _testFontSubset(String extension) async {
  final original = await File('test/support/media_complex_probe.$extension')
      .readAsBytes();
  final fontPath = 'OEBPS/fonts/probe.$extension';
  await writeMediaEpub(
    _path('input.epub'),
    mediaEpub(
      resources: {fontPath: original},
      stylesheet:
          '@font-face { font-family: probe; src: url("../fonts/probe.$extension"); }'
          'p { font-family: probe; }',
    ),
  );
  final log = await FontSubsetOperation.execute(
    epubPath: _path('input.epub'),
    outputPath: _path('subset.epub'),
  );
  expect(log, contains('子集化 1 个'));
  final output = await readMediaEpub(_path('subset.epub'));
  final subset = output.findFile(fontPath)!.content;
  expect(subset.length, lessThan(original.length));
  expect(mediaGlyphId(subset, 65), greaterThan(0));
  expect(mediaGlyphId(subset, 66), greaterThan(0));
  expect(mediaGlyphId(subset, 67), 0);
  final tables = mediaFontTables(subset);
  expect(tables.containsKey('GSUB'), isTrue);
  expect(tables.containsKey(extension == 'otf' ? 'CFF ' : 'glyf'), isTrue);
  for (final feature in ['liga=1', 'vert=1', 'ss01=1']) {
    expect(
      mediaShape(subset, 'AB A', feature: feature),
      mediaShape(original, 'AB A', feature: feature),
    );
  }
  expect(
    mediaShape(subset, 'AB A', vertical: true),
    mediaShape(original, 'AB A', vertical: true),
  );
  expect(mediaFontChecksum(subset), 0xb1b0afba);
}

Future<void> _testBackgroundSubset() async {
  final original = await File('test/support/media_complex_probe.otf')
      .readAsBytes();
  final subset = await Isolate.run(
    () => HarfBuzzSubsetter.subset(original, {32, 65, 66}),
  );
  expect(subset, isNotNull);
  expect(mediaGlyphId(subset!, 65), greaterThan(0));
  expect(HarfBuzzSubsetter.subset(Uint8List(1024), {65}), isNull);
}

Future<void> _testTtfFallback(int codePoint) async {
  final original = await File('test/support/media_subset_probe.ttf')
      .readAsBytes();
  final subset = TtfSubsetter.subset(original, {codePoint});
  expect(subset, isNotNull);
  final before = mediaFontTables(original);
  final after = mediaFontTables(subset!);
  expect(after['cmap'], orderedEquals(before['cmap']!));
  expect(mediaGlyphId(subset, codePoint), mediaGlyphId(original, codePoint));
  expect(mediaFontChecksum(subset), 0xb1b0afba);
  List<int> offsets(Map<String, Uint8List> tables) {
    final short = ByteData.sublistView(tables['head']!).getInt16(50) == 0;
    final count = ByteData.sublistView(tables['maxp']!).getUint16(4);
    final data = ByteData.sublistView(tables['loca']!);
    return [
      for (var index = 0; index <= count; index++)
        short ? data.getUint16(index * 2) * 2 : data.getUint32(index * 4),
    ];
  }

  final oldOffsets = offsets(before);
  final newOffsets = offsets(after);
  for (final glyph in [0, 1, 3, 4]) {
    final bytes = before['glyf']!.sublist(
      oldOffsets[glyph],
      oldOffsets[glyph + 1],
    );
    expect(
      after['glyf']!
          .sublist(newOffsets[glyph], newOffsets[glyph + 1])
          .take(bytes.length),
      orderedEquals(bytes),
    );
  }
}

Future<void> _testFontEncryption() async {
  final original = await File('test/support/media_subset_probe.ttf')
      .readAsBytes();
  final result = TtfFontEncryptor.encrypt(original, {65, 66, 0x20000});
  expect(result.fontData, isNotNull);
  expect(result.charToShadow.length, 3);
  final output = result.fontData!;
  for (final entry in result.charToShadow.entries) {
    expect(entry.value, inInclusiveRange(0xac00, 0xd7af));
    expect(
      mediaGlyphId(output, entry.value),
      mediaGlyphId(original, entry.key),
    );
    expect(mediaGlyphId(output, entry.key), mediaGlyphId(original, entry.key));
  }
  expect(
    mediaShape(
      output,
      String.fromCharCodes([
        result.charToShadow[65]!,
        result.charToShadow[66]!,
      ]),
    ),
    mediaShape(original, 'AB'),
  );
  final before = mediaFontTables(original);
  final after = mediaFontTables(output);
  for (final tag in before.keys.where(
    (tag) => tag != 'head' && tag != 'cmap',
  )) {
    expect(after[tag], orderedEquals(before[tag]!), reason: tag);
  }
  expect(mediaFontChecksum(output), 0xb1b0afba);
  expect(TtfFontEncryptor.encrypt(Uint8List(12), {65}).fontData, isNull);
}

Future<void> _testSelectedFontEncryption() async {
  final original = await File('test/support/media_complex_probe.ttf')
      .readAsBytes();
  await writeMediaEpub(
    _path('input.epub'),
    mediaEpub(
      resources: {'OEBPS/fonts/probe.ttf': original},
      stylesheet:
          '@font-face { font-family: "Probe"; src: url("../fonts/probe.ttf"); }'
          '@font-face { font-family: "Missing"; src: url("../missing/probe.ttf"); }'
          '.fonted { font-family: "Probe"; }',
      body:
          '<p class="fonted" title="AB">A&#160;<strong>B</strong></p>'
          '<p>A B 普通正文</p><p style="font-family: Probe">C</p>',
      otherChapters: {'OEBPS/text/ch2.xhtml': '<p class="fonted">ABC</p>'},
    ),
  );
  final targets = await ListFontTargetsOperation.scan(
    epubPath: _path('input.epub'),
  );
  expect(targets.fontFamilies, ['Probe']);
  expect(targets.xhtmlFiles, ['OEBPS/text/ch1.xhtml', 'OEBPS/text/ch2.xhtml']);
  final log = await EncryptFontOperation.execute(
    epubPath: _path('input.epub'),
    outputPath: _path('output.epub'),
    targetFontFamilies: ['probe'],
    targetXhtmlFiles: ['ch1.xhtml'],
  );
  expect(log, contains('加密 1 个'));
  final output = await readMediaEpub(_path('output.epub'));
  final html = mediaText(output, 'OEBPS/text/ch1.xhtml');
  final document = XmlDocument.parse(html);
  final paragraphs = document.findAllElements('p', namespaceUri: '*').toList();
  expect(paragraphs.first.getAttribute('title'), 'AB');
  expect(paragraphs[1].innerText, 'A B 普通正文');
  expect(html, contains('&#160;'));
  final encrypted = output.findFile('OEBPS/fonts/probe.ttf')!.content;
  final shadows = paragraphs.first.innerText.runes
      .where((code) => code >= 0xac00)
      .toList();
  expect(shadows.length, 2);
  expect(mediaGlyphId(encrypted, shadows[0]), mediaGlyphId(original, 65));
  expect(mediaGlyphId(encrypted, shadows[1]), mediaGlyphId(original, 66));
  expect(
    mediaGlyphId(encrypted, paragraphs[2].innerText.runes.single),
    mediaGlyphId(original, 67),
  );
  expect(mediaText(output, 'OEBPS/text/ch2.xhtml'), contains('>ABC</p>'));
  for (final codePoint in [65, 66, 67]) {
    expect(
      mediaGlyphId(encrypted, codePoint),
      mediaGlyphId(original, codePoint),
    );
  }
  expect(mediaFontChecksum(encrypted), 0xb1b0afba);
}

Future<void> _testNameRoundTrip() async {
  final font = await File('test/support/media_subset_probe.ttf').readAsBytes();
  final secondImage = mediaImage()..setPixelRgba(0, 0, 255, 0, 0, 255);
  final resources = {
    'OEBPS/images/a/common.png': img.encodePng(mediaImage()),
    'OEBPS/images/b/common.png': img.encodePng(secondImage),
    'OEBPS/images/封 面.png': img.encodePng(mediaImage(transparent: true)),
    'OEBPS/fonts/probe.ttf': font,
    'OEBPS/nav.ncx': utf8.encode(
      '<ncx><navMap><content src="text/ch1.xhtml#p"/></navMap></ncx>',
    ),
    'OEBPS/graphics/diagram.svg': utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">'
      '<image xlink:href="../images/a/common.png"/></svg>',
    ),
  };
  final archive = mediaEpub(
    resources: resources,
    body:
        '<p id="p">common.png 和原始正文</p>'
        '<img src="../images/a/common.png"/><img src="../images/b/common.png"/>'
        '<img src="../images/${Uri.encodeComponent('封 面.png')}?size=1#crop"/>'
        '<a href="ch1.xhtml#p">续读</a>',
    stylesheet:
        'body { background: url("../images/a/common.png?x=1#mask"); }'
        '@font-face { font-family: probe; src: url("../fonts/probe.ttf"); }',
  );
  await writeMediaEpub(_path('input.epub'), archive);
  expect(
    await EncryptOperation.execute(
      epubPath: _path('input.epub'),
      outputPath: _path('encrypted.epub'),
    ),
    contains('加密完成'),
  );
  final encrypted = await readMediaEpub(_path('encrypted.epub'));
  expect(
    EncryptDecryptBase.isEncrypted(mediaText(encrypted, 'OEBPS/content.opf')),
    isTrue,
  );
  expect(encrypted.findFile('OEBPS/images/a/common.png'), isNull);
  expect(
    await DecryptOperation.execute(
      epubPath: _path('encrypted.epub'),
      outputPath: _path('restored.epub'),
    ),
    contains('解密完成'),
  );
  final restored = await readMediaEpub(_path('restored.epub'));
  expect(
    restored.files.map((file) => file.name).toSet(),
    archive.files.map((file) => file.name).toSet(),
  );
  for (final file in archive.files.where(
    (file) => file.name != 'OEBPS/content.opf',
  )) {
    expect(
      restored.findFile(file.name)!.content,
      orderedEquals(file.content),
      reason: file.name,
    );
  }
  expect(
    EncryptDecryptBase.isEncrypted(mediaText(restored, 'OEBPS/content.opf')),
    isFalse,
  );
  expect(
    mediaGlyphId(restored.findFile('OEBPS/fonts/probe.ttf')!.content, 65),
    greaterThan(0),
  );
}

Future<void> _testLegacyNames() async {
  final name = EncryptDecryptBase.obfuscateName('cover', 'cover.png');
  final bytes = img.encodePng(mediaImage());
  await writeMediaEpub(
    _path('legacy.epub'),
    mediaEpub(
      resources: {'OEBPS/images/$name': bytes},
      body: '<img src="../images/${Uri.encodeComponent(name)}"/>',
      manifestIds: {'OEBPS/images/$name': 'cover'},
    ),
  );
  final log = await DecryptOperation.execute(
    epubPath: _path('legacy.epub'),
    outputPath: _path('restored.epub'),
  );
  expect(log, contains('解密完成'));
  final output = await readMediaEpub(_path('restored.epub'));
  expect(
    output.findFile('OEBPS/images/cover.png')!.content,
    orderedEquals(bytes),
  );
  expect(
    EncryptDecryptBase.isEncrypted(mediaText(output, 'OEBPS/content.opf')),
    isFalse,
  );
}
