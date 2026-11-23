import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'rea_micro_models.dart';

/// 清单选书不下载文件，确认后才同步所选图书及其阅读记录。
class ReaMicroLanBookPicker extends StatefulWidget {
  const ReaMicroLanBookPicker({super.key, required this.books});
  final List<ReaMicroLanBookProgress> books;

  @override
  State<ReaMicroLanBookPicker> createState() => _ReaMicroLanBookPickerState();
}

class _ReaMicroLanBookPickerState extends State<ReaMicroLanBookPicker> {
  final _selected = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.books
        .where(
          (book) => '${book.title} ${book.author}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择同步图书'),
        actions: [
          IconButton(
            tooltip: _selected.length == widget.books.length ? '取消全选' : '全选',
            icon: const AppIcon(AppGlyph.multiSelect),
            onPressed: () => setState(() {
              if (_selected.length == widget.books.length) {
                _selected.clear();
              } else {
                _selected.addAll(widget.books.map((book) => book.uuid));
              }
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索书名或作者',
                prefixIcon: AppIcon(AppGlyph.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('没有可同步的图书'))
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, index) {
                      final book = visible[index];
                      return CheckboxListTile(
                        key: ValueKey('lan-book-${book.uuid}'),
                        title: Text(book.title.isEmpty ? '未命名图书' : book.title),
                        subtitle: Text(book.author),
                        value: _selected.contains(book.uuid),
                        onChanged: (value) => setState(() {
                          value == true
                              ? _selected.add(book.uuid)
                              : _selected.remove(book.uuid);
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          key: const ValueKey('lan-sync-selected'),
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set<String>.of(_selected)),
          child: Text('同步所选图书（${_selected.length} 本）'),
        ),
      ),
    );
  }
}
