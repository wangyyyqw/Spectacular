import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/parser/cfi_binder.dart';
import 'package:reader_core/parser/cfi_resolver.dart';
import 'package:reader_core/position/cfi.dart';

const _base =
    '<html><body><p id="p1">Hello</p><p id="p2">World</p></body></html>';

EpubCfi _p2TextCfi() {
  final bound = CfiBinder.bind(xhtml: _base, spineIndex: 0);
  return bound.textNodes.last.baseCfi;
}

void main() {
  test('未变化的 CFI 精确解析', () {
    final target = _p2TextCfi();
    final result = CfiResolver.resolve(
      xhtml: _base,
      target: target,
      expectedSpineIndex: 0,
    );
    expect(result.ok, isTrue);
    expect(result.exact, isTrue);
    expect(result.adjusted, isFalse);
    expect(result.warnings, isEmpty);
    expect(result.cfi!.serialize(), target.serialize());
  });

  test('节点删除时回退到最近节点', () {
    final target = _p2TextCfi();
    final result = CfiResolver.resolve(
      xhtml: '<html><body><p id="p1">Hello</p></body></html>',
      target: target,
      expectedSpineIndex: 0,
    );
    expect(result.ok, isTrue);
    expect(result.adjusted, isTrue);
    expect(result.warnings, isNotEmpty);
    expect(result.cfi!.serialize(), 'epubcfi(/6/2!/4/2[p1]/1)');
  });

  test('文本节点删除时回退到元素起点', () {
    final target = _p2TextCfi();
    final result = CfiResolver.resolve(
      xhtml: '<html><body><p id="p1">Hello</p><p id="p2"></p></body></html>',
      target: target,
      expectedSpineIndex: 0,
    );
    expect(result.ok, isTrue);
    expect(result.adjusted, isTrue);
    expect(result.cfi!.serialize(), 'epubcfi(/6/2!/4/4[p2])');
    expect(result.textOffset, isNull);
  });

  test('字符偏移越界时钳制到文本末尾', () {
    final target = _p2TextCfi().withCharOffset(99);
    final result = CfiResolver.resolve(
      xhtml: _base,
      target: target,
      expectedSpineIndex: 0,
    );
    expect(result.ok, isTrue);
    expect(result.adjusted, isTrue);
    expect(result.textOffset, 5);
    expect(result.cfi!.charOffset, 5);
    expect(result.warnings.any((w) => w.contains('字符偏移越界')), isTrue);
  });

  test('嵌套变化时按 id 断言重新定位', () {
    final target = _p2TextCfi();
    final result = CfiResolver.resolve(
      xhtml: '<html><body><div><p id="p2">World</p></div></body></html>',
      target: target,
      expectedSpineIndex: 0,
    );
    expect(result.ok, isTrue);
    expect(result.adjusted, isTrue);
    expect(result.cfi!.serialize(), contains('[p2]'));
    expect(result.warnings.any((w) => w.contains('id 断言')), isTrue);
  });

  test('itemref 与章节不匹配时明确失败', () {
    final result = CfiResolver.resolve(
      xhtml: _base,
      target: _p2TextCfi(),
      expectedSpineIndex: 1,
    );
    expect(result.ok, isFalse);
    expect(result.warnings.single, contains('itemref'));
  });

  test('XHTML 非法时返回失败而不抛异常', () {
    final result = CfiResolver.resolve(
      xhtml: '<html><body><p>',
      target: _p2TextCfi(),
      expectedSpineIndex: 0,
    );
    expect(result.ok, isFalse);
    expect(result.warnings, isNotEmpty);
  });
}
