import 'dart:typed_data';

Uint8List buildLocalToolkitBitmap() {
  const width = 64;
  const height = 64;
  final pixels = Uint8List(width * height * 3);
  for (var index = 0; index < pixels.length; index++) {
    pixels[index] = (index * 13) % 256;
  }
  final bytes = Uint8List(54 + pixels.length);
  final header = ByteData.sublistView(bytes)
    ..setUint16(0, 0x4d42, Endian.little)
    ..setUint32(2, bytes.length, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, width, Endian.little)
    ..setInt32(22, height, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, pixels.length, Endian.little);
  header.buffer.asUint8List().setRange(54, bytes.length, pixels);
  return bytes;
}
