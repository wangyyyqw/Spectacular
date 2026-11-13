import 'dart:math' as math;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/api.dart' show EpubLayoutType;
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/parser/full_bleed.dart';

import 'book_resources.dart';
import 'chapter_layout_job.dart';
import 'chapter_page_flags.dart';

/// 扩展页属性只读数据，不引用会话设置。
class FullPageLayoutOptions {
  const FullPageLayoutOptions(this.layout, this.flags, this.aspectRatio);
  final EpubLayoutType layout;
  final OpfPageFlags flags;
  final double? aspectRatio;
}

typedef FullPageLayoutDecision = ({PageBlock? block, String? warning});

/// 已确认单图的整页快路，和普通正文共用后续分页与缓存提交。
class FullPageChapterLayout {
  FullPageChapterLayout(this.resources, this.snapshot, this.imageCfi);
  final BookResources resources;
  final LayoutSnapshot snapshot;

  /// 结构准备时确认的唯一可见图片叶位置，不按资源地址反查隐藏元素。
  final String? imageCfi;

  FullPageLayoutDecision build(
    FullBleedChapter analysis,
    FullPageLayoutOptions options,
  ) {
    String? warning;
    final layout = options.layout;
    if (layout == EpubLayoutType.verticalComic) {
      warning =
          'E_DUOKAN_VERTICAL_COMIC_UNSUPPORTED: '
          'vertical-comic 暂不支持连续纵向画布，已回退到普通可读路径';
    } else if (isFixedLike(layout)) {
      return _fixed(analysis, options);
    }
    final source = analysis.singleImageSrc;
    if (source == null || source.isEmpty) {
      return (block: null, warning: warning);
    }
    if (options.flags.isFullPage) {
      final contain =
          options.flags.fitWindow || analysis.singleImageMeetsViewport;
      return (
        block: _block(source, (
          contain: contain,
          bleed: true,
          aspect: null,
        ), flags: options.flags),
        warning: warning,
      );
    }
    // 自动单图页没有作者的裁切声明，等比完整显示，避免窄页裁掉图内文字。
    return (
      block: analysis.isFullBleed
          ? _block(source, (contain: true, bleed: false, aspect: null))
          : null,
      warning: warning,
    );
  }

  static bool isFixedLike(EpubLayoutType layout) =>
      layout == EpubLayoutType.fixedPage ||
      layout == EpubLayoutType.comicsFrame ||
      layout == EpubLayoutType.transverseComic ||
      layout == EpubLayoutType.verticalComic;

  FullPageLayoutDecision _fixed(
    FullBleedChapter analysis,
    FullPageLayoutOptions options,
  ) {
    final source = analysis.singleImageSrc;
    if (analysis.imageCount == 1 &&
        source != null &&
        source.isNotEmpty &&
        !resources.document.archive.contains(
          resources.imageUrl(snapshot.spineIndex, source),
        )) {
      return (
        block: null,
        warning:
            'E_DUOKAN_IMAGE_MISSING: '
            '${options.layout.token} 单图资源不可用：${resources.imageUrl(snapshot.spineIndex, source)}',
      );
    }
    if (analysis.imageCount != 1 ||
        analysis.hasVisibleText ||
        source == null ||
        source.isEmpty) {
      return (
        block: null,
        warning:
            'E_DUOKAN_FIXED_LAYOUT_UNSUPPORTED: '
            '${options.layout.token} 章节不是单图无正文页'
            '（图片 ${analysis.imageCount}，正文 ${analysis.hasVisibleText}），已回退',
      );
    }
    final contain = options.flags.fitWindow || !options.flags.fullScreen;
    return (
      block: _block(source, (
        contain: contain,
        bleed: true,
        aspect: options.aspectRatio,
      ), flags: options.flags),
      warning: null,
    );
  }

  PageBlock _block(
    String source,
    ({bool contain, bool bleed, double? aspect}) options, {
    OpfPageFlags flags = OpfPageFlags.none,
  }) {
    final width = math.max(80.0, snapshot.width);
    final height = math.max(120.0, snapshot.height);
    final url = options.bleed && !options.contain
        ? _fullscreenImage(source, options.aspect)
        : resources.imageUrl(snapshot.spineIndex, source);
    return PageBlock(
      layout: TextLayoutResult(
        text: '',
        lines: [
          LineBox(
            start: 0,
            end: 0,
            top: 0,
            height: height,
            baseline: height,
            width: width,
          ),
        ],
        width: width,
        height: height,
        maxWidth: width,
        runs: const [],
      ),
      style: _backgroundStyle(url, options.contain, flags),
      startCfi: imageCfi,
      bleedLeft: options.bleed,
      bleedRight: options.bleed,
      bleedTop: options.bleed,
      bleedBottom: options.bleed,
    );
  }

  ComputedStyle _backgroundStyle(String url, bool contain, OpfPageFlags flags) {
    // 满屏图等比铺满后保留指定侧；窗口适配及冲突标记仍居中。
    final horizontal = contain || flags.spreadLeft == flags.spreadRight
        ? 'center'
        : flags.spreadLeft
        ? 'left'
        : 'right';
    return ComputedStyle({
      ...snapshot.baseStyle.values,
      'background-image': 'url($url)',
      'background-size': contain ? 'contain' : 'cover',
      'background-position': '$horizontal center',
      'background-repeat': 'no-repeat',
    });
  }

  String _fullscreenImage(String source, double? targetAspect) {
    final original = resources.imageUrl(snapshot.spineIndex, source);
    final slash = original.lastIndexOf('/');
    final dot = original.lastIndexOf('.');
    if (dot <= slash || original.substring(0, dot).endsWith('~slim')) {
      return original;
    }
    final slim = '${original.substring(0, dot)}~slim${original.substring(dot)}';
    final slimSize = resources.intrinsicSizeOfUrl(slim);
    if (slimSize == null) return original;
    final originalSize = resources.intrinsicSizeOfUrl(original);
    if (originalSize == null) return slim;
    final aspect =
        targetAspect ?? snapshot.width / math.max(1.0, snapshot.height);
    final originalAspect =
        originalSize.width / math.max(1.0, originalSize.height);
    final slimAspect = slimSize.width / math.max(1.0, slimSize.height);
    return (slimAspect - aspect).abs() < (originalAspect - aspect).abs()
        ? slim
        : original;
  }
}
