import 'package:flutter/material.dart';

import 'navigation_settings.dart';

/// 可隐藏发现、统计和笔记；书架与我的保留为内容和设置入口。
class NavigationSettingsPage extends StatelessWidget {
  const NavigationSettingsPage({super.key, required this.settings});
  final NavigationSettings settings;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('底栏设置')),
    body: ListenableBuilder(
      listenable: settings,
      builder: (context, _) => ListView(
        children: [
          for (final entry in HomeDestination.values)
            SwitchListTile(
              key: ValueKey('navigation-setting-${entry.name}'),
              title: Text(entry.label),
              subtitle:
                  entry == HomeDestination.stats && !settings.statisticsAllowed
                  ? const Text('需要阅微青士权限')
                  : null,
              value: settings.visible(entry),
              onChanged:
                  entry == HomeDestination.bookshelf ||
                      entry == HomeDestination.profile ||
                      (entry == HomeDestination.stats &&
                          !settings.statisticsAllowed)
                  ? null
                  : (value) => settings.setVisible(entry, value),
            ),
        ],
      ),
    ),
  );
}
