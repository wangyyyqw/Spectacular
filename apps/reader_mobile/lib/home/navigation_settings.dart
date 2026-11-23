import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../library/library_store.dart';
import '../rea_micro/rea_micro_controller.dart';

/// 底栏按稳定入口身份保存，隐藏入口不改变其他页面的索引。
enum HomeDestination {
  bookshelf('书架'),
  discover('发现'),
  stats('统计'),
  notes('笔记'),
  profile('我的');

  const HomeDestination(this.label);
  final String label;
}

class NavigationSettings extends ChangeNotifier {
  NavigationSettings(this.library, this.account) {
    account.addListener(_accountChanged);
  }

  final LibraryStore library;
  final ReaMicroController account;
  static const storageKey = 'home.navigation.visible';
  static const discoveryPromptKey = 'home.navigation.discoveryPromptHandled';
  Set<HomeDestination> _enabled = {
    HomeDestination.bookshelf,
    HomeDestination.stats,
    HomeDestination.notes,
    HomeDestination.profile,
  };
  bool initialized = false;
  bool discoveryPromptHandled = false;

  bool get statisticsAllowed => !account.signedIn || account.hasQingShi;
  bool selected(HomeDestination entry) => _enabled.contains(entry);
  bool visible(HomeDestination entry) =>
      selected(entry) && (entry != HomeDestination.stats || statisticsAllowed);

  Future<void> initialize() async {
    final raw = await library.getSetting(storageKey);
    try {
      if (raw != null) {
        final names = (jsonDecode(raw) as List).whereType<String>().toSet();
        _enabled = HomeDestination.values
            .where((e) => names.contains(e.name))
            .toSet();
      }
    } catch (_) {
      // 损坏的底栏设置使用默认入口。
    }
    _enabled.addAll([HomeDestination.bookshelf, HomeDestination.profile]);
    discoveryPromptHandled =
        await library.getSetting(discoveryPromptKey) == 'true';
    initialized = true;
    notifyListeners();
  }

  Future<void> setVisible(HomeDestination entry, bool value) async {
    if (entry == HomeDestination.bookshelf ||
        entry == HomeDestination.profile) {
      return;
    }
    if (entry == HomeDestination.stats && !statisticsAllowed) return;
    final next = Set<HomeDestination>.of(_enabled);
    value ? next.add(entry) : next.remove(entry);
    await library.setSetting(
      storageKey,
      jsonEncode(next.map((e) => e.name).toList()),
    );
    _enabled = next;
    notifyListeners();
  }

  Future<void> markDiscoveryPromptHandled() async {
    await library.setSetting(discoveryPromptKey, 'true');
    discoveryPromptHandled = true;
  }

  void _accountChanged() => notifyListeners();

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    super.dispose();
  }
}
