import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/epub/chapter/container_blocks.dart';

final _style = ComputedStyle({'font-size': '16px', 'margin': '0'});

void main() {
  test('外边距预算入口与原核心算法严格等价，保留浮动、边界与幂等身份', () async {
    final random = math.Random(721);
    const margins = [-12.0, -4.0, 0.0, 8.0, 16.0, double.nan];
    for (var example = 0; example < 32; example++) {
      final blocks = _marginExample(random, margins);
      final expected = PageBlock.collapseAdjacentMargins(_flow(blocks));
      final synchronous = collapseMarginsIgnoringFloats(blocks);
      final asynchronous = await collapseMarginsIgnoringFloatsAsync(blocks);
      expect(_geometry(_flow(synchronous)), _geometry(expected));
      expect(_geometry(asynchronous), _geometry(synchronous));
      for (var index = 0; index < blocks.length; index++) {
        if (blocks[index].floatSide != null || blocks[index].absolute) {
          expect(asynchronous[index], same(blocks[index]));
        }
      }
      final repeated = await collapseMarginsIgnoringFloatsAsync(asynchronous);
      for (var index = 0; index < asynchronous.length; index++) {
        expect(repeated[index], same(asynchronous[index]));
      }
    }
  });

  test('普通容器收尾返回原列表，少于两个在流块也保留原身份', () async {
    final shared = _container();
    final blocks = [
      _block(0, containers: [_fragment(shared)]),
    ];
    expect(configureContainerDecoration(blocks), same(blocks));
    expect(await configureContainerDecorationAsync(blocks), same(blocks));
    expect(collapseMarginsIgnoringFloats(blocks), same(blocks));
    expect(await collapseMarginsIgnoringFloatsAsync(blocks), same(blocks));
  });

  test('竖排和分栏保留几何与共享容器关系，输入的装饰和CFI不变', () async {
    for (final declaration in [
      {'writing-mode': 'vertical-rl'},
      {'column-count': '2'},
      {'column-width': '80px'},
    ]) {
      final shared = _container();
      final blocks = [
        _block(
          0,
          style: ComputedStyle({..._style.values, ...declaration}),
          containers: [_fragment(shared, start: true)],
        ),
        _block(1, containers: [_fragment(shared, end: true)]),
        _block(2),
      ];
      final before = _geometry(blocks);
      final expected = configureContainerDecoration(blocks);
      final actual = await configureContainerDecorationAsync(blocks);
      expect(_geometry(actual), _geometry(expected));
      final replacement = actual.first.containers.single.container;
      expect(replacement, isNot(same(shared)));
      expect(actual[1].containers.single.container, same(replacement));
      expect(replacement.cloneDecoration, isFalse);
      expect(actual[2], same(blocks[2]));
      expect(_geometry(blocks), before);
      expect(shared.cloneDecoration, isTrue);
    }
  });

  test('发现和改写单块的大量容器片段时均可取消，不发布部分列表', () async {
    for (final special in [false, true]) {
      final blocks = [
        _block(
          0,
          style: special ? ComputedStyle({'column-count': '2'}) : _style,
          containers: _deepFragments(),
        ),
      ];
      final before = _geometry(blocks);
      final cancel = _Cancellation(10);
      var published = false;
      final task = configureContainerDecorationAsync(
        blocks,
        checkpoint: cancel.checkpoint,
      ).then((_) => published = true);
      await expectLater(task, throwsA(same(cancel.error)));
      expect(cancel.calls, 10);
      expect(published, isFalse);
      expect(_geometry(blocks), before);
    }
  });

  test('相邻两块的单次容器边界扫描可取消，不在外围等整对扫描结束', () async {
    final blocks = [
      _block(0, after: 12, containers: _deepFragments()),
      _block(1, before: 8),
    ];
    final before = _geometry(blocks);
    final cancel = _Cancellation(10);
    await expectLater(
      collapseMarginsIgnoringFloatsAsync(blocks, checkpoint: cancel.checkpoint),
      throwsA(same(cancel.error)),
    );
    expect(cancel.calls, 10);
    expect(_geometry(blocks), before);
  });

  test('容器浮动预扫描内取消时还未插入垫片或改写子块', () async {
    final blocks = List.generate(80, (index) => _block(index));
    final original = blocks.toList();
    final cancel = _Cancellation(10);
    await expectLater(
      wrapContainerBlocks(
        blocks,
        0,
        _container(),
        checkpoint: cancel.checkpoint,
      ),
      throwsA(same(cancel.error)),
    );
    expect(cancel.calls, 10);
    for (var index = 0; index < original.length; index++) {
      expect(blocks[index], same(original[index]));
    }
  });
}

