import 'package:flutter_test/flutter_test.dart';
import 'support/css_chapter_book.dart';

/// 页索引重放一致性（h）：声明高度块（height/min-height/overflow 裁剪）
/// 的盒内留白会在「按行高之和重建切片」时丢失，含这类块的章节必须跳过
/// 页索引重放/写入——否则二次进入章节与首次分页会差几 px。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('声明高度章节二次分页与首次完全一致', () async {
    final source = await openCssChapter(
      body:
          '<div class="box">声明高度 40px 的盒子，内容会超出一行，观察盒内留白。</div>'
          '<p>普通段落，用于确认后续块位置稳定。</p>'
          '<div class="tall">min-height 80px 的盒子，内容不足也占 80px。</div>',
      css: '.box { height: 40px; overflow: hidden; } '
          '.tall { min-height: 80px; }',
      contentWidth: 300,
      contentHeight: 800,
    );
    final first = await source.loadChapter(0);

    // 清掉页缓存与页索引后重排：结果必须与首次一致。
    source.clearPaginationCache();
    final second = await source.loadChapter(0);

    expect(second.length, first.length, reason: '页数必须一致');
    for (var i = 0; i < first.length; i++) {
      expect(
        second[i].usedHeight,
        closeTo(first[i].usedHeight, 0.01),
        reason: '第 $i 页已用高度必须一致',
      );
      expect(
        second[i].slices.length,
        first[i].slices.length,
        reason: '第 $i 页切片数必须一致',
      );
      for (var s = 0; s < first[i].slices.length; s++) {
        final a = first[i].slices[s];
        final b = second[i].slices[s];
        expect(b.height, closeTo(a.height, 0.01), reason: '切片 $s 高度一致');
        expect(
          b.block.height,
          closeTo(a.block.height, 0.01),
          reason: '切片 $s 的块高空一致（盒高约束不能丢）',
        );
      }
    }
  });
}
