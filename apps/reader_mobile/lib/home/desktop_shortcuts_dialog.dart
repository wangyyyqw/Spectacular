import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

/// 与当前页面一致的桌面键位说明，使用系统对应的修饰键名称。
Future<void> showDesktopShortcuts(
  BuildContext context, {
  List<BottomNavigationBarItem>? destinations,
}) {
  final mac = Theme.of(context).platform == TargetPlatform.macOS;
  final command = mac ? '⌘' : 'Ctrl';
  final editor = destinations == null;
  final rows = destinations == null
      ? [
          ('$command + S', '保存书籍并继续编辑'),
          ('$command + Shift + S', '导出 EPUB'),
          ('$command + F', '查找当前文档'),
          ('$command + Shift + F', '全书查找替换'),
          ('Ctrl + Tab / Ctrl + Shift + Tab', '切换源码标签'),
          ('$command + W', '关闭当前源码标签'),
          ('$command + G', '跳转到行或行:列'),
          ('Alt + Z', '切换自动换行'),
          ('Ctrl + Space', '唤起 CSS 补全'),
          ('Esc', '关闭补全、查找或弹窗'),
        ]
      : [
          (
            '$command + 1…${destinations.length}',
            '切换${destinations.map((item) => item.label).join('、')}',
          ),
          ('$command + F', '搜索当前书架或笔记'),
          ('$command + O', '书架导入书籍 / 编辑页打开 EPUB'),
          ('Tab / 方向键', '移动书籍焦点'),
          ('Enter', '打开书籍，多选时切换选择'),
          ('Space', '选择当前书籍'),
          ('$command + 点击', '逐本添加或取消选择'),
          ('Shift + 点击 / Shift + Space', '从上次选择处连续选择'),
          ('$command + A', '选择当前搜索和分组内的书籍'),
          (mac ? '⌘ + Delete' : 'Delete', '确认删除所选书籍'),
          ('Shift + F10', '打开当前书籍菜单'),
          ('Esc', '退出搜索、多选或关闭弹窗'),
        ];
  return showReaderDialog<void>(
    context: context,
    builder: (context) => ReaderFrostedAlertDialog(
      title: Text(editor ? '编辑器快捷键' : '桌面快捷键'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (keys, action) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: LayoutBuilder(
                    builder: (_, bounds) => bounds.maxWidth < 400
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(action),
                              Text(
                                keys,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: Text(action)),
                              const SizedBox(width: 24),
                              Flexible(
                                child: Text(
                                  keys,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
