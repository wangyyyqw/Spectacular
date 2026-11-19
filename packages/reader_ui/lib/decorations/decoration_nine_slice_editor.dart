import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import 'decoration_image_codec.dart';
import 'decoration_image_store.dart';
import 'decoration_painter.dart';
import 'decoration_style.dart';
import 'style_controls.dart';

class ReaderDecorationNineSliceSelection {
  const ReaderDecorationNineSliceSelection(this.nineSlice, {this.path});
  final ReaderDecorationNineSlice nineSlice;
  final String? path;
}

class ReaderDecorationNineSliceButton extends StatefulWidget {
  const ReaderDecorationNineSliceButton({
    super.key,
    required this.path,
    required this.images,
    required this.value,
    required this.onChanged,
  });

  final String path;
  final ReaderDecorationImageStore images;
  final ReaderDecorationNineSlice? value;
  final ValueChanged<ReaderDecorationNineSliceSelection> onChanged;

  @override
  State<ReaderDecorationNineSliceButton> createState() =>
      _ReaderDecorationNineSliceButtonState();
}

class _ReaderDecorationNineSliceButtonState
    extends State<ReaderDecorationNineSliceButton> {
  bool _loading = false;

  Future<void> _edit() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    ReaderDecorationDecodedImage? decoded;
    var transferred = false;
    try {
      decoded = await ReaderDecorationImageCodec.decode(
        await widget.images.loadImage(widget.path),
      );
      if (!mounted) return;
      final loaded = decoded;
      setState(() => _loading = false);
      final imageStore = widget.images;
      final next =
          await showModalBottomSheet<ReaderDecorationNineSliceSelection>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            enableDrag: false,
            builder: (_) {
              transferred = true;
              return ReaderDecorationNineSliceEditor(
                image: loaded.image,
                value:
                    widget.value ??
                    loaded.nineSlice ??
                    const ReaderDecorationNineSlice(),
                disposeImage: true,
                saveImage: imageStore is ReaderDecorationNinePatchImageStore
                    ? imageStore.saveNinePatch
                    : null,
              );
            },
          );
      if (next != null && mounted) widget.onChanged(next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('图片无法读取，请重新导入')));
      }
    } finally {
      if (!transferred) decoded?.image.dispose();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey('decoration-nine-slice-edit'),
    onPressed: _loading ? null : _edit,
    icon: _loading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const AppIcon(AppGlyph.formatPaint),
    label: Text(widget.value == null ? '转为点九背景' : '编辑点九内容区'),
  );
}

class ReaderDecorationNineSliceEditor extends StatefulWidget {
  const ReaderDecorationNineSliceEditor({
    super.key,
    required this.image,
    this.value = const ReaderDecorationNineSlice(),
    this.disposeImage = false,
    this.saveImage,
  });

  final ui.Image image;
  final ReaderDecorationNineSlice value;
  final bool disposeImage;
  final Future<String> Function(Uint8List bytes)? saveImage;

  @override
  State<ReaderDecorationNineSliceEditor> createState() =>
      _ReaderDecorationNineSliceEditorState();
}

