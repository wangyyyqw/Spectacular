part of 'book_editor_tools.dart';

enum _FileGroup {
  text('正文', AppGlyph.article),
  styles('样式', AppGlyph.formatPaint),
  images('图片', AppGlyph.image),
  fonts('字体', AppGlyph.textFields),
  other('其他资源', AppGlyph.folder);

  const _FileGroup(this.label, this.icon);
  final String label;
  final AppGlyph icon;
}

const _rasterExtensions = {
  'image/jpeg': ['jpg', 'jpeg'],
  'image/png': ['png'],
  'image/gif': ['gif'],
  'image/webp': ['webp'],
};

String _resourceMediaType(EpubEditResource resource) {
  final declared = resource.mediaType.split(';').first.trim().toLowerCase();
  return switch (declared) {
    'image/jpg' || 'image/pjpeg' => 'image/jpeg',
    'image/x-png' => 'image/png',
    '' || 'application/octet-stream' => switch (p.posix
        .extension(resource.path)
        .toLowerCase()) {
      '.woff2' => 'font/woff2',
      '.ttc' || '.otc' => 'font/collection',
      '.eot' => 'application/vnd.ms-fontobject',
      '.bmp' => 'image/bmp',
      '.tif' || '.tiff' => 'image/tiff',
      '.avif' => 'image/avif',
      '.xht' => 'application/xhtml+xml',
      '.xml' => 'application/xml',
      '.txt' => 'text/plain',
      _ => OpfParser.inferMediaType(resource.path),
    },
    _ => declared,
  };
}

class _BrowserFile {
  _BrowserFile(this.resource)
    : searchPath = resource.path.toLowerCase(),
      mediaType = _resourceMediaType(resource);

  final EpubEditResource resource;
  final String searchPath;
  final String mediaType;
  String get path => resource.path;
  bool get raster => _rasterExtensions.containsKey(mediaType);
  bool get source =>
      mediaType.startsWith('text/') ||
      mediaType.endsWith('+xml') ||
      mediaType == 'application/xml';

  _FileGroup get group {
    if (mediaType == 'application/xhtml+xml' || mediaType == 'text/html') {
      return _FileGroup.text;
    }
    if (mediaType == 'text/css') return _FileGroup.styles;
    if (mediaType.startsWith('image/')) return _FileGroup.images;
    if (mediaType.startsWith('font/') ||
        mediaType.startsWith('application/font-') ||
        mediaType.startsWith('application/x-font-') ||
        mediaType == 'application/vnd.ms-opentype' ||
        mediaType == 'application/vnd.ms-fontobject') {
      return _FileGroup.fonts;
    }
    return _FileGroup.other;
  }
}

Map<_FileGroup, List<_BrowserFile>> _indexFiles(EpubEditSession session) {
  final groups = {
    for (final group in _FileGroup.values) group: <_BrowserFile>[],
  };
  final remaining = {
    for (final resource in session.resources)
      resource.path: _BrowserFile(resource),
  };
  for (final path in session.spinePaths) {
    if (remaining.remove(path) case final file?) {
      groups[_FileGroup.text]!.add(file);
    }
  }
  for (final path in remaining.keys.toList()..sort()) {
    final file = remaining[path]!;
    groups[file.group]!.add(file);
  }
  return groups;
}

class BookEditorFiles extends StatefulWidget {
  const BookEditorFiles({
    super.key,
    required this.editor,
    required this.onOpen,
  });
  final BookEditorController editor;
  final VoidCallback onOpen;

  @override
  State<BookEditorFiles> createState() => _BookEditorFilesState();
}

class _BookEditorFilesState extends State<BookEditorFiles> {
  final _filter = TextEditingController();
  final _scroll = ScrollController();
  final _expanded = {_FileGroup.text};
  EpubEditSession? _session;
  int _revision = -1;
  late Map<_FileGroup, List<_BrowserFile>> _index;
  late Map<_FileGroup, List<_BrowserFile>> _visible;
  String _query = '';

