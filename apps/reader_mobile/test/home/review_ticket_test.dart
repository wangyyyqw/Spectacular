import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/review_ticket.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/icons/app_icon.dart';

BookEntry _book({DateTime? lastReadAt}) => BookEntry(
  id: 'ticket-book',
  title: '长夜与灯火',
  author: '林川',
  filePath: '',
  addedAt: DateTime(2026, 1),
  lastReadAt: lastReadAt,
);

BookReview _review() => BookReview(
  bookId: 'ticket-book',
  rating: 4,
  content: '写到深夜仍舍不得放下。',
  createdAt: DateTime(2026, 6, 10),
  updatedAt: DateTime(2026, 6, 13),
);

Future<void> _pump(
  WidgetTester tester,
  BookEntry book, {
  BookReview? review,
  Duration? duration,
  VoidCallback? onTap,
  Size size = const Size(360, 800),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ReviewTicket(
            key: const ValueKey('ticket'),
            book: book,
            review: review,
            duration: duration,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int _starCount(WidgetTester tester) => tester
    .widgetList<AppIcon>(find.byType(AppIcon))
    .where((icon) => icon.glyph == AppGlyph.star)
    .length;

void main() {
  testWidgets('已写书评显示评分、更新日期和真实累计时长', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        _book(),
        review: _review(),
        duration: const Duration(hours: 4, minutes: 24),
      );

      expect(find.text('长夜与灯火'), findsOneWidget);
      expect(find.text('林川'), findsOneWidget);
      expect(find.text('书评更新'), findsOneWidget);
      expect(find.text('2026.06.13'), findsOneWidget);
      expect(_starCount(tester), 5);
      expect(
        find.bySemanticsLabel(
          '长夜与灯火，林川，4 星，有书评正文，书评更新：2026年6月13日，累计阅读4 小时 24 分钟',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('待写书评不伪造评分或时长，只显示最近阅读日期', (tester) async {
    await _pump(
      tester,
      _book(lastReadAt: DateTime(2026, 6, 9)),
      duration: null,
    );

    expect(find.text('写书评'), findsOneWidget);
    expect(find.text('最近阅读'), findsOneWidget);
    expect(find.text('2026.06.09'), findsOneWidget);
    expect(find.text('暂无时长记录'), findsOneWidget);
    expect(_starCount(tester), 0);
  });

  testWidgets('窄屏双倍字号改为上下票纸，整卡可点且不溢出', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      _book(),
      review: _review(),
      duration: const Duration(minutes: 59),
      onTap: () => taps++,
      size: const Size(280, 900),
      scale: 2,
    );

    expect(find.text('长夜与灯火'), findsOneWidget);
    expect(find.text('书评更新'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ticket')));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
