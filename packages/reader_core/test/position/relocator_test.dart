import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/relocator.dart';

/// P7-14：位置锚点三级解析——区间直查 → quote+指纹消歧 → 比例兜底。
void main() {
  // 「重复段落」在章内出现两次，用于消歧场景。
  const chapterText =
      '第一章开始。山中有雾，雾里有灯，灯下有人读旧书。'
      '中段过渡文字，与选区无关。'
      '第二章开始。山中有雾，雾里有灯，灯下有人读旧书。'
      '结尾文字。';
  const quote = '山中有雾，雾里有灯，灯下有人读旧书。';

  test('一级：区间直查零成本命中', () {
    final result = AnnotationRelocator.relocate(
      RelocateRequest(quote: quote, directOffset: 7),
      chapterText: chapterText,
    );
    expect(result.isHit, isTrue);
    expect(result.level, RelocateLevel.direct);
    expect(result.offset, 7);
  });

  test('区间直查越界时降级到二级', () {
    final result = AnnotationRelocator.relocate(
      RelocateRequest(quote: quote, directOffset: chapterText.length + 10),
      chapterText: chapterText,
    );
    expect(result.level, RelocateLevel.fingerprint);
  });

  test('二级：唯一命中直接重建', () {
    final result = AnnotationRelocator.relocate(
      RelocateRequest(quote: '中段过渡文字'),
      chapterText: chapterText,
    );
    expect(result.isHit, isTrue);
    expect(result.level, RelocateLevel.fingerprint);
    expect(result.offset, chapterText.indexOf('中段过渡文字'));
  });

  test('重复文本：前后文指纹消歧成功（第二处）', () {
    final second = chapterText.indexOf(quote, chapterText.indexOf(quote) + 1);
    final result = AnnotationRelocator.relocate(
      RelocateRequest(
        quote: quote,
        contextBefore: '第二章开始。',
        contextAfter: '结尾文字。',
      ),
      chapterText: chapterText,
    );
    expect(result.isHit, isTrue);
    expect(result.offset, second, reason: '指纹应锁定第二次出现');
    expect(result.candidates, hasLength(2), reason: '候选随结果返回供 UI');
  });

  test('重复文本：重复选区且无指纹时按 §30.4 取离原位置最近', () {
    final first = chapterText.indexOf(quote);
    final result = AnnotationRelocator.relocate(
      RelocateRequest(quote: quote, searchFrom: first - 5),
      chapterText: chapterText,
    );
    expect(result.offset, first);
  });

  test('指纹平分时仍取离原位置最近（不失败）', () {
    // 两处命中给相同且非零的指纹分（前后文都匹配不上但窗口包含相同
    // 片段），退到最近原则。
    final first = chapterText.indexOf(quote);
    final result = AnnotationRelocator.relocate(
      RelocateRequest(
        quote: quote,
        contextBefore: '。', // 两处窗口都包含
        searchFrom: first + 1,
      ),
      chapterText: chapterText,
    );
    expect(result.isHit, isTrue);
    expect(result.offset, first);
  });

  test('三级：quote 未命中且带比例时按比例兜底', () {
    final result = AnnotationRelocator.relocate(
      RelocateRequest(quote: '这段文字后来被删掉了', chapterFraction: 0.5),
      chapterText: chapterText,
    );
    expect(result.isHit, isTrue);
    expect(result.level, RelocateLevel.fraction);
    expect(result.offset, (0.5 * chapterText.length).round());
  });

  test('比例越界被钳制到 [0,1]', () {
    final result = AnnotationRelocator.relocate(
      RelocateRequest(quote: 'x', chapterFraction: 1.7),
      chapterText: chapterText,
    );
    expect(result.level, RelocateLevel.fraction);
    expect(result.offset, chapterText.length);
  });

  test('三级全失败：quoteNotFound（有 quote 无比例）', () {
    final result = AnnotationRelocator.relocate(
      RelocateRequest(quote: '不存在的原文'),
      chapterText: chapterText,
    );
    expect(result.isHit, isFalse);
    expect(result.failure, RelocateFailure.quoteNotFound);
  });

  test('三级全失败：noAnchor（无 quote 无比例）——调用方置灰保留', () {
    final result = AnnotationRelocator.relocate(
      const RelocateRequest(quote: ''),
      chapterText: chapterText,
    );
    expect(result.isHit, isFalse);
    expect(result.failure, RelocateFailure.noAnchor);
  });
}