class _ReaderDecorationNineSliceEditorState
    extends State<ReaderDecorationNineSliceEditor> {
  late ReaderDecorationNineSlice _value =
      ReaderDecorationImageCodec.pixelAligned(widget.image, widget.value);
  int? _handle;
  Offset _dragStart = Offset.zero;
  Rect _dragRect = Rect.zero;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    if (widget.disposeImage) widget.image.dispose();
    super.dispose();
  }

  void _changeContent(Rect rect) =>
      setState(() => _value = _value.withContent(rect));

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saveImage = widget.saveImage;
      final nineSlice = ReaderDecorationImageCodec.pixelAligned(
        widget.image,
        _value,
      );
      final path = saveImage == null
          ? null
          : await saveImage(
              await ReaderDecorationImageCodec.encodeNinePatch(
                widget.image,
                nineSlice,
              ),
            );
      if (mounted) {
        Navigator.of(context)
            .pop(ReaderDecorationNineSliceSelection(nineSlice, path: path));
      }
    } catch (_) {
      if (mounted) setState(() => _error = '点九图片保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Material(
      key: const ValueKey('decoration-nine-slice-editor'),
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '点九拉伸',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '取消',
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const AppIcon(AppGlyph.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('图案随文字大小缩放，长文字只拉伸中间，保留边角。'),
                      const SizedBox(height: 12),
                      _samples(context),
                      const SizedBox(height: 16),
                      _sourceEditor(),
                      const SizedBox(height: 8),
                      const Text('拖动橙框或四角，把内容区放在写文字的位置。内容区高度对应一行文字。'),
                      const SizedBox(height: 12),
                      for (var edge = 0; edge < 4; edge++) _inset(edge),
                      ReaderStyleSlider(
                        label: '图案缩放',
                        value: _value.scale,
                        min: 0.25,
                        max: 3,
                        divisions: 55,
                        digits: 2,
                        suffix: ' 倍',
                        onChanged: (scale) => setState(() {
                          _value = ReaderDecorationNineSlice(
                            slice: _value.slice,
                            content: _value.content,
                            scale: scale,
                          );
                        }),
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('decoration-nine-slice-reset'),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _value = const ReaderDecorationNineSlice();
                          }),
                    child: const Text('重置'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('decoration-nine-slice-save'),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '正在保存…' : '使用点九背景'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _samples(BuildContext context) => Container(
    key: const ValueKey('decoration-nine-slice-preview'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(4),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final painter = _NineSliceSamplePainter(
          widget.image,
          _value,
          Theme.of(context).textTheme.bodyMedium!,
          MediaQuery.textScalerOf(context),
        );
        return CustomPaint(
          size: Size(
            constraints.maxWidth,
            painter.heightFor(constraints.maxWidth),
          ),
          painter: painter,
        );
      },
    ),
  );

  Widget _sourceEditor() => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(
        constraints.maxWidth,
        (constraints.maxWidth * widget.image.height / widget.image.width).clamp(
          110.0,
          240.0,
        ),
      );
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
        size,
      );
      final imageRect = Alignment.center.inscribe(
        fitted.destination,
        Offset.zero & size,
      );
      return GestureDetector(
        key: const ValueKey('decoration-nine-slice-source'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (details) => _startDrag(details.localPosition, imageRect),
        onPanUpdate: (details) => _updateDrag(details.localPosition, imageRect),
        onPanEnd: (_) => _handle = null,
        child: CustomPaint(
          size: size,
          painter: _NineSliceSourcePainter(
            widget.image,
            imageRect,
            _value.content,
          ),
        ),
      );
    },
  );

  Offset _normalized(Offset position, Rect image) => Offset(
    (position.dx - image.left) / image.width,
    (position.dy - image.top) / image.height,
  );

  void _startDrag(Offset position, Rect image) {
    final rect = _value.content;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    var distance = 28.0;
    _handle = null;
    for (var index = 0; index < corners.length; index++) {
      final point =
          image.topLeft +
          Offset(
            corners[index].dx * image.width,
            corners[index].dy * image.height,
          );
      final candidate = (position - point).distance;
      if (candidate < distance) {
        distance = candidate;
        _handle = index;
      }
    }
    final normalized = _normalized(position, image);
    if (_handle == null && rect.contains(normalized)) _handle = 4;
    _dragStart = normalized;
    _dragRect = rect;
  }

  void _updateDrag(Offset position, Rect image) {
    final handle = _handle;
    if (handle == null) return;
    final delta = _normalized(position, image) - _dragStart;
    if (handle == 4) {
      _changeContent(
        _dragRect.shift(
          Offset(
            delta.dx.clamp(-_dragRect.left, 1 - _dragRect.right),
            delta.dy.clamp(-_dragRect.top, 1 - _dragRect.bottom),
          ),
        ),
      );
      return;
    }
    final minWidth = 1 / widget.image.width;
    final minHeight = 1 / widget.image.height;
    final left = handle == 0 || handle == 3;
    final top = handle == 0 || handle == 1;
    _changeContent(
      Rect.fromLTRB(
        left
            ? (_dragRect.left + delta.dx).clamp(0.0, _dragRect.right - minWidth)
            : _dragRect.left,
        top
            ? (_dragRect.top + delta.dy).clamp(
                0.0,
                _dragRect.bottom - minHeight,
              )
            : _dragRect.top,
        left
            ? _dragRect.right
            : (_dragRect.right + delta.dx).clamp(
                _dragRect.left + minWidth,
                1.0,
              ),
        top
            ? _dragRect.bottom
            : (_dragRect.bottom + delta.dy).clamp(
                _dragRect.top + minHeight,
                1.0,
              ),
      ),
    );
  }

  Widget _inset(int edge) {
    final content = _value.content;
    final dimension = (edge < 2 ? widget.image.height : widget.image.width)
        .toDouble();
    final fraction = [
      content.top,
      1 - content.bottom,
      content.left,
      1 - content.right,
    ][edge];
    final opposite = [
      1 - content.bottom,
      content.top,
      1 - content.right,
      content.left,
    ][edge];
    final maxValue = ((1 - opposite) * dimension - 1).clamp(0.0, dimension);
    final value = (fraction * dimension).clamp(0.0, maxValue);
    return Column(
      children: [
        Row(
          children: [
            Text(['上边距', '下边距', '左边距', '右边距'][edge]),
            const Spacer(),
            IconButton(
              key: ValueKey('decoration-nine-slice-minus-$edge'),
              tooltip: '减少 1 像素',
              onPressed: value <= 0 ? null : () => _setInset(edge, value - 1),
              icon: const AppIcon(AppGlyph.remove),
            ),
            Text('${value.round()} px'),
            IconButton(
              key: ValueKey('decoration-nine-slice-plus-$edge'),
              tooltip: '增加 1 像素',
              onPressed: value >= maxValue
                  ? null
                  : () => _setInset(edge, value + 1),
              icon: const AppIcon(AppGlyph.add),
            ),
          ],
        ),
        Slider(
          key: ValueKey('decoration-nine-slice-inset-$edge'),
          value: value,
          max: math.max(1.0, maxValue),
          onChanged: (pixels) => _setInset(edge, pixels.clamp(0.0, maxValue)),
        ),
      ],
    );
  }

  void _setInset(int edge, double pixels) {
    final rect = _value.content;
    final dimension = edge < 2 ? widget.image.height : widget.image.width;
    final fraction = pixels / dimension;
    _changeContent(
      Rect.fromLTRB(
        edge == 2 ? fraction : rect.left,
        edge == 0 ? fraction : rect.top,
        edge == 3 ? 1 - fraction : rect.right,
        edge == 1 ? 1 - fraction : rect.bottom,
      ),
    );
  }
}

