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
      ),
      ReviewsPage(library: widget.library),
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
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.library_books_outlined),
              activeIcon: Icon(Icons.library_books),
              label: '书架',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: '统计',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.rate_review_outlined),
              activeIcon: Icon(Icons.rate_review),
              label: '书评',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
