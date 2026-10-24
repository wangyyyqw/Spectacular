import 'dart:collection';

import 'package:flutter/painting.dart';

/// 段落（行）`TextPainter` 缓存（P2-30）。
///
/// 键包含布局指纹、页号与行号：布局指纹变化（字号/边距/宽度等重排）时
/// [bindLayout] 会整体失效；超过上限按 LRU 驱逐，驱逐与清空都会调用
/// [TextPainter.dispose] 释放底层 `ui.Paragraph`，避免内存持续增长。
class ParagraphCache {
  /// 创建缓存。
  ParagraphCache({this.maxEntries = 256});

  /// 条目上限。
  final int maxEntries;

  final LinkedHashMap<String, TextPainter> _entries =
      LinkedHashMap<String, TextPainter>();
  String? _layoutFingerprint;
  int _hits = 0;
  int _misses = 0;

  /// 命中次数。
  int get hits => _hits;

  /// 未命中次数。
  int get misses => _misses;

  /// 当前条目数。
  int get length => _entries.length;

  /// 当前绑定的布局指纹。
  String? get layoutFingerprint => _layoutFingerprint;

  /// 绑定布局指纹；指纹变化时清空旧缓存（重排后旧段落全部失效）。
  void bindLayout(String fingerprint) {
    if (_layoutFingerprint == fingerprint) {
      return;
    }
    _layoutFingerprint = fingerprint;
    clear();
  }

  /// 取缓存的行排版；未命中时用 [build] 构建并写入。
  TextPainter obtain(String key, {required TextPainter Function() build}) {
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      _hits += 1;
      return cached;
    }
    _misses += 1;
    final painter = build();
    _entries[key] = painter;
    _evict();
    return painter;
  }

  /// 清空并释放所有段落。
  void clear() {
    for (final painter in _entries.values) {
      painter.dispose();
    }
    _entries.clear();
    _hits = 0;
    _misses = 0;
  }

  /// 释放缓存（等价于 [clear]）。
  void dispose() => clear();

  void _evict() {
    while (_entries.length > maxEntries) {
      final oldestKey = _entries.keys.first;
      final painter = _entries.remove(oldestKey);
      painter?.dispose();
    }
  }
}
