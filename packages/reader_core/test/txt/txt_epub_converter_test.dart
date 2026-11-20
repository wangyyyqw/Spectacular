import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/txt.dart';
import 'package:xml/xml.dart';

Future<({List<String> blocks, Map<String, dynamic> metadata})> _read(
  File file,
) async {
  final opened = await openEpubFile(file);
  expect(opened.report.ok, isTrue, reason: opened.report.message);
  final doc = opened.document!;
  try {
    final blocks = <String>[];
    for (final item in doc.spine) {
      final xml = XmlDocument.parse(
        doc.archive.readString('OEBPS/${item.href}')!,
      );
      blocks.addAll(
        xml.descendants
            .whereType<XmlElement>()
            .where((node) => {'p', 'h1', 'h2'}.contains(node.name.local))
            .map((node) => node.innerText),
      );
    }
    return (
      blocks: blocks,
      metadata: jsonDecode(
        doc.archive.readString(txtMetadataPath)!,
      ) as Map<String, dynamic>,
    );
  } finally {
    doc.archive.close();
  }
}

Uint8List _utf16(String text, bool little) => Uint8List.fromList([
  if (little) ...[0xff, 0xfe] else ...[0xfe, 0xff],
  for (final unit in text.codeUnits)
    if (little) ...[unit & 255, unit >> 8] else ...[unit >> 8, unit & 255],
]);

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('txt-epub-test-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('UTF8检测样本截断多字节字符仍正确，真实替代符作为原文保留', () async {
    final text = '${'a' * 65535}中😀\n第一章 开始\n保留�字符';
    final output = File('${temporary.path}/boundary.epub');
    final result = await TxtEpubConverter.convertBytes(
      Uint8List.fromList(utf8.encode(text)),
      output,
    );
    expect(result.encoding, 'UTF-8');
    expect((await _read(output)).blocks.join(), text.replaceAll('\n', ''));
  });

  test('GBK及Big5字符跨读取边界不丢失', () async {
    final text = '${'a' * 65535}天地人生\n第一章 開始\n末尾';
    for (final codec in [const GbkCodec(), const Big5Codec()]) {
      final output = File('${temporary.path}/chunk-${codec.name}.epub');
      final result = await TxtEpubConverter.convertBytes(
        Uint8List.fromList(codec.encode(text)),
        output,
        encoding: codec.name,
      );
      expect(
        (await _read(result.file)).blocks.join(),
        text.replaceAll('\n', ''),
      );
    }
  });

  test('后台取消在提交前清理临时文件', () async {
    var cancel = false;
    final output = File('${temporary.path}/cancel.epub');
    await expectLater(
      TxtEpubConverter.convertBytes(
        Uint8List.fromList(utf8.encode('正文\n' * 10000)),
        output,
        isCancelled: () => cancel,
        onProgress: (progress) {
          if (progress >= 0.35) cancel = true;
        },
      ),
      throwsA(
        isA<TxtConversionException>().having(
          (error) => error.code,
          '错误码',
          'E_CANCELLED',
        ),
      ),
    );
    expect(await output.exists(), isFalse);
    expect(await temporary.list().toList(), isEmpty);
  });

  test('生成正式EPUB3，清空白行及原缩进，保留行内空格、特殊字符和唯一标题', () async {
    const text =
        '\ufeff\r\n \t　\r\n \t　第一章 开始\r\n　\t 甲 & <乙>😀\r\n\r\n\t第二章 终点\r\n  结束。 行内\t　空格  \r\n';
    final bytes = Uint8List.fromList(utf8.encode(text));
    final output = File('${temporary.path}/book.epub');
    final result = await TxtEpubConverter.convertBytes(
      bytes,
      output,
      title: '书 & 名',
    );
    final content = await _read(output);
    expect(content.blocks, ['第一章 开始', '甲 & <乙>😀', '第二章 终点', '结束。 行内\t　空格  ']);
    expect(result.detection.blockCount, 4);
    expect(result.detection.boundaries.map((boundary) => boundary.blockIndex), [
      0,
      2,
    ]);
    expect(result.identifier, '$txtIdentifierPrefix${sha256.convert(bytes)}');
    expect(content.metadata['schema'], 1);
    expect(content.metadata['sourceDigest'], result.sourceDigest);
    final zip = ZipDecoder().decodeBytes(await output.readAsBytes());
    expect(zip.files.first.name, 'mimetype');
    expect(zip.files.first.compression, CompressionType.none);
    final opened = await openEpubFile(output);
    expect(opened.document!.meta.title, '书 & 名');
    expect(opened.document!.toc.map((entry) => entry.title), [
      '第一章 开始',
      '第二章 终点',
    ]);
    opened.document!.archive.close();
  });

  for (final encoding in ['UTF-16LE', 'UTF-16BE', 'GBK', 'Big5']) {
    test('$encoding严格解码，生成后正文一致', () async {
      const text = '第一章 春天\n　　天地人生，山水明月。\n第二章 夜雨\n春风又来。';
      final bytes = switch (encoding) {
        'UTF-16LE' => _utf16(text, true),
        'UTF-16BE' => _utf16(text, false),
        'GBK' => Uint8List.fromList(const GbkCodec().encode(text)),
        _ => Uint8List.fromList(
          const Big5Codec().encode(
            text.replaceAll('风', '風').replaceAll('来', '來'),
          ),
        ),
      };
      final output = File('${temporary.path}/book.epub');
      final result = await TxtEpubConverter.convertBytes(
        bytes,
        output,
        encoding: encoding,
      );
      expect(result.encoding, encoding);
      final expected = encoding == 'Big5'
          ? text.replaceAll('风', '風').replaceAll('来', '來')
          : text;
      expect(
        (await _read(output)).blocks.join('\n'),
        expected.replaceFirst('　　', ''),
      );
    });
  }

  test('UTF16 BOM自动识别与分块代理对完整解码', () async {
    final text = '第一章\n${'甲' * 32760}😀末尾';
    final result = await TxtEpubConverter.convertBytes(
      _utf16(text, true),
      File('${temporary.path}/book.epub'),
    );
    expect(result.encoding, 'UTF-16LE');
    expect((await _read(result.file)).blocks.join(), text.replaceAll('\n', ''));
  });

  test('GBK及Big5自动检测能识别正常中文长样本', () async {
    const text = '第一章 春天\n天地人生，山水明月。春風又來，人生如夢。';
    for (final codec in [const GbkCodec(), const Big5Codec()]) {
      final output = File('${temporary.path}/${codec.name}.epub');
      final bytes = Uint8List.fromList(codec.encode(text));
      try {
        final result = await TxtEpubConverter.convertBytes(bytes, output);
        expect((await _read(result.file)).blocks.join('\n'), text);
      } on TxtConversionException catch (error) {
        expect(error.code, 'E_TXT_ENCODING_AMBIGUOUS');
        expect(
          error.encodingCandidates.map((candidate) => candidate.name),
          contains(codec.name.toLowerCase() == 'gbk' ? 'GBK' : 'Big5'),
        );
      }
    }
  });

  test('超长单行与无标题兜底不丢字符，不截断emoji', () async {
    final text = '${'甲' * 9999}😀${'乙' * 40000}结束';
    final output = File('${temporary.path}/book.epub');
    final result = await TxtEpubConverter.convertBytes(
      Uint8List.fromList(utf8.encode(text)),
      output,
    );
    final content = await _read(output);
    expect(content.blocks.join(), text);
    expect(content.blocks.any((block) => block.contains('\ufffd')), isFalse);
    expect(result.detection.boundaries.length, greaterThan(1));
    expect(content.blocks.any((block) => block.startsWith('第 1 节')), isFalse);
  });

  test('分卷生成两层目录且正文不重复卷名', () async {
    const text = '第一卷 春\n卷前文字\n第一章 开始\n正文\n第二章 继续\n正文\n第二卷 夏\n第一章 新章\n正文';
    final output = File('${temporary.path}/book.epub');
    await TxtEpubConverter.convertBytes(
      Uint8List.fromList(utf8.encode(text)),
      output,
    );
    final opened = await openEpubFile(output);
    final toc = opened.document!.toc;
    expect(toc.length, 2);
    expect(toc.first.children.length, 2);
    expect(toc.last.children.length, 1);
    opened.document!.archive.close();
    expect((await _read(output)).blocks.join('\n'), text);
  });

  test('只有卷标题时导航不产生空列表', () async {
    final output = File('${temporary.path}/volume.epub');
    await TxtEpubConverter.convertBytes(
      Uint8List.fromList(utf8.encode('第一卷\n正文\n第二卷\n正文')),
      output,
    );
    final opened = await openEpubFile(output);
    final nav = XmlDocument.parse(
      opened.document!.archive.readString('OEBPS/nav.xhtml')!,
    );
    expect(
      nav.descendants
          .whereType<XmlElement>()
          .where((node) => node.name.local == 'ol')
          .every((node) => node.childElements.isNotEmpty),
      isTrue,
    );
    opened.document!.archive.close();
  });

  test('样本之后遇到不同编码字节时提供编码纠错候选', () async {
    final bytes = Uint8List.fromList([
      ...List.filled(65536, 0x61),
      ...const GbkCodec().encode('第一章 开始'),
    ]);
    await expectLater(
      TxtEpubConverter.convertBytes(
        bytes,
        File('${temporary.path}/wrong.epub'),
      ),
      throwsA(
        isA<TxtConversionException>().having(
          (error) =>
              error.encodingCandidates.map((candidate) => candidate.name),
          '可选编码',
          contains('GBK'),
        ),
      ),
    );
  });

  test('文件路径分块导入与字节导入得到同一来源标识', () async {
    final source = File('${temporary.path}/source.txt');
    await source.writeAsString('第一章 开始\n正文内容。');
    final first = await TxtEpubConverter.convertFile(
      source,
      File('${temporary.path}/file.epub'),
    );
    final second = await TxtEpubConverter.convertBytes(
      await source.readAsBytes(),
      File('${temporary.path}/bytes.epub'),
    );
    expect(first.identifier, second.identifier);
    expect((await _read(first.file)).blocks, (await _read(second.file)).blocks);
  });

  test('空书、非法编码、取消和已存在目标均不写成品', () async {
    final output = File('${temporary.path}/book.epub');
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList(utf8.encode(' \n　\t\n')),
      Uint8List.fromList([0xff]),
    ]) {
      await expectLater(
        TxtEpubConverter.convertBytes(bytes, output, encoding: 'UTF-8'),
        throwsA(isA<TxtConversionException>()),
      );
      expect(await output.exists(), isFalse);
    }
    await expectLater(
      TxtEpubConverter.convertBytes(
        Uint8List.fromList(utf8.encode('正文')),
        output,
        isCancelled: () => true,
      ),
      throwsA(
        isA<TxtConversionException>().having(
          (error) => error.code,
          '错误码',
          'E_CANCELLED',
        ),
      ),
    );
    await output.writeAsString('保留原文件');
    await expectLater(
      TxtEpubConverter.convertBytes(
        Uint8List.fromList(utf8.encode('正文')),
        output,
      ),
      throwsA(isA<TxtConversionException>()),
    );
    expect(await output.readAsString(), '保留原文件');
    expect((await temporary.list().toList()).whereType<Directory>(), isEmpty);
  });
}