class _NineSliceSourcePainter extends CustomPainter {
  _NineSliceSourcePainter(this.image, this.imageRect, this.content);
  final ui.Image image;
  final Rect imageRect;
  final Rect content;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var row = 0; row < size.height / 10; row++) {
      for (var column = 0; column < size.width / 10; column++) {
        canvas.drawRect(
          Rect.fromLTWH(column * 10.0, row * 10.0, 10, 10),
          Paint()
            ..color = (row + column).isEven
                ? const Color(0xFFF0F0F0)
                : const Color(0xFFD5D5D5),
        );
      }
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.low,
    );
    final rect = Rect.fromLTRB(
      imageRect.left + content.left * imageRect.width,
      imageRect.top + content.top * imageRect.height,
      imageRect.left + content.right * imageRect.width,
      imageRect.top + content.bottom * imageRect.height,
    );
    const orange = Color(0xFFDF7A1F);
    canvas.drawRect(rect, Paint()..color = orange.withValues(alpha: 0.2));
    canvas.drawRect(
      rect,
      Paint()
        ..color = orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]) {
      canvas.drawCircle(corner, 7, Paint()..color = Colors.white);
      canvas.drawCircle(corner, 5, Paint()..color = orange);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NineSliceSourcePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.imageRect != imageRect ||
      oldDelegate.content != content;
}

class _NineSliceSamplePainter extends CustomPainter {
  _NineSliceSamplePainter(
    this.image,
    this.nineSlice,
    this.style,
    this.textScaler,
  );
  final ui.Image image;
  final ReaderDecorationNineSlice nineSlice;
  final TextStyle style;
  final TextScaler textScaler;

  double heightFor(double width) {
    final (_, samples) = _layout(width);
    var height = 52.0;
    for (final text in samples) {
      height += text.height;
      text.dispose();
    }
    return math.max(148, height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    var top = 14.0;
    final (left, samples) = _layout(size.width);
    for (final text in samples) {
      _paintSample(canvas, text, Offset(left, top), size);
      top += text.height + 24;
      text.dispose();
    }
    canvas.restore();
  }

  (double, List<TextPainter>) _layout(double width) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fontHeight = _text('字', double.infinity, 1.65);
    final glyph = fontHeight
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        )
        .first
        .toRect();
    final outset = nineSlice.imageRectFor(
      Rect.fromLTWH(0, 0, 40, glyph.height),
      imageSize,
    );
    fontHeight.dispose();
    final left = math.min(-outset.left + 2, width / 3);
    final right = math.min(outset.right - 40 + 2, width / 3);
    final extra = math.max(-outset.top, outset.bottom - glyph.height);
    final lineHeight = math.max(
      1.65,
      (glyph.height + extra * 2 + 4) / textScaler.scale(style.fontSize!),
    );
    return (
      left,
      [
        for (final sample in ['命中示例文字', '命中示例文字较长时会折成多行，中间拉伸，边角保持比例。'])
          _text(sample, math.max(1, width - left - right), lineHeight),
      ],
    );
  }

  TextPainter _text(String sample, double width, double lineHeight) =>
      TextPainter(
        text: TextSpan(
          text: sample,
          style: style.copyWith(height: lineHeight),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: width);

  void _paintSample(Canvas canvas, TextPainter text, Offset origin, Size size) {
    for (final line in text.computeLineMetrics()) {
      final top = line.baseline - line.ascent;
      final range = text.getLineBoundary(
        text.getPositionForOffset(
          Offset(line.left + 0.5, top + line.height / 2),
        ),
      );
      for (final box in text.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      )) {
        ReaderDecorationPainter.paintBox(
          canvas,
          box.toRect().shift(origin),
          ReaderDecorationStyle(
            backgroundImageFit: ReaderDecorationImageFit.nineSlice,
            backgroundImageNineSlice: nineSlice,
          ),
          image: image,
          clipRect: Rect.fromLTWH(0, origin.dy + top, size.width, line.height),
        );
      }
    }
    text.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_NineSliceSamplePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.nineSlice != nineSlice ||
      oldDelegate.style != style ||
      oldDelegate.textScaler != textScaler;
}
