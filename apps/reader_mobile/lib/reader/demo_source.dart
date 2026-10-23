import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_ui/reader_session.dart';

/// 30 章纯文本示例，用于 M0 联调不依赖外部文件。
class DemoChapterSource implements ReaderChapterSource {
  @override
  int get chapterCount => 30;

  final ComputedStyle _style = ComputedStyle(const <String, String>{
    'font-size': '18px',
    'line-height': '1.6',
    'font-family': 'serif',
  });

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final lines = <String>[
      '第${spineIndex + 1}章',
      for (var i = 1; i <= 32; i++)
        '这是第${spineIndex + 1}章第$i行示例文本，用于验证打开、分页、绘制与翻页链路。',
    ];
    final layout = TextLayoutEngine.layout(
      text: lines.join('\n'),
      style: _style,
      maxWidth: 320,
    );
    final block = PageBlock(layout: layout, style: _style);
    return Paginator(pageHeight: 480)
        .measureChapter(blocks: <PageBlock>[block], spineIndex: spineIndex)
        .pages;
  }
}
