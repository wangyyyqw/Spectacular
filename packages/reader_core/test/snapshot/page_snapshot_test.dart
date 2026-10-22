import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/page_snapshot.dart';

const SnapshotConfig _config = SnapshotConfig(
  pageWidth: 390,
  pageHeight: 844,
  devicePixelRatio: 3,
  fontFamily: 'SourceHanSerifSC',
  fontSize: 18,
  lineHeight: 1.6,
  language: 'zh-CN',
);

const List<SnapshotPage> _pages = <SnapshotPage>[
  SnapshotPage(text: '第一章　　山中有雾，雾里有灯。', annotations: <String>['a1']),
  SnapshotPage(text: '第二章　　灯下有人，人读旧书。'),
  SnapshotPage(text: '第三章　　书页翻过去，风从窗外来。'),
];

void main() {
  test('同一配置与页序列两次哈希一致', () {
    final first = PageSnapshot.hash(_pages, _config);
    final second = PageSnapshot.hash(_pages, _config);
    expect(first, second);
    expect(first, hasLength(64));
  });

  test('字号变化会改变哈希', () {
    const changed = SnapshotConfig(
      pageWidth: 390,
      pageHeight: 844,
      devicePixelRatio: 3,
      fontFamily: 'SourceHanSerifSC',
      fontSize: 20,
      lineHeight: 1.6,
      language: 'zh-CN',
    );
    expect(
      PageSnapshot.hash(_pages, _config),
      isNot(PageSnapshot.hash(_pages, changed)),
    );
  });

  test('DPR 与视口变化会改变哈希', () {
    const changed = SnapshotConfig(
      pageWidth: 360,
      pageHeight: 800,
      devicePixelRatio: 2,
      fontFamily: 'SourceHanSerifSC',
      fontSize: 18,
      lineHeight: 1.6,
      language: 'zh-CN',
    );
    expect(
      PageSnapshot.hash(_pages, _config),
      isNot(PageSnapshot.hash(_pages, changed)),
    );
  });

  test('页顺序变化会改变哈希', () {
    final reversed = _pages.reversed.toList(growable: false);
    expect(
      PageSnapshot.hash(_pages, _config),
      isNot(PageSnapshot.hash(reversed, _config)),
    );
  });

  test('页文本或标注变化会改变哈希', () {
    const changedText = <SnapshotPage>[
      SnapshotPage(text: '第一章　　山中有雾，雾里有灯。'),
      SnapshotPage(text: '第二章　　灯下有人，人读旧书。'),
      SnapshotPage(text: '第三章　　书页翻过去，风从窗外来。'),
    ];
    expect(
      PageSnapshot.hash(_pages, _config),
      isNot(PageSnapshot.hash(changedText, _config)),
    );

    const changedAnnotation = <SnapshotPage>[
      SnapshotPage(text: '第一章　　山中有雾，雾里有灯。', annotations: <String>['a2']),
      SnapshotPage(text: '第二章　　灯下有人，人读旧书。'),
      SnapshotPage(text: '第三章　　书页翻过去，风从窗外来。'),
    ];
    expect(
      PageSnapshot.hash(_pages, _config),
      isNot(PageSnapshot.hash(changedAnnotation, _config)),
    );
  });
}
