import 'package:flutter/material.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import 'bookshelf_page.dart';
import 'profile_page.dart';
import 'reviews_page.dart';
import 'stats_page.dart';

/// 四底栏应用壳：书架 / 统计 / 书评 / 我的。
class HomeShell extends StatefulWidget {
  /// 创建壳。
  const HomeShell({
    super.key,
    required this.library,
    required this.progressStore,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final ReaderProgressStore progressStore;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _bookshelfRefreshToken = 0;
  int _statsRefreshToken = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navigationTheme = theme.bottomNavigationBarTheme;
    final unselectedColor =
        navigationTheme.unselectedItemColor ??
        theme.colorScheme.onSurfaceVariant;
    final selectedColor =
        navigationTheme.selectedItemColor ?? theme.colorScheme.onSurface;
    final navigationBackground =
        navigationTheme.backgroundColor ?? theme.canvasColor;
    final pages = <Widget>[
      BookshelfPage(
        library: widget.library,
        progressStore: widget.progressStore,
        refreshToken: _bookshelfRefreshToken,
      ),
      StatsPage(
        library: widget.library,
        progressStore: widget.progressStore,
        refreshToken: _statsRefreshToken,
        active: _index == 1,
      ),
      ReviewsPage(library: widget.library, active: _index == 2),
      ProfilePage(library: widget.library),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (value) {
            setState(() {
              _index = value;
              if (value == 0) {
                _bookshelfRefreshToken += 1;
              } else if (value == 1) {
                _statsRefreshToken += 1;
              }
            });
          },
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: _BookshelfIcon(color: unselectedColor),
              activeIcon: _BookshelfIcon(
                color: selectedColor,
                filled: true,
                cutoutColor: navigationBackground,
              ),
              label: '书架',
            ),
            BottomNavigationBarItem(
              icon: _StatsIcon(color: unselectedColor),
              activeIcon: _StatsIcon(color: selectedColor, filled: true),
              label: '统计',
            ),
            BottomNavigationBarItem(
              icon: _ReviewIcon(color: unselectedColor),
              activeIcon: _ReviewIcon(
                color: selectedColor,
                filled: true,
                cutoutColor: navigationBackground,
              ),
              label: '书评',
            ),
            BottomNavigationBarItem(
              icon: _ProfileIcon(color: unselectedColor),
              activeIcon: _ProfileIcon(
                color: selectedColor,
                filled: true,
                cutoutColor: navigationBackground,
              ),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}

class _BookshelfIcon extends StatelessWidget {
  const _BookshelfIcon({
    required this.color,
    this.filled = false,
    this.cutoutColor,
  });

  final Color color;
  final bool filled;
  final Color? cutoutColor;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(24),
    painter: _BookshelfIconPainter(
      color: color,
      filled: filled,
      cutoutColor: cutoutColor,
    ),
  );
}

class _BookshelfIconPainter extends CustomPainter {
  const _BookshelfIconPainter({
    required this.color,
    required this.filled,
    required this.cutoutColor,
  });

  final Color color;
  final bool filled;
  final Color? cutoutColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final outline = Paint()
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final leftBook = RRect.fromLTRBR(
      2.8,
      2.7,
      10.6,
      21.3,
      const Radius.circular(1.2),
    );
    final secondBook = RRect.fromLTRBR(
      12.4,
      3,
      15.1,
      21,
      const Radius.circular(1.2),
    );
    final thirdBook = RRect.fromLTRBR(
      17.3,
      3,
      20,
      21,
      const Radius.circular(1.2),
    );
    canvas.drawRRect(leftBook, outline);
    _drawTiltedBook(canvas, secondBook, outline);
    _drawTiltedBook(canvas, thirdBook, outline);

    final bars = Paint()
      ..color = filled ? cutoutColor! : color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromLTRBR(5.5, 9.6, 8, 11.1, const Radius.circular(0.75)),
      bars,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(5.5, 13.1, 8, 14.6, const Radius.circular(0.75)),
      bars,
    );
    canvas.restore();
  }

  void _drawTiltedBook(Canvas canvas, RRect book, Paint paint) {
    canvas.save();
    canvas.translate(book.center.dx, book.center.dy);
    canvas.rotate(-0.16);
    canvas.translate(-book.center.dx, -book.center.dy);
    canvas.drawRRect(book, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BookshelfIconPainter oldDelegate) =>
      color != oldDelegate.color ||
      filled != oldDelegate.filled ||
      cutoutColor != oldDelegate.cutoutColor;
}

class _ProfileIcon extends StatelessWidget {
  const _ProfileIcon({
    required this.color,
    this.filled = false,
    this.cutoutColor,
  });

