import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_source_models.dart';
import 'online_book_controller.dart';

/// 在线书籍详情、目录与下载。
class OnlineBookDetailPage extends StatefulWidget {
  const OnlineBookDetailPage({
    super.key,
    required this.controller,
    required this.source,
    required this.book,
  });

  final OnlineBookController controller;
  final BookSource source;
  final OnlineBook book;

  @override
  State<OnlineBookDetailPage> createState() => _OnlineBookDetailPageState();
}

class _OnlineBookDetailPageState extends State<OnlineBookDetailPage> {
  OnlineBook? _info;
  List<OnlineChapter>? _chapters;
  bool _loading = true;
  bool _downloading = false;
  bool _cancelRequested = false;
  String? _error;
  int _completed = 0;
  int _total = 0;
  String _progressMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await widget.controller.service.loadBookInfo(
        widget.source,
        widget.book,
      );
      final chapters = await widget.controller.service.fetchToc(
        widget.source,
        info,
      );
      if (!mounted) return;
      setState(() {
        _info = info;
        _chapters = chapters;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _info = widget.book;
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    final info = _info ?? widget.book;
    setState(() {
      _downloading = true;
      _cancelRequested = false;
      _completed = 0;
      _total = _chapters?.length ?? 0;
      _progressMessage = '准备下载';
    });
    try {
      await widget.controller.downloadAndImport(
        widget.source,
        info,
        onProgress: (completed, total, message) {
          if (!mounted) return;
          setState(() {
            _completed = completed;
            _total = total;
            _progressMessage = message;
          });
        },
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BookSourceException catch (error) {
      if (!mounted) return;
      if (error.code == 'ONLINE_CANCELLED') {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已取消下载')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载失败：${error.message}')));
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('下载失败：$error')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info ?? widget.book;
    return PopScope(
      canPop: !_downloading,
      child: Scaffold(
        appBar: AppBar(title: const Text('书籍详情')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: <Widget>[
                  _header(info),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '详情加载不完整：$_error',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                  if (info.intro.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    Text('简介', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    SelectableText(info.intro),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '目录',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (_chapters != null)
                        Text(
                          '${_chapters!.length} 章',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_chapters == null)
                    TextButton(onPressed: _load, child: const Text('重新读取目录'))
                  else
                    for (final chapter in _chapters!.take(40))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          '${chapter.index + 1}. ${chapter.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  if (_chapters != null && _chapters!.length > 40)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '仅预览前 40 章，下载时会获取完整目录。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: _downloading ? _buildProgress() : _buildDownloadButton(),
          ),
        ),
      ),
    );
  }

  Widget _header(OnlineBook info) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 96,
            height: 130,
            child: info.coverUrl.isEmpty
                ? ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Icon(Icons.menu_book_outlined, size: 38),
                  )
                : Image.network(
                    info.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined, size: 34),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(info.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(info.author.isEmpty ? '未知作者' : info.author),
              const SizedBox(height: 6),
              Text(
                info.sourceName,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (info.kind.isNotEmpty || info.wordCount.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  <String>[
                    if (info.kind.isNotEmpty) info.kind,
                    if (info.wordCount.isNotEmpty) info.wordCount,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (info.lastChapter.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '最新：${info.lastChapter}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgress() {
    final value = _total > 0 ? (_completed / _total).clamp(0.0, 1.0) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LinearProgressIndicator(value: value),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _progressMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              key: const ValueKey<String>('online-book-cancel-download'),
              onPressed: () => setState(() => _cancelRequested = true),
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadButton() {
    final ready = _chapters != null;
    return FilledButton.icon(
      key: const ValueKey<String>('online-book-download'),
      onPressed: ready ? _download : null,
      icon: const AppIcon(AppGlyph.upload),
      label: Text(ready ? '下载并加入书架' : '目录不可用'),
    );
  }
}
