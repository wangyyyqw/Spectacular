part of 'image_preview_page.dart';

/// 相邻帧只持有缩略图；当前帧克隆原图，失去选择或关闭时释放。
class _ImagePreviewFrame extends StatefulWidget {
  const _ImagePreviewFrame({
    super.key,
    required this.item,
    required this.active,
    this.onReady,
  });

  final ImagePreviewItem item;
  final bool active;
  final ValueChanged<bool>? onReady;

  @override
  State<_ImagePreviewFrame> createState() => _ImagePreviewFrameState();
}

class _ImagePreviewFrameState extends State<_ImagePreviewFrame> {
  ui.Image? _image;
  var _loading = true;
  var _request = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void didUpdateWidget(_ImagePreviewFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.item != widget.item) {
      _loadCurrent();
    }
  }

  void _loadCurrent() {
    _request++;
    final thumbnail = widget.item.thumbnail?.call()?.clone();
    _image?.dispose();
    _image = thumbnail;
    _loading = widget.active;
    _notifyReady();
    unawaited(
      _load(
        widget.active ? widget.item.loadOriginal : widget.item.loadThumbnail,
      ),
    );
  }

  Future<void> _load(Future<ui.Image?> Function()? loader) async {
    if (loader == null) return;
    final request = ++_request;
    ui.Image? original;
    try {
      original = await loader();
    } catch (_) {
      // 加载器抛错与缺图采用相同的可重试状态。
    }
    if (!mounted || request != _request) return;
    final image = original?.clone();
    setState(() {
      _loading = false;
      if (image != null) {
        _image?.dispose();
        _image = image;
      }
    });
    _notifyReady();
  }

  void _notifyReady() {
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) widget.onReady?.call(_image != null);
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image != null) {
      return ExcludeSemantics(
        child: SizedBox.expand(
          child: RawImage(
            key: widget.active ? const ValueKey('preview-image') : null,
            image: image,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    return widget.active ? _placeholder() : const SizedBox.expand();
  }

  Widget _placeholder() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          semanticsLabel: '正在加载图片',
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('图片无法加载', style: TextStyle(color: Colors.white)),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () {
              setState(() => _loading = true);
              unawaited(_load(widget.item.loadOriginal));
            },
            icon: const AppIcon(AppGlyph.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