  final Color color;
  final bool filled;
  final Color? cutoutColor;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(24),
    painter: _ProfileIconPainter(
      color: color,
      filled: filled,
      cutoutColor: cutoutColor,
    ),
  );
}

class _ProfileIconPainter extends CustomPainter {
  const _ProfileIconPainter({
    required this.color,
    required this.filled,
    required this.cutoutColor,
  });

  final Color color;
  final bool filled;
  final Color? cutoutColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final circle = Path()
      ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 10.2));
    final paint = Paint()
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..color = color;
    canvas.drawPath(circle, paint);

    final person = Path()
      ..addOval(Rect.fromCircle(center: const Offset(12, 8.65), radius: 2.7))
      ..moveTo(5.35, 19.6)
      ..cubicTo(6.05, 15.8, 8.4, 13.75, 12, 13.75)
      ..cubicTo(15.6, 13.75, 17.95, 15.8, 18.65, 19.6)
      ..cubicTo(16.95, 20.85, 14.65, 21.5, 12, 21.5)
      ..cubicTo(9.35, 21.5, 7.05, 20.85, 5.35, 19.6)
      ..close();
    final silhouette = Paint()
      ..style = PaintingStyle.fill
      ..color = filled ? cutoutColor! : color;
    canvas.save();
    canvas.clipPath(circle);
    canvas.drawPath(person, silhouette);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ProfileIconPainter oldDelegate) =>
      color != oldDelegate.color ||
      filled != oldDelegate.filled ||
      cutoutColor != oldDelegate.cutoutColor;
}

class _StatsIcon extends StatelessWidget {
  const _StatsIcon({required this.color, this.filled = false});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(24),
    painter: _StatsIconPainter(color: color, filled: filled),
  );
}

class _StatsIconPainter extends CustomPainter {
  const _StatsIconPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    for (final bar in const <Rect>[
      Rect.fromLTRB(3.1, 11.7, 7.5, 20.5),
      Rect.fromLTRB(9.8, 7, 14.2, 20.5),
      Rect.fromLTRB(16.5, 2.7, 20.9, 20.5),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(1.2)),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StatsIconPainter oldDelegate) =>
      color != oldDelegate.color || filled != oldDelegate.filled;
}

class _ReviewIcon extends StatelessWidget {
  const _ReviewIcon({
    required this.color,
    this.filled = false,
    this.cutoutColor,
  });

  final Color color;
  final bool filled;
  final Color? cutoutColor;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(24),
    painter: _ReviewIconPainter(
      color: color,
      filled: filled,
      cutoutColor: cutoutColor,
    ),
  );
}

class _ReviewIconPainter extends CustomPainter {
  const _ReviewIconPainter({
    required this.color,
    required this.filled,
    required this.cutoutColor,
  });

  final Color color;
  final bool filled;
  final Color? cutoutColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final outer = Paint()
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final paper = Paint()..color = color;
    final left = RRect.fromLTRBR(
      2.8,
      2.7,
      10.1,
      21.3,
      const Radius.circular(1.2),
    );
    final middle = RRect.fromLTRBR(
      10.8,
      8.5,
      16,
      21.3,
      const Radius.circular(1.2),
    );
    final right = RRect.fromLTRBR(
      17.4,
      2.7,
      20.1,
      20.2,
      const Radius.circular(1.2),
    );
    canvas.save();
    canvas.translate(right.center.dx, right.center.dy);
    canvas.rotate(-0.17);
    canvas.translate(-right.center.dx, -right.center.dy);
    canvas.drawRRect(right, outer);
    canvas.restore();
    canvas.drawRRect(left, outer);
    canvas.drawRRect(middle, outer);
    if (filled) {
      final cut = Paint()..color = cutoutColor!;
      canvas.drawRRect(
        RRect.fromLTRBR(11.7, 14, 15.1, 16.2, const Radius.circular(1.1)),
        cut,
      );
    } else {
      canvas.drawRRect(
        RRect.fromLTRBR(11.9, 14, 14.9, 15.4, const Radius.circular(0.7)),
        paper,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReviewIconPainter oldDelegate) =>
      color != oldDelegate.color ||
      filled != oldDelegate.filled ||
      cutoutColor != oldDelegate.cutoutColor;
}
