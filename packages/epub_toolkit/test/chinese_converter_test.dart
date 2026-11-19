import 'package:flutter_test/flutter_test.dart';
import 'package:spectacular_epub_tools/src/core/chinese_converter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('最长匹配保护恒等词、词义、标点和代理对', () {
    final dictionary = ChineseDictionary({
      '后': '後',
      '皇后': '皇后',
      '头发': '頭髮',
      '发': '發',
    });
    expect(dictionary.convert('皇后头发，发😀'), '皇后頭髮，發😀');
  });

  test('打包字典能够双向转换真实中文词组', () async {
    final traditional = await ChineseDictionary.load(
      ChineseConversion.simplifiedToTraditional,
    );
    final simplified = await ChineseDictionary.load(
      ChineseConversion.traditionalToSimplified,
    );
    expect(traditional.convert('皇后头发与数据库'), '皇后頭髮與數據庫');
    expect(simplified.convert('皇后頭髮與數據庫'), '皇后头发与数据库');
  });
}