class _Cancellation {
  _Cancellation(this.at);
  final int at;
  final error = StateError('取消容器收尾');
  int calls = 0;

  Future<void> checkpoint() async {
    if (++calls == at) throw error;
  }
}

List<PageBlock> _marginExample(math.Random random, List<double> margins) {
  final container = _container();
  return [
    for (var index = 0; index < 10; index++)
      if (index % 3 == 1)
        PageBlock(
          layout: _layout(index),
          floatSide: index.isOdd ? FloatSide.left : null,
          absolute: index.isEven,
          spaceBefore: 27,
          spaceAfter: 33,
        )
      else
        _block(
          index,
          before: margins[random.nextInt(margins.length)],
          after: margins[random.nextInt(margins.length)],
          containers: [
            _fragment(
              container,
              start: random.nextBool(),
              end: random.nextBool(),
            ),
          ],
        ),
  ];
}

List<PageBlock> _flow(List<PageBlock> blocks) => blocks
    .where((block) => !block.absolute && block.floatSide == null)
    .toList();

TextLayoutResult _layout(int index) => TextLayoutResult(
  text: '正文$index',
  lines: const [
    LineBox(start: 0, end: 3, top: 0, height: 20, baseline: 16, width: 100),
  ],
  width: 100,
  height: 20,
  maxWidth: 100,
);

PageBlock _block(
  int index, {
  double before = 0,
  double after = 0,
  List<PageContainerFragment> containers = const [],
  ComputedStyle? style,
}) => PageBlock(
  layout: _layout(index),
  style: style ?? _style,
  spaceBefore: before,
  spaceAfter: after,
  topInset: 2,
  bottomInset: 3,
  leftInset: 4,
  startCfi: 'epubcfi(/6/2!/4/${index * 2 + 2})',
  endCfi: 'epubcfi(/6/2!/4/${index * 2 + 2}:3)',
  containers: containers,
  declaredContentHeight: 20,
  effectiveOpacity: 0.6,
);

PageContainer _container() => PageContainer(
  style: ComputedStyle({'display': 'block', 'padding': '2px 0 3px'}),
  left: 4,
  width: 100,
  cloneDecoration: true,
  isPageRoot: true,
);

PageContainerFragment _fragment(
  PageContainer container, {
  bool start = false,
  bool end = false,
}) => PageContainerFragment(
  container: container,
  startsHere: start,
  endsHere: end,
  topInset: 5,
  bottomInset: 7,
);

List<PageContainerFragment> _deepFragments() {
  final container = _container();
  return List.generate(256, (_) => _fragment(container));
}

List<Object?> _geometry(List<PageBlock> blocks) => [
  for (final block in blocks)
    [
      block.layout,
      block.style,
      _number(block.spaceBefore),
      _number(block.spaceAfter),
      block.topInset,
      block.bottomInset,
      block.leftInset,
      block.startCfi,
      block.endCfi,
      block.floatSide,
      block.absolute,
      block.declaredContentHeight,
      block.effectiveOpacity,
      for (final fragment in block.containers)
        [
          fragment.startsHere,
          fragment.endsHere,
          fragment.topInset,
          fragment.bottomInset,
          fragment.container.style,
          fragment.container.left,
          fragment.container.width,
          fragment.container.cloneDecoration,
          fragment.container.isPageRoot,
        ],
    ],
];

Object _number(double value) => value.isNaN ? 'NaN' : value;
