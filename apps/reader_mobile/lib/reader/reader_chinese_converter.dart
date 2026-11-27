import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/text/reader_text_conversion.dart';
import 'package:reader_core/text/text_offsets.dart';
import 'package:spectacular_opencc/opencc_native.dart';

/// 官方 OpenCC 引擎与词典；旧词典中官方未收录的词条已在构建资源时合并。
class ReaderChineseConverter {
  ReaderChineseConverter({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const String assetRoot = 'packages/spectacular_opencc/assets/opencc';
  // 词典内容或合并规则变化时必须提升，旧私有目录不会自动刷新。
  static const String version = '1.4.2-v2';
  static const List<String> _common = ['CJK_Compatibility_Ideographs.ocd2'];
  static const Map<ReaderChineseMode, List<String>> _dictionaries = {
    ReaderChineseMode.traditional: [
      'STPhrases.ocd2',
      'STPhrases_GeneratedFromRegionalPhrases.ocd2',
      'STCharacters.ocd2',
    ],
    ReaderChineseMode.simplified: [
      'TSPhrases.ocd2',
      'TSCharactersExt.ocd2',
      'TSCharacters.ocd2',
    ],
  };

  final Future<Directory> Function() _directoryProvider;
  final _prepared = <ReaderChineseMode, Future<ReaderTextConversion>>{};

  Future<ReaderTextConversion?> load(ReaderChineseMode mode) async {
    if (mode == ReaderChineseMode.original) return null;
    final existing = _prepared[mode];
    final pending = existing ?? _prepare(mode);
    _prepared[mode] = pending;
    try {
      return await pending;
    } catch (_) {
      _prepared.remove(mode)?.ignore();
      rethrow;
    }
  }

  Future<ReaderTextConversion> _prepare(ReaderChineseMode mode) async {
    final root = await _directoryProvider();
    final directory = Directory(p.join(root.path, 'opencc', version));
    await directory.create(recursive: true);
    final name = mode == ReaderChineseMode.traditional ? 's2t' : 't2s';
    final config = File(p.join(directory.path, '$name.json'));
    if (!await config.exists()) {
      for (final asset in [..._common, ..._dictionaries[mode]!]) {
        await _copy(asset, File(p.join(directory.path, asset)));
      }
      // 配置最后落盘，存在即代表同版本的字典已齐备。
      await _copy('$name.json', config);
    }
    final converter = _NativeReaderConversion(config.path);
    // 提前打开原生配置，缺少词典或原生资源时不保存不可用的偏好。
    converter.convert('简繁转换');
    return ReaderTextConversion(
      id: 'opencc-$version:${mode.name}',
      convert: converter.convert,
    );
  }

  /// 先写临时文件再改名，进程中断不会留下被当作完整的截断字典。
  static Future<void> _copy(String name, File target) async {
    final data = await rootBundle.load('$assetRoot/$name');
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await temp.rename(target.path);
  }
}

/// 只传递配置路径到章节准备 isolate，不跨 isolate 传递 FFI 指针。
class _NativeReaderConversion {
  const _NativeReaderConversion(this.path);
  final String path;

  ConvertedReaderText convert(String text) {
    final result = convertOpencc(path, text);
    TextOffsetMap? offsets;
    for (final stage in result.stages) {
      final builder = TextOffsetMapBuilder();
      for (final (input, output) in stage) {
        builder.add(input, output);
      }
      offsets = composeTextOffsets(offsets, builder.build());
    }
    return (text: result.text, offsets: offsets);
  }
}
