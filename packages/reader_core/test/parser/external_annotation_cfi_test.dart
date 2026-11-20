import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/parser/external_annotation_cfi.dart';

void main() {
  test('带横向装饰的内联文本使用阅微分组坐标及装饰占位偏移', () {
    final mapper = ExternalAnnotationCfi(
      '<html><body>\n<p><span>原文</span></p></body></html>',
      isInline: (cfi) => cfi == 'epubcfi(/6/2!/4/2/2)',
      hasInlineDecoration: (_) => true,
    );
    expect(
      mapper.toExternal('epubcfi(/6/2!/4/2/2/1:0)'),
      'epubcfi(/6/2/4/2/1/1:1)',
    );
    expect(
      mapper.toExternal('epubcfi(/6/2!/4/2/2/1:2)'),
      'epubcfi(/6/2/4/2/1/1:3)',
    );
  });

  test('原 DOM 编号转换覆盖空白、内联元素与字符偏移', () {
    final mapper = ExternalAnnotationCfi(
      '<html><body>\n<p> 首段 <em>强调</em> 尾段 </p>\n<p>次段</p>\n</body></html>',
    );
    const pairs = {
      'epubcfi(/6/12!/4/2/1:1)': 'epubcfi(/6/12/4/2/1/1:0)',
      'epubcfi(/6/12!/4/2/2/1:1)': 'epubcfi(/6/12/4/2/2/1/1:1)',
      'epubcfi(/6/12!/4/2/3:2)': 'epubcfi(/6/12/4/2/3/1:1)',
      'epubcfi(/6/12!/4/4/1:1)': 'epubcfi(/6/12/4/4/1/1:1)',
    };
    for (final pair in pairs.entries) {
      expect(mapper.toExternal(pair.key), pair.value);
      expect(mapper.toLocal(pair.value), pair.key);
    }
  });

  test('紧邻元素没有空白时原 DOM 编号仍能双向定位', () {
    final mapper = ExternalAnnotationCfi(
      '<html><body><p>第一段</p><p><em>第二段</em></p></body></html>',
    );
    const local = 'epubcfi(/6/2!/4/4/2/1:2)';
    const remote = 'epubcfi(/6/2/4/2/1/1/1:2)';
    expect(mapper.toExternal(local), remote);
    expect(mapper.toLocal(remote), local);
    expect(mapper.toLocal('epubcfi(/6/2/4/8/1/1:2)'), isNull);
    expect(mapper.toExternal('epubcfi(/6/2!/4/4/2/1:40)'), isNull);
  });
}
