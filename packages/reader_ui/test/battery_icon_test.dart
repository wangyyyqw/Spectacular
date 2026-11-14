import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/page_furniture/battery_icon.dart';
import 'package:reader_ui/page_furniture/corner_info.dart';
import 'package:reader_ui/page_furniture/corner_row.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

const _channel = MethodChannel('com.spectacular.reader_mobile/reader');
const _eventChannel = EventChannel('com.spectacular.reader_mobile/battery');
const _pixelWidth = 128;

void main() {
  testWidgets('电池图标按实际电量填充，零电量留空', (tester) async {
    final filled = <int>[];
    for (final level in [0, 15, 50, 100]) {
      final pixels = await _renderIcon(tester, level);
      filled.add(_filledPixels(pixels));
    }
    expect(filled[0], 0);
    expect(filled[1], greaterThan(0));
    expect(filled[1], lessThan(filled[2]));
    expect(filled[2] / filled[3], closeTo(.5, .05));
    expect(filled[3], 56 * 24);
  });

  testWidgets('未知电量有短横提示，读屏仍可获取真实电量', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final unknown = await _renderIcon(tester, null);
      expect(unknown.getUint8((24 * _pixelWidth + 40) * 4 + 3), greaterThan(0));
      expect(
        tester.getSemantics(find.bySemanticsLabel('电量')).value,
        '未知，充电状态未知',
      );
      await _renderIcon(tester, 50);
      expect(
        tester.getSemantics(find.bySemanticsLabel('电量')).value,
        '50%，充电状态未知',
      );
      expect(find.text('50%'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('充电显示闪电，断电隐藏，图标尺寸和电量填充不变', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final idle = await _renderIcon(tester, 50, charging: false);
      expect(_boltPixels(idle), 0);
      expect(tester.getSemantics(find.bySemanticsLabel('电量')).value, '50%，未充电');
      final charging = await _renderIcon(tester, 50, charging: true);
      expect(_boltPixels(charging), greaterThan(0));
      expect(_filledPixels(charging), _filledPixels(idle));
      expect(tester.getSemantics(find.bySemanticsLabel('电量')).value, '50%，充电中');
      await _renderIcon(tester, 100, charging: true);
      expect(
        tester.getSemantics(find.bySemanticsLabel('电量')).value,
        '100%，已充满，已接电',
      );
      final unplugged = await _renderIcon(tester, 50, charging: false);
      expect(_boltPixels(unplugged), 0);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('时间旁电池图标随分钟刷新，读取失败保留有效值', (tester) async {
    var level = 73;
    var fail = false;
    _mockBattery(tester, () async {
      if (fail) throw PlatformException(code: 'battery_unavailable');
      return level;
    });
    await tester.pumpWidget(_rows(1));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^\d\d:\d\d$')), findsOneWidget);
    expect(find.text('73%'), findsNothing);
    expect(_levels(tester), [73]);
    level = 15;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(_levels(tester), [15]);
    fail = true;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(_levels(tester), [15]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('预热纸面立即复用电量，异步更新同步到两张纸面', (tester) async {
    var read = () async => 73;
    _mockBattery(tester, () => read());
    await tester.pumpWidget(_rows(1, fixedClock: true));
    await tester.pumpAndSettle();
    final next = Completer<int>();
    read = () => next.future;
    await tester.pumpWidget(_rows(2, fixedClock: true));
    expect(_levels(tester), [73, 73]);
    next.complete(42);
    await tester.pumpAndSettle();
    expect(_levels(tester), [42, 42]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首次读取未完成或无效时也保留电池图标', (tester) async {
    final next = Completer<int?>();
    _mockBattery(tester, () => next.future);
    await tester.pumpWidget(_rows(1, fixedClock: true));
    expect(_levels(tester), [null]);
    next.complete(-1);
    await tester.pumpAndSettle();
    expect(_levels(tester), [null]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('退出后重开重新读取电量，旧查询晚到不覆盖新值', (tester) async {
    final prior = Completer<int?>();
    var reads = 0;
    _mockBattery(tester, () async {
      if (++reads == 1) return prior.future;
      return 18;
    });
    await tester.pumpWidget(_rows(1, fixedClock: true));
    expect(_levels(tester), [null]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_rows(1, fixedClock: true));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(_levels(tester), [18]);
    prior.complete(92);
    await tester.pumpAndSettle();
    expect(_levels(tester), [18]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('系统事件立即同步纸面充电状态，异常事件保留有效值', (tester) async {
    final events = _mockBattery(tester, () async => 73, charging: () => false);
    await tester.pumpWidget(_rows(2, fixedClock: true));
    await tester.pumpAndSettle();
    expect(events.listens, 1, reason: '预热纸面共用一份系统订阅');
    expect(_charging(tester), [false, false]);
    events.send(73, true);
    await tester.pumpAndSettle();
    expect(_charging(tester), [true, true]);
    expect(_levels(tester), [73, 73]);
    events.sink!.error(code: 'battery_unavailable', message: '暂时无法获取状态');
    events.send(-1, null);
    await tester.pumpAndSettle();
    expect(_charging(tester), [true, true]);
    expect(_levels(tester), [73, 73]);
    events.send(73, false);
    await tester.pumpAndSettle();
    expect(_charging(tester), [false, false]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(events.cancels, 1);
  });

  testWidgets('分钟查询晚到不能覆盖已经收到的充电事件', (tester) async {
    final delayed = Completer<int?>();
    var reads = 0;
    final events = _mockBattery(
      tester,
      () async => ++reads == 1 ? 73 : delayed.future,
      charging: () => false,
    );
    await tester.pumpWidget(_rows(1));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    events.send(73, true);
    await tester.pumpAndSettle();
    delayed.complete(72);
    await tester.pumpAndSettle();
    expect(_levels(tester), [73]);
    expect(_charging(tester), [true]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('重开后重新订阅充电状态，关闭期间不复用旧标记', (tester) async {
    var charging = true;
    final events = _mockBattery(
      tester,
      () async => 100,
      charging: () => charging,
    );
    await tester.pumpWidget(_rows(1, fixedClock: true));
    await tester.pumpAndSettle();
    expect(_charging(tester), [true]);
    await tester.pumpWidget(const SizedBox.shrink());
    charging = false;
    await tester.pumpWidget(_rows(1, fixedClock: true));
    await tester.pumpAndSettle();
    expect(events.listens, 2);
    expect(_charging(tester), [false]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(events.cancels, 2);
  });

  testWidgets('实际电量变化刷新正式翻页快照，相同电量不重建缓存', (tester) async {
    final first = Completer<int?>();
    var firstRead = true;
    var level = 73;
    final events = _mockBattery(tester, () async {
      if (firstRead) {
        firstRead = false;
        return first.future;
      }
      return level;
    });
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _BatteryPages(),
          store: MemoryReaderProgressStore(),
          bookId: 'battery-snapshot',
          pageTurnMode: PageTurnMode.coverStack,
          onSessionReady: (value) => session = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Object revision() =>
        tester.widget<PageTurnView>(find.byType(PageTurnView)).revision;
    final initialRevision = revision();
    final page = session.page;
    final generation = session.generation;
    expect(_levels(tester), [null]);
    first.complete(level);
    await tester.pumpAndSettle();
    expect(revision(), isNot(initialRevision), reason: '首次异步读回不能保留未知电量快照');
    expect(_levels(tester), [73]);
    final readyRevision = revision();
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(revision(), readyRevision);
    level = 15;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(revision(), isNot(readyRevision));
    expect(_levels(tester), [15]);
    expect(session.page, same(page));
    expect(session.generation, generation, reason: '电量更新不触发正文重排或导航');
    final state = tester.state<PageTurnViewState>(find.byType(PageTurnView));
    expect(state.snapshotCount, greaterThan(0));
    await _verifyChargingSnapshots(tester, events, session);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _verifyChargingSnapshots(
  WidgetTester tester,
  _MockBatteryEvents events,
  ReaderSession session,
) async {
  Object revision() =>
      tester.widget<PageTurnView>(find.byType(PageTurnView)).revision;
  final initial = revision();
  final page = session.page;
  events.send(15, true);
  await tester.pumpAndSettle();
  final chargingRevision = revision();
  expect(chargingRevision, isNot(initial), reason: '电量不变也要更新充电标记快照');
  expect(_charging(tester), [true]);
  expect(session.page, same(page));
  events.send(15, true);
  await tester.pumpAndSettle();
  expect(revision(), chargingRevision, reason: '重复状态不使快照失效');
  final state = tester.state<PageTurnViewState>(find.byType(PageTurnView));
  state.controller.request(true);
  await tester.pumpAndSettle();
  expect(session.page?.pageIndex, 1);
  expect(_charging(tester), [true]);
  events.send(15, false);
  await tester.pumpAndSettle();
  expect(revision(), isNot(chargingRevision));
  expect(_charging(tester), [false]);
  expect(state.snapshotCount, greaterThan(0));
}

class _BatteryPages implements ReaderChapterSource {
  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    for (var page = 0; page < 2; page++)
      PageContent(
        spineIndex: spineIndex,
        pageIndex: page,
        slices: const [],
        usedHeight: 0,
        pageHeight: 400,
        topPadding: 0,
      ),
  ];
}

_MockBatteryEvents _mockBattery(
  WidgetTester tester,
  Future<int?> Function() read, {
  bool? Function()? charging,
}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
    call,
  ) async {
    if (call.method != 'getBatteryStatus') return null;
    final status = charging?.call();
    return {'level': await read(), 'charging': status};
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      null,
    ),
  );
  return _MockBatteryEvents(tester);
}

class _MockBatteryEvents {
  _MockBatteryEvents(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      _eventChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          listens++;
          sink = events;
        },
        onCancel: (_) {
          cancels++;
          sink = null;
        },
      ),
    );
    addTearDown(() => messenger.setMockStreamHandler(_eventChannel, null));
  }

  MockStreamHandlerEventSink? sink;
  int listens = 0;
  int cancels = 0;

  void send(int? level, bool? charging) =>
      sink!.success({'level': level, 'charging': charging});
}

Widget _rows(int count, {bool fixedClock = false}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        for (var row = 0; row < count; row++)
          ReaderCornerRow(
            key: ValueKey(row),
            left: ReaderCornerContent.clockAndBattery,
            right: ReaderCornerContent.progress,
            data: const ReaderCornerData(progress: .125),
            now: fixedClock ? DateTime(2026, 11, 14, 9, 8) : null,
          ),
      ],
    ),
  ),
);

List<int?> _levels(WidgetTester tester) => tester
    .widgetList<ReaderBatteryIcon>(find.byType(ReaderBatteryIcon))
    .map((icon) => icon.level)
    .toList();

List<bool?> _charging(WidgetTester tester) => tester
    .widgetList<ReaderBatteryIcon>(find.byType(ReaderBatteryIcon))
    .map((icon) => icon.charging)
    .toList();

Future<ByteData> _renderIcon(
  WidgetTester tester,
  int? level, {
  bool? charging,
}) async {
  final boundary = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: boundary,
          child: ReaderBatteryIcon(
            level: level,
            charging: charging,
            color: Colors.black,
          ),
        ),
      ),
    ),
  );
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = render.toImageSync(pixelRatio: 4);
  try {
    expect(image.width, _pixelWidth);
    expect(image.height, 48);
    return (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
  } finally {
    image.dispose();
  }
}

int _filledPixels(ByteData pixels) {
  var result = 0;
  for (var y = 12; y < 36; y++) {
    for (var x = 12; x < 68; x++) {
      if (pixels.getUint8((y * _pixelWidth + x) * 4 + 3) > 127) result++;
    }
  }
  return result;
}

int _boltPixels(ByteData pixels) {
  var result = 0;
  for (var y = 0; y < 48; y++) {
    for (var x = 100; x < _pixelWidth; x++) {
      if (pixels.getUint8((y * _pixelWidth + x) * 4 + 3) > 127) result++;
    }
  }
  return result;
}
