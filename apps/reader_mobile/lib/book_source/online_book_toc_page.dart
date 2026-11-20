import 'package:flutter/material.dart';

import 'book_source_models.dart';

/// 完整在线目录按需构建列表，支持查找、倒序和指定章节阅读。
class OnlineBookTocPage extends StatefulWidget {
  const OnlineBookTocPage({
    super.key,
    required this.bookTitle,
    required this.chapters,
    this.currentChapter,
    this.selectable = true,
  });

  final String bookTitle;
  final List<OnlineChapter> chapters;
  final int? currentChapter;
  final bool selectable;

  @override
  State<OnlineBookTocPage> createState() => _OnlineBookTocPageState();
}

class _OnlineBookTocPageState extends State<OnlineBookTocPage> {
  String _query = '';
  bool _reversed = false;

  List<int> get _visibleChapters {
    final query = _query.trim().toLowerCase();
    final indices = [
      for (final (index, chapter) in widget.chapters.indexed)
        if (query.isEmpty ||
            '${index + 1} ${chapter.title} ${chapter.volume}'
                .toLowerCase()
                .contains(query))
          index,
    ];
    return _reversed ? indices.reversed.toList() : indices;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleChapters;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.bookTitle} · 目录'),
        actions: [
          IconButton(
            key: const ValueKey('online-toc-order'),
            tooltip: _reversed ? '正序排列' : '倒序排列',
            onPressed: () => setState(() => _reversed = !_reversed),
            icon: const Icon(Icons.swap_vert),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              key: const ValueKey('online-toc-query'),
              decoration: InputDecoration(
                hintText: '查找章节名称或序号',
                prefixIcon: const Icon(Icons.search),
                suffixText: '${visible.length}/${widget.chapters.length}',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('没有匹配的章节'))
                : ListView.builder(
                    key: const ValueKey('online-toc-list'),
                    itemCount: visible.length,
                    itemBuilder: (context, position) {
                      final index = visible[position];
                      final chapter = widget.chapters[index];
                      return ListTile(
                        key: ValueKey('online-toc-chapter-$index'),
                        selected: widget.currentChapter == index,
                        title: Text('${index + 1}. ${chapter.title}'),
                        subtitle: chapter.volume.isEmpty
                            ? null
                            : Text(chapter.volume),
                        trailing: widget.currentChapter == index
                            ? const Icon(Icons.bookmark_outline)
                            : null,
                        onTap: widget.selectable
                            ? () => Navigator.of(context).pop(index)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
