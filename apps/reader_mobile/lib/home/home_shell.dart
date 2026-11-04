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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
            if (value == 0) {
              _bookshelfRefreshToken += 1;
            } else if (value == 1) {
              _statsRefreshToken += 1;
            }
          });
        },
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.rate_review_outlined),
            selectedIcon: Icon(Icons.rate_review),
            label: '书评',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
