import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';

import '../library/revision_anchor_store.dart';
import 'db.dart';

/// 标注存储的 drift 实现：同版同选区合并，保留待定位的旧标注。
class DriftAnnotationStore
    implements ReaderAnnotationStore, RelocatableAnnotationStore {
  /// 创建存储。
  DriftAnnotationStore(this._db, String bookUuid)
    : _binding = RevisionBookBinding(_db, bookUuid);

  final AppDatabase _db;
  final RevisionBookBinding _binding;

  @override
  Future<List<ReaderAnnotation>> list() async {
    final book = await _binding.read();
    if (book == null) {
      return const <ReaderAnnotation>[];
    }
    final rows =
        await (_db.select(_db.annotations)
              ..where(
                (table) =>
                    table.bookId.equals(book.id) &
                    table.type.isSmallerThanValue(2),
              )
              ..orderBy([(table) => OrderingTerm(expression: table.createdAt)]))
            .get();
    return [for (final row in rows) _toAnnotation(row)];
  }

  @override
  Future<ReaderAnnotation?> add({
    required ReaderAnnotationType type,
    required String startCfi,
    required String endCfi,
    required String quote,
    String? contextBefore,
    String? contextAfter,
    int? color,
    ReaderAnnotationStyle style = ReaderAnnotationStyle.background,
    double? opacity,
    String? note,
  }) async {
    final book = await _binding.writable();
    if (book == null) return null;
    final thought = note?.trim();
    if (type == ReaderAnnotationType.thought &&
        (thought == null || thought.isEmpty)) {
      throw const FormatException('想法内容不能为空');
    }
    final bookId = book.id;
    final anchor = await _captureSelection(book, startCfi, endCfi, (
      quote: quote,
      before: contextBefore ?? '',
      after: contextAfter ?? '',
    ));
    final now = DateTime.now();
    final id =
        'an-${now.millisecondsSinceEpoch}-'
        '${math.Random().nextInt(0x7FFFFFFF).toRadixString(36)}';
    final row = await _db.transaction(() async {
      if (await _binding.writable() == null) return null;
      final candidates =
          await (_db.select(_db.annotations)
                ..where(
                  (table) =>
                      table.bookId.equals(bookId) &
                      table.type.isSmallerThanValue(2) &
                      table.startCfi.equals(startCfi) &
                      table.endCfi.equals(endCfi),
                )
                ..orderBy([
                  (table) => OrderingTerm.desc(table.type),
                  (table) => OrderingTerm.desc(table.updatedAt),
                ]))
              .get();
      final existing = candidates.where((row) {
        if (anchor == null) return row.anchorJson == null && row.quote == quote;
        final saved = AnchorRecord.decode(row.anchorJson);
        return anchor.isResolved &&
            saved != null &&
            saved.isResolved &&
            saved.effective.revision == anchor.effective.revision;
      }).toList();
      if (existing.isNotEmpty) {
        return _updateRange(
          existing,
          type: type,
          color: color,
          style: style,
          opacity: opacity,
          note: thought,
        );
      }
      await _db
          .into(_db.annotations)
          .insert(
            AnnotationsCompanion.insert(
              id: id,
              bookId: bookId,
              type: type.storageValue,
              startCfi: startCfi,
              endCfi: endCfi,
              anchorJson: Value(anchor?.encode()),
              quote: quote,
              contextBefore: Value<String?>(contextBefore),
              contextAfter: Value<String?>(contextAfter),
              style: Value<int?>(style.storageValue),
              color: Value<int?>(color),
              opacity: Value<double?>(_validOpacity(opacity)),
              note: Value<String?>(thought),
              createdAt: now.millisecondsSinceEpoch,
              updatedAt: now.millisecondsSinceEpoch,
            ),
          );
      return (_db.select(
        _db.annotations,
      )..where((table) => table.id.equals(id))).getSingle();
    });
    return row == null ? null : _toAnnotation(row);
  }

  Future<AnnotationRow> _updateRange(
    List<AnnotationRow> existing, {
    required ReaderAnnotationType type,
    required ReaderAnnotationStyle style,
    int? color,
    double? opacity,
    String? note,
  }) async {
    final original = existing.first;
    final hasThought =
        original.type == ReaderAnnotationType.thought.storageValue;
    await (_db.update(
      _db.annotations,
    )..where((table) => table.id.equals(original.id))).write(
      AnnotationsCompanion(
        type: Value(hasThought ? original.type : type.storageValue),
        color: Value(color),
        style: Value(style.storageValue),
        opacity: Value(_validOpacity(opacity)),
        note: type == ReaderAnnotationType.thought
            ? Value(note)
            : const Value.absent(),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    final duplicates = existing.skip(1).map((row) => row.id).toList();
    if (duplicates.isNotEmpty) {
      await (_db.delete(
        _db.annotations,
      )..where((table) => table.id.isIn(duplicates))).go();
    }
    return (_db.select(
      _db.annotations,
    )..where((table) => table.id.equals(original.id))).getSingle();
  }

  double? _validOpacity(double? value) =>
      value == null || !value.isFinite ? null : value.clamp(0.0, 1.0);

  void _validateThoughtUpdate(
    AnnotationRow row,
    ReaderAnnotationType? type,
    String? note,
    bool clearNote,
  ) {
    final nextType = type ?? ReaderAnnotationType.fromStorage(row.type);
    if (nextType != ReaderAnnotationType.thought) return;
    if (clearNote || (note ?? row.note ?? '').trim().isEmpty) {
      throw const FormatException('想法内容不能为空');
    }
  }

  @override
  Future<void> update(
    String id, {
    ReaderAnnotationType? type,
    int? color,
    ReaderAnnotationStyle? style,
    double? opacity,
    String? note,
    bool clearNote = false,
  }) async {
    await _db.transaction(() async {
      final book = await _binding.writable();
      if (book == null) return;
      final row =
          await (_db.select(_db.annotations)..where(
                (table) =>
                    table.id.equals(id) &
                    table.bookId.equals(book.id) &
                    table.type.isSmallerThanValue(2),
              ))
              .getSingleOrNull();
      if (row == null) return;
      _validateThoughtUpdate(row, type, note, clearNote);
      await (_db.update(_db.annotations)..where(
            (table) =>
                table.id.equals(id) &
                table.bookId.equals(book.id) &
                table.type.isSmallerThanValue(2),
          ))
          .write(
            AnnotationsCompanion(
              type: type == null
                  ? const Value<int>.absent()
                  : Value<int>(type.storageValue),
              color: color == null
                  ? const Value<int?>.absent()
                  : Value<int?>(color),
              style: style == null
                  ? const Value<int?>.absent()
                  : Value<int?>(style.storageValue),
              opacity: opacity == null
                  ? const Value<double?>.absent()
                  : Value<double?>(_validOpacity(opacity)),
              note: clearNote
                  ? const Value<String?>(null)
                  : note == null
                  ? const Value<String?>.absent()
                  : Value<String?>(note.trim()),
              updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
            ),
          );
    });
  }

  @override
  Future<void> remove(String id) => _db.transaction(() async {
    // 已移除书籍仍展示保留的笔记，允许清理但不解除内容版本保护。
    final book = await _binding.writable(allowDeleted: true);
    if (book == null) return;
    await (_db.delete(_db.annotations)..where(
          (table) =>
              table.id.equals(id) &
              table.bookId.equals(book.id) &
              table.type.isSmallerThanValue(2),
        ))
        .go();
  });

  /// 导入云端标注；同一标识按更新时间保留较新内容。
  Future<void> importSynced(ReaderAnnotation annotation) async {
    final book = await _binding.writable();
    if (book == null) return;
    final startCfi = annotation.startCfi.trim();
    final endCfi = annotation.endCfi.trim();
    if (startCfi.isEmpty) return;
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.annotations)..where(
                (table) =>
                    table.id.equals(annotation.id) &
                    table.bookId.equals(book.id) &
                    table.type.isSmallerThanValue(2),
              ))
              .getSingleOrNull();
      final updatedAt = annotation.updatedAt.millisecondsSinceEpoch;
      if (existing != null && existing.updatedAt > updatedAt) return;
      final evidence = (
        quote: annotation.quote,
        before: annotation.contextBefore ?? '',
        after: annotation.contextAfter ?? '',
      );
      var resolvedStart = startCfi;
      var resolvedEnd = endCfi.isEmpty ? startCfi : endCfi;
      AnchorRecord? anchor;
      final startCandidates = await _annotationCandidates(book, startCfi);
      final endCandidates = resolvedEnd == startCfi
          ? startCandidates
          : await _annotationCandidates(book, resolvedEnd);
      for (final candidateStart in startCandidates) {
        for (final candidateEnd in endCandidates) {
          final attempt = await _captureSelection(
            book,
            candidateStart,
            candidateEnd,
            evidence,
          );
          if (attempt != null && attempt.isResolved) {
            anchor = attempt;
            resolvedStart = candidateStart;
            resolvedEnd = candidateEnd;
            break;
          }
          anchor ??= attempt;
        }
        if (anchor?.isResolved == true) break;
      }
      if (anchor?.isResolved != true) {
        final recovered = await _recoverExternalSelection(
          book,
          startCfi,
          resolvedEnd,
          evidence.quote,
        );
        if (recovered != null) {
          anchor = recovered;
          resolvedStart = recovered.effective.start.cfi;
          resolvedEnd = recovered.effective.end!.cfi;
        }
      }
      // 同一设备再次同步只更新想法正文时，保留上一轮已验证的本地锚点。
      final savedAnchor = AnchorRecord.decode(existing?.anchorJson);
      if (anchor?.isResolved != true &&
          savedAnchor != null &&
          savedAnchor.isResolved &&
          existing?.startCfi == startCfi &&
          existing?.endCfi == resolvedEnd) {
        anchor = savedAnchor;
        resolvedStart = existing!.startCfi;
        resolvedEnd = existing.endCfi;
      }
      final companion = AnnotationsCompanion(
        id: Value<String>(annotation.id),
        bookId: Value<int>(book.id),
        type: Value<int>(annotation.type.storageValue),
        startCfi: Value<String>(resolvedStart),
        endCfi: Value<String>(resolvedEnd),
        anchorJson: Value<String?>(anchor?.encode() ?? annotation.anchorData),
        quote: Value<String>(annotation.quote),
        contextBefore: Value<String?>(annotation.contextBefore),
        contextAfter: Value<String?>(annotation.contextAfter),
        style: Value<int?>(annotation.style.storageValue),
        color: Value<int?>(annotation.color),
        opacity: Value<double?>(_validOpacity(annotation.opacity)),
        note: Value<String?>(annotation.note),
        createdAt: Value<int>(annotation.createdAt.millisecondsSinceEpoch),
        updatedAt: Value<int>(updatedAt),
      );
      if (existing == null) {
        await _db.into(_db.annotations).insert(companion);
      } else {
        await (_db.update(
          _db.annotations,
        )..where((table) => table.id.equals(existing.id))).write(companion);
      }
    });
  }

  /// 为历史云端标注补建本地锚点；阅读页依赖锚点定位，笔记列表不需要。
  Future<int> repairUnresolvedAnchors() async {
    final book = await _binding.writable();
    if (book == null) return 0;
    final rows =
        await (_db.select(_db.annotations)..where(
              (table) =>
                  table.bookId.equals(book.id) &
                  table.type.isSmallerThanValue(2),
            ))
            .get();
    var repaired = 0;
    for (final row in rows) {
      final saved = AnchorRecord.decode(row.anchorJson);
      if (saved?.isResolved == true) continue;
      final startCfi = row.startCfi.trim();
      if (startCfi.isEmpty) continue;
      final endCfi = row.endCfi.trim().isEmpty ? startCfi : row.endCfi.trim();
      final evidence = (
        quote: row.quote,
        before: row.contextBefore ?? '',
        after: row.contextAfter ?? '',
      );
      final startCandidates = await _annotationCandidates(book, startCfi);
      final endCandidates = endCfi == startCfi
          ? startCandidates
          : await _annotationCandidates(book, endCfi);
      var rowRepaired = false;
      for (final candidateStart in startCandidates) {
        for (final candidateEnd in endCandidates) {
          final anchor = await _captureSelection(
            book,
            candidateStart,
            candidateEnd,
            evidence,
          );
          if (anchor?.isResolved != true) continue;
          await (_db.update(_db.annotations)..where(
                (table) =>
                    table.id.equals(row.id) & table.bookId.equals(book.id),
              ))
              .write(
                AnnotationsCompanion(
                  startCfi: Value<String>(candidateStart),
                  endCfi: Value<String>(candidateEnd),
                  anchorJson: Value<String?>(anchor!.encode()),
                ),
              );
          repaired += 1;
          rowRepaired = true;
          break;
        }
        if (rowRepaired) break;
      }
      if (!rowRepaired) {
        final anchor = await _recoverExternalSelection(
          book,
          startCfi,
          endCfi,
          row.quote,
        );
        if (anchor != null) {
          await (_db.update(_db.annotations)..where(
                (table) =>
                    table.id.equals(row.id) & table.bookId.equals(book.id),
              ))
              .write(
                AnnotationsCompanion(
                  startCfi: Value(anchor.effective.start.cfi),
                  endCfi: Value(anchor.effective.end!.cfi),
                  anchorJson: Value(anchor.encode()),
                ),
              );
          repaired += 1;
        }
      }
    }
    return repaired;
  }

  @override
  Future<void> relocate(
    String id, {
    required String startCfi,
    required String endCfi,
  }) async {
    final book = await _binding.writable();
    if (book == null) throw const FormatException('书籍内容已更新，请重新打开阅读');
    final row =
        await (_db.select(_db.annotations)..where(
              (table) =>
                  table.id.equals(id) &
                  table.bookId.equals(book.id) &
                  table.type.isSmallerThanValue(2),
            ))
            .getSingleOrNull();
    if (row == null) throw const FormatException('原标注不存在');
    final anchor = await captureBookAnchor(
      _db,
      book,
      startCfi,
      endCfi: endCfi,
      existing: requireAnchorRecord(row.anchorJson),
    );
    if (anchor == null) throw const FormatException('无法确认所选文字的位置');
    await _db.transaction(() async {
      if (await _binding.writable() == null) {
        throw const FormatException('书籍内容已更新，请重新打开阅读');
      }
      await (_db.update(
        _db.annotations,
      )..where((table) => table.id.equals(id))).write(
        AnnotationsCompanion(
          startCfi: Value(startCfi),
          endCfi: Value(endCfi),
          anchorJson: Value(anchor.encode()),
        ),
      );
    });
  }

  /// 无法对应原引用的合法偏移也不能标成可靠定位。
  Future<List<String>> _annotationCandidates(BookRow book, String cfi) async {
    final converted = await localExternalAnnotationCfi(_db, book, cfi);
    return {?converted, ...epubCfiCandidates(cfi)}.toList(growable: false);
  }

  /// 阅微内联容器可能使用显示偏移；仅在原 DOM 范围内唯一匹配整段引用。
  Future<AnchorRecord?> _recoverExternalSelection(
    BookRow book,
    String start,
    String end,
    String quote,
  ) async {
    if (quote.isEmpty) return null;
    final scope = await localExternalAnnotationCfi(
      _db,
      book,
      start,
      scope: true,
    );
    final endScope = await localExternalAnnotationCfi(
      _db,
      book,
      end,
      scope: true,
    );
    if (scope == null || scope != endScope) return null;
    final index = await loadBookAnchorIndex(
      _db,
      book,
      startCfi: epubCfiCandidates(start).first,
      endCfi: epubCfiCandidates(end).first,
    );
    if (index == null || index.chapters.length != 1) return null;
    final chapter = index.chapters.single;
    final prefix = scope.substring(0, scope.length - 1);
    AnchorRecord? found;
    var offset = chapter.text.indexOf(quote);
    while (offset >= 0) {
      final first = chapter.cfiAt(offset);
      final last = chapter.cfiAt(offset + quote.length, end: true);
      bool within(String? cfi) =>
          cfi != null &&
          (cfi.startsWith('$prefix/') || cfi.startsWith('$prefix:'));
      if (within(first) && within(last)) {
        if (found != null) return null;
        final selection = index.capture(first!, endCfi: last!);
        if (selection != null && selection.quote == quote) {
          // capture 的章末边界可能规范化到下一块，标注保留已核验的结束文本端点。
          AnchorPoint endpoint(AnchorPoint point, String cfi) =>
              AnchorPoint.fromJson({...point.toJson(), 'cfi': cfi});
          found = AnchorRecord(
            original: LocationAnchor(
              revision: selection.revision,
              start: endpoint(selection.start, first),
              end: endpoint(selection.end!, last),
              quote: selection.quote,
            ),
          );
        }
      }
      offset = chapter.text.indexOf(quote, offset + 1);
    }
    return found;
  }

  Future<AnchorRecord?> _captureSelection(
    BookRow book,
    String startCfi,
    String endCfi,
    ({String quote, String before, String after}) evidence,
  ) async {
    final anchor = await captureBookAnchor(_db, book, startCfi, endCfi: endCfi);
    if (anchor == null ||
        _matchingText(anchor.effective.quote) ==
            _matchingText(evidence.quote)) {
      return anchor;
    }
    final index = await loadBookAnchorIndex(
      _db,
      book,
      startCfi: startCfi,
      endCfi: endCfi,
    );
    final original = index?.rangeFromEvidence(
      startCfi: startCfi,
      endCfi: endCfi,
      quote: evidence.quote,
      contextBefore: evidence.before,
      contextAfter: evidence.after,
    );
    return original == null
        ? null
        : AnchorRecord(
            original: original,
            status: 'pending',
            reason: '原引用与当前位置文字不一致',
          );
  }

  String _matchingText(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  ReaderAnnotation _toAnnotation(
    AnnotationRow row, {
    AnchorRecord? anchor,
    String? startCfi,
    String? endCfi,
  }) {
    anchor ??= AnchorRecord.decode(row.anchorJson);
    return ReaderAnnotation(
      id: row.id,
      type: ReaderAnnotationType.fromStorage(row.type),
      startCfi: startCfi ?? row.startCfi,
      endCfi: endCfi ?? row.endCfi,
      quote: row.quote,
      contextBefore: row.contextBefore,
      contextAfter: row.contextAfter,
      color: row.color,
      style: ReaderAnnotationStyle.fromStorage(row.style),
      opacity: row.opacity,
      note: row.note,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      relocationStatus: anchor?.status ?? 'pending',
      relocationReason:
          anchor?.reason ?? (anchor == null ? '内容锚点缺失或格式不受支持，请重新建立记录' : null),
      currentQuote: anchor?.effective.quote,
      anchorData: anchor?.encode() ?? row.anchorJson,
    );
  }
}
