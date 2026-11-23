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
  int? readDays,
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
            readDays: readDays,
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
  testWidgets('里程碑阅读天数显示在作者与时长之间，封面和书名缩小', (tester) async {
    await _pump(
      tester,
      _book(),
      review: _review(),
      readDays: 24,
      duration: const Duration(hours: 12),
    );
    expect(
      tester.getTopLeft(find.text('林川')).dy,
      lessThan(tester.getTopLeft(find.text('阅读 24 天')).dy),
    );
    expect(
      tester.getTopLeft(find.text('阅读 24 天')).dy,
      lessThan(tester.getTopLeft(find.text('12 小时')).dy),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('review-ticket-cover'))).width,
      76,
    );
    final title = find
        .descendant(
          of: find.byKey(const ValueKey('review-ticket-face')),
          matching: find.text('长夜与灯火'),
        )
        .last;
    expect(tester.widget<Text>(title).style?.fontSize, 16);
    expect(tester.takeException(), isNull);
  });
  testWidgets('已写书评显示评分、标记读完日期和真实累计时长', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        _book(),
        review: _review(),
        duration: const Duration(hours: 4, minutes: 24),
      );

      // 书名同时出现在主标题与无封面时的占位封面上。
      expect(find.text('长夜与灯火'), findsWidgets);
      expect(find.textContaining('林川'), findsOneWidget);
      expect(find.text('标记读完'), findsOneWidget);
      expect(find.text('2026.06.10'), findsOneWidget);
      expect(find.text('书评更新'), findsNothing);
      expect(find.text('2026.06.13'), findsNothing);
      expect(_starCount(tester), 5);
      expect(
        find.bySemanticsLabel(
          '长夜与灯火，林川，4 星，有书评正文，标记读完：2026年6月10日，累计阅读4 小时 24 分钟',
        ),
        findsOneWidget,
      );

      // 封面内缩 6dp、垂直居中，宽高保持 3:4。
      final face = tester.getRect(
        find.byKey(const ValueKey<String>('review-ticket-face')),
      );
      final cover = tester.getRect(
        find.byKey(const ValueKey<String>('review-ticket-cover')),
      );
      expect(cover.left, closeTo(face.left + 6, .01));
      expect(cover.center.dy, closeTo(face.center.dy, .01));
      expect(cover.width / cover.height, closeTo(3 / 4, .01));
      expect(cover.right, lessThan(face.right));
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
    // 没有阅读时长时保留空位，不显示占位文案。
    expect(find.textContaining('暂无时长记录'), findsNothing);
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
    expect(find.text('标记读完'), findsOneWidget);
    final cover = tester.getRect(
      find.byKey(const ValueKey<String>('review-ticket-cover')),
    );
    expect(cover.width / cover.height, closeTo(3 / 4, .01));
    await tester.tap(find.byKey(const ValueKey('ticket')));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
