import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/book_identity.dart';

void main() {
  test('固定向量：UTF-8 JSON 编码与 SHA-256 前128位保持跨平台一致', () {
    expect(
      generateBookId(
        title: '史记',
        author: '司马迁',
        identifier: 'urn:uuid:12345678-1234-1234-1234-123456789abc',
      ),
      '5254e823ce6321371c8300ab4822eea2',
    );
    expect(
      generateBookId(title: '测试书', author: '测试作者', identifier: ''),
      '7363ebcf3d128c7b8cc951a62f4d77d6',
    );
    expect(
      generateBookId(title: '', author: '', identifier: ''),
      '098fb7fb98035c2deda40fd5c2c11163',
    );
  });

  test('重复计算和首尾空白稳定，三个字段均参与身份', () {
    final id = generateBookId(title: '书名', author: '作者', identifier: 'UUID');
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(
      generateBookId(title: ' 书名 ', author: '\n作者\t', identifier: ' UUID '),
      id,
    );
    for (final fields in [
      ['新书名', '作者', 'UUID'],
      ['书名', '新作者', 'UUID'],
      ['书名', '作者', '新UUID'],
    ]) {
      expect(
        generateBookId(
          title: fields[0],
          author: fields[1],
          identifier: fields[2],
        ),
        isNot(id),
      );
    }
  });

  test('字段边界、标点和大小写不会被清洗成相同输入', () {
    expect(
      generateBookId(title: 'ab', author: 'c', identifier: 'd'),
      isNot(generateBookId(title: 'a', author: 'bc', identifier: 'd')),
    );
    expect(
      generateBookId(title: '书', author: '作', identifier: 'a:b'),
      isNot(generateBookId(title: '书', author: '作', identifier: 'a/b')),
    );
    expect(
      generateBookId(title: '书', author: '作', identifier: 'UUID'),
      isNot(generateBookId(title: '书', author: '作', identifier: 'uuid')),
    );
  });
}