  @override
  void dispose() {
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _applyFilter() {
    if (_query.isEmpty) {
      _visible = _index;
      return;
    }
    _visible = {};
    for (final group in _index.entries) {
      final matches = group.value
          .where((file) => file.searchPath.contains(_query))
          .toList(growable: false);
      if (matches.isNotEmpty) _visible[group.key] = matches;
    }
  }

  void _filterChanged() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _query = _filter.text.trim().toLowerCase();
      _applyFilter();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.editor,
    builder: (context, _) {
      final session = widget.editor.session;
      if (_session != session || _revision != session.revision) {
        _index = _indexFiles(session);
        _session = session;
        _revision = session.revision;
        _applyFilter();
      }
      return Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 4),
            title: Text('书籍浏览器', style: Theme.of(context).textTheme.titleSmall),
            trailing: IconButton(
              tooltip: '新增文件',
              icon: const AppIcon(AppGlyph.add),
              onPressed: () =>
                  BookEditorTools(context, widget.editor).addResource(),
            ),
          ),
          _filterField(),
          const Divider(height: 1),
          Expanded(child: _fileList()),
        ],
      );
    },
  );

  Widget _filterField() {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Material(
        color: ReaderDrawerStyle.searchSurfaceOf(theme),
        borderRadius: border.borderRadius,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        child: TextField(
          controller: _filter,
          style: theme.textTheme.bodyMedium,
          onChanged: (_) => _filterChanged(),
          decoration: InputDecoration(
            hintText: '文件名或路径',
            isDense: true,
            filled: true,
            fillColor: ReaderDrawerStyle.searchSurfaceOf(theme),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
            prefixIconConstraints: const BoxConstraints.tightFor(
              width: 40,
              height: 40,
            ),
            suffixIconConstraints: const BoxConstraints.tightFor(
              width: 40,
              height: 40,
            ),
            prefixIcon: AppIcon(
              AppGlyph.search,
              size: 20,
              color: ReaderDrawerStyle.mutedOf(theme),
            ),
            suffixIcon: _filter.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除筛选',
                    icon: const AppIcon(AppGlyph.close, size: 16),
                    onPressed: () {
                      _filter.clear();
                      _filterChanged();
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _fileList() {
    if (_visible.isEmpty) return const Center(child: Text('没有匹配的文件'));
    return CustomScrollView(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        for (final group in _visible.entries) ...[
          SliverToBoxAdapter(
            child: _groupHeader(group.key, group.value.length),
          ),
          if (_query.isNotEmpty || _expanded.contains(group.key))
            SliverList.builder(
              itemCount: group.value.length,
              itemBuilder: (_, index) => _fileRow(group.value[index]),
            ),
        ],
      ],
    );
  }

  Widget _groupHeader(_FileGroup group, int count) {
    final canToggle = count > 0 && _query.isEmpty;
    final expanded = _expanded.contains(group);
    return Semantics(
      expanded: canToggle ? expanded : null,
      child: ListTile(
        dense: true,
        minTileHeight: 32,
        minLeadingWidth: 18,
        horizontalTitleGap: 8,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: AppIcon(group.icon, size: 18),
        title: Text(group.label, style: Theme.of(context).textTheme.labelLarge),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$count', style: Theme.of(context).textTheme.bodySmall),
            if (canToggle) ...[
              const SizedBox(width: 4),
              AppIcon(
                expanded ? AppGlyph.chevronDown : AppGlyph.chevronRight,
                size: 16,
              ),
            ],
          ],
        ),
        onTap: !canToggle
            ? null
            : () => setState(
                () => expanded ? _expanded.remove(group) : _expanded.add(group),
              ),
      ),
    );
  }

  Widget _fileRow(_BrowserFile file) {
    return GestureDetector(
      onSecondaryTapDown: (details) => showBookEditorFileMenu(
        context,
        widget.editor,
        file.path,
        details.globalPosition,
      ),
      child: ListTile(
        key: ValueKey(file.path),
        dense: true,
        minTileHeight: 32,
        horizontalTitleGap: 0,
        minVerticalPadding: 2,
        contentPadding: const EdgeInsetsDirectional.only(start: 20),
        selected: widget.editor.activePath == file.path,
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        title: Tooltip(
          message: file.path,
          child: Text(
            p.posix.basename(file.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: _fileMenu(file),
        onTap: () => _open(file),
      ),
    );
  }

  Widget _fileMenu(_BrowserFile file) => PopupMenuButton<String>(
    tooltip: '文件操作',
    enabled: !widget.editor.busy,
    icon: const AppIcon(AppGlyph.more, size: 18),
    onSelected: (action) =>
        BookEditorTools(context, widget.editor).fileAction(file.path, action),
    itemBuilder: (context) =>
        bookEditorFileMenuItems(context, widget.editor, file.path),
  );

  void _open(_BrowserFile file) {
    if (file.raster) {
      _showImage(file.path);
    } else if (file.source) {
      widget.editor.showSource(file.path);
      widget.onOpen();
    } else {
      recordAppEvent('editor_file_info_opened');
    }
  }

  void _showImage(String path) {
    final editor = widget.editor;
    final bytes = editor.session.readBytes(path)!;
    _showEditorDialog<void>(
      context: context,
      builder: (context) => ReaderFrostedDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: InteractiveViewer(child: Image.memory(bytes))),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭图片'),
            ),
            TextButton(
              onPressed: () async {
                if (await BookEditorTools(
                      context,
                      editor,
                    ).replaceImageResource(path) &&
                    context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('替换图片资源（全书引用生效）'),
            ),
          ],
        ),
      ),
    );
  }
}
