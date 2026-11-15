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
              icon: Icon(Icons.library_books_outlined),
              activeIcon: Icon(Icons.library_books_rounded),
              label: '书架',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.insights_outlined),
              activeIcon: Icon(Icons.insights_rounded),
              label: '统计',
            ),
            BottomNavigationBarItem(
              icon: _BooksIcon(color: unselectedColor),
              activeIcon: _BooksIcon(
                color: selectedColor,
                filled: true,
                cutoutColor: navigationBackground,
              ),
              label: '书评',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person_rounded),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}

class _BooksIcon extends StatelessWidget {
  const _BooksIcon({
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
    painter: _BooksIconPainter(
      color: color,
      filled: filled,
      cutoutColor: cutoutColor,
    ),
  );
}

class _BooksIconPainter extends CustomPainter {
  const _BooksIconPainter({
    required this.color,
    required this.filled,
    required this.cutoutColor,
  });

  final Color color;
  final bool filled;
  final Color? cutoutColor;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final outer = Paint()
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.7 * sx
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final paper = Paint()..color = color;
    final left = RRect.fromLTRBR(
      3.5 * sx,
      3 * sy,
      10 * sx,
      21 * sy,
      Radius.circular(1.2 * sx),
    );
    final middle = RRect.fromLTRBR(
      10 * sx,
      9 * sy,
      16.5 * sx,
      21 * sy,
      Radius.circular(1.2 * sx),
    );
    final right = RRect.fromLTRBR(
      18.5 * sx,
      2.7 * sy,
      21.2 * sx,
      20.2 * sy,
      Radius.circular(1.2 * sx),
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
        RRect.fromLTRBR(
          11.1 * sx,
          14 * sy,
          15.4 * sx,
          16.4 * sy,
          Radius.circular(1.2 * sx),
        ),
        cut,
      );
    } else {
      canvas.drawRRect(
        RRect.fromLTRBR(
          11.3 * sx,
          14 * sy,
          15.2 * sx,
          15.4 * sy,
          Radius.circular(0.7 * sx),
        ),
        paper,
      );
    }
  }

  @override
  bool shouldRepaint(_BooksIconPainter oldDelegate) =>
      color != oldDelegate.color ||
      filled != oldDelegate.filled ||
      cutoutColor != oldDelegate.cutoutColor;
}
