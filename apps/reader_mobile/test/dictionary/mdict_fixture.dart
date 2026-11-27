import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

List<int> _number(int value, int width, [Endian endian = Endian.big]) {
  final bytes = ByteData(width);
  if (width == 8) {
    bytes.setUint64(0, value, endian);
  } else if (width == 4) {
    bytes.setUint32(0, value, endian);
  } else {
    bytes.setUint16(0, value, endian);
  }
  return bytes.buffer.asUint8List();
}

List<int> _utf16(String value) => [
  for (final unit in value.codeUnits) ..._number(unit, 2, Endian.little),
];

int _adler(List<int> bytes) {
  var a = 1, b = 0;
  for (final value in bytes) {
    a = (a + value) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}

List<int> _block(List<int> bytes, int compression) => [
  ..._number(compression, 4, Endian.little),
  ..._number(_adler(bytes), 4),
  ...(compression == 2 ? zlib.encode(bytes) : bytes),
];

/// 生成自有的最小二进制词库，不依赖受版权保护的真实词典数据。
Future<File> createMdictFixture(
  Directory directory, {
  String filename = '测试词典.mdx',
  List<(String, List<int>)>? entries,
  int version = 2,
  int compression = 2,
  String encrypted = 'No',
}) async {
  entries ??= [
    ('hello', utf8.encode('<b>你好</b><img src="image.png">')),
    ('help', utf8.encode('帮助')),
    ('alias', utf8.encode('@@@LINK=hello')),
    ('loop', utf8.encode('@@@LINK=loop')),
  ];
  final resource = filename.endsWith('.mdd');
  final width = version == 1 ? 4 : 8;
  List<int> encode(String text) => resource ? _utf16(text) : utf8.encode(text);
  final terminator = resource ? [0, 0] : [0];
  var offset = 0;
  final keys = BytesBuilder();
  final records = BytesBuilder();
  for (final (word, data) in entries) {
    keys.add([..._number(offset, width), ...encode(word), ...terminator]);
    records.add(data);
    offset += data.length;
  }
  final keyBytes = keys.toBytes();
  final keyBlock = _block(keyBytes, compression == 1 ? 0 : compression);
  final recordBytes = records.toBytes();
  final recordBlock = _block(recordBytes, compression);
  final keyInfo = <int>[
    ..._number(entries.length, width),
    for (final word in [entries.first.$1, entries.last.$1]) ...[
      ...(version == 1
          ? [resource ? word.length : utf8.encode(word).length]
          : _number(resource ? word.length : utf8.encode(word).length, 2)),
      ...encode(word),
      if (version != 1) ...terminator,
    ],
    ..._number(keyBlock.length, width),
    ..._number(keyBytes.length, width),
  ];
  final infoBlock = version == 1 ? keyInfo : _block(keyInfo, 2);
  final keyHeader = <int>[
    ..._number(1, width),
    ..._number(entries.length, width),
    if (version != 1) ..._number(keyInfo.length, width),
    ..._number(infoBlock.length, width),
    ..._number(keyBlock.length, width),
  ];
  final header = _utf16(
    '<Dictionary Title="离线测试词典" '
    'Encoding="${resource ? 'UTF-16' : 'UTF-8'}" '
    'GeneratedByEngineVersion="$version.0" Encrypted="$encrypted"/>\u0000',
  );
  return File('${directory.path}/$filename').writeAsBytes([
    ..._number(header.length, 4),
    ...header,
    ..._number(_adler(header), 4, Endian.little),
    ...keyHeader,
    if (version != 1) ..._number(_adler(keyHeader), 4),
    ...infoBlock,
    ...keyBlock,
    ..._number(1, width),
    ..._number(entries.length, width),
    ..._number(width * 2, width),
    ..._number(recordBlock.length, width),
    ..._number(recordBlock.length, width),
    ..._number(recordBytes.length, width),
    ...recordBlock,
  ]);
}
