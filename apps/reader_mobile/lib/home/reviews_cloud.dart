import 'package:reader_ui/annotations/annotation.dart';

import '../library/library_store.dart';
import '../rea_micro/rea_micro_models.dart';
import '../storage/book_review_store.dart';

/// 阅微标注书与本地书架的合并结果。
class CloudNoteMerge {
  /// 创建合并结果。
  const CloudNoteMerge({
    required this.extraBooks,
    required this.counts,
    required this.markBooks,
  });

  /// 本地书架没有的云端书；用于笔记列表直接展示。
  final List<BookEntry> extraBooks;

  /// 合并后的每本书笔记数量。
  final Map<String, BookNoteCounts> counts;

  /// 本地书籍标识到阅微标注书标识的映射。
  final Map<String, ({int cloudBookId, int bookId})> markBooks;
}

/// 阅微书评与本地书架的合并结果。
class CloudReviewMerge {
  /// 创建合并结果。
  const CloudReviewMerge({
    required this.extraBooks,
    required this.reviews,
    required this.durations,
  });

  /// 本地书架没有的云端书。
  final List<BookEntry> extraBooks;

  /// 合并后的书评，按书籍标识索引。
  final Map<String, BookReview> reviews;

  /// 云端累计阅读时长，按书籍标识索引。
  final Map<String, Duration> durations;
}

/// 一条可展示的阅微书评。
class CloudReviewRecord {
  /// 创建书评记录。
  const CloudReviewRecord({
    required this.cloudBookId,
    required this.bookId,
    required this.bookName,
    required this.bookAuthor,
    required this.bookCover,
    required this.rating,
    required this.comment,
    required this.updatedAt,
    required this.readSeconds,
  });

  /// 云端书籍标识。
  final int cloudBookId;

  /// 阅微内部书籍标识。
  final int bookId;

  final String bookName;
  final String bookAuthor;
  final String bookCover;

  /// 阅微评分为 1～10，0 表示未评分。
  final int rating;
  final String comment;
  final DateTime updatedAt;
  final int readSeconds;

  /// 是否包含可展示的书评内容。
  bool get usable => rating > 0 || comment.trim().isNotEmpty;

  /// 从读完里程碑解析。
  factory CloudReviewRecord.fromMilestone(ReaMicroMilestone milestone) =>
      CloudReviewRecord(
        cloudBookId: milestone.cloudBookId,
        bookId: 0,
        bookName: milestone.name,
        bookAuthor: milestone.author,
        bookCover: milestone.cover,
        rating: milestone.rating,
        comment: milestone.comment,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          milestone.ratingTime > 0
              ? milestone.ratingTime
              : DateTime.now().millisecondsSinceEpoch,
        ),
        readSeconds: milestone.totalReadTimeSeconds,
      );

  /// 从按书查询的书评解析。
  factory CloudReviewRecord.fromReview(
    ReaMicroBookReview review, {
    required int cloudBookId,
  }) => CloudReviewRecord(
    cloudBookId: cloudBookId,
    bookId: review.bookId,
    bookName: review.bookName,
    bookAuthor: review.bookAuthor,
    bookCover: review.bookCover,
    rating: review.rating,
    comment: review.comment,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      review.commentUpdateTime > 0
          ? review.commentUpdateTime
          : review.publishTime > 0
          ? review.publishTime
          : DateTime.now().millisecondsSinceEpoch,
    ),
    readSeconds: review.readTotalTimeSeconds,
  );
}

/// 把阅微标注书合并到本地书架的笔记列表。
CloudNoteMerge mergeCloudMarkBooks({
  required List<BookEntry> books,
  required Map<String, BookNoteCounts> counts,
  required Map<String, ReaMicroBookLink> links,
  required List<ReaMicroMarkBook> markBooks,
}) {
  final mergedCounts = Map<String, BookNoteCounts>.of(counts);
  final markBookByLocal = <String, ({int cloudBookId, int bookId})>{};
  final extraBooks = <BookEntry>[];
  for (final remote in markBooks) {
    final local = matchLocalBook(
      books: books,
      links: links,
      cloudBookId: remote.cloudBookId,
      bookId: remote.bookId,
      title: remote.name,
      author: remote.author,
    );
    final cloudCount = (
      thoughts: remote.thoughtCount,
      marks: remote.underlineCount,
      updatedAt: DateTime.now(),
    );
    if (local != null) {
      final existing = mergedCounts[local.id];
      mergedCounts[local.id] = (
        thoughts: _larger(existing?.thoughts ?? 0, cloudCount.thoughts),
        marks: _larger(existing?.marks ?? 0, cloudCount.marks),
        updatedAt: existing?.updatedAt ?? cloudCount.updatedAt,
      );
      markBookByLocal[local.id] = (
        cloudBookId: remote.cloudBookId,
        bookId: remote.bookId,
      );
      continue;
    }
    final entry = cloudNoteBook(remote);
    extraBooks.add(entry);
    mergedCounts[entry.id] = cloudCount;
    markBookByLocal[entry.id] = (
      cloudBookId: remote.cloudBookId,
      bookId: remote.bookId,
    );
  }
  return CloudNoteMerge(
    extraBooks: extraBooks,
    counts: mergedCounts,
    markBooks: markBookByLocal,
  );
}

/// 把阅微书评合并到本地书评列表；云端较新的内容覆盖本地旧副本。
CloudReviewMerge mergeCloudReviews({
  required List<BookEntry> books,
  required Map<String, BookReview> reviews,
  required Map<String, ReaMicroBookLink> links,
  required List<CloudReviewRecord> records,
}) {
  final mergedReviews = Map<String, BookReview>.of(reviews);
  final durations = <String, Duration>{};
  final extraBooks = <BookEntry>[];
  final seen = <int>{};
  for (final record in records) {
    if (!record.usable || record.cloudBookId <= 0) continue;
    if (!seen.add(record.cloudBookId)) continue;
    final local = matchLocalBook(
      books: books,
      links: links,
      cloudBookId: record.cloudBookId,
      bookId: record.bookId,
      title: record.bookName,
      author: record.bookAuthor,
    );
    final target = local ?? cloudReviewBook(record);
    if (local == null) extraBooks.add(target);
    final existing = mergedReviews[target.id];
    if (existing != null && existing.updatedAt.isAfter(record.updatedAt)) {
      continue;
    }
    mergedReviews[target.id] = BookReview(
      bookId: target.id,
      rating: _stars(record.rating),
      content: record.comment.trim(),
      createdAt: existing?.createdAt ?? record.updatedAt,
      updatedAt: record.updatedAt,
    );
    if (record.readSeconds > 0) {
      durations[target.id] = Duration(seconds: record.readSeconds);
    }
  }
  return CloudReviewMerge(
    extraBooks: extraBooks,
    reviews: mergedReviews,
    durations: durations,
  );
}

/// 合并本地与云端标注；相同类型和 CFI 区间的记录只保留本地版本。
List<ReaderAnnotation> mergeCloudMarks(
  List<ReaderAnnotation> local,
  List<ReaMicroMark> remote,
) {
  final merged = List<ReaderAnnotation>.of(local);
  final ranges = <String>{
    for (final annotation in local)
      '${annotation.type.storageValue}|${annotation.startCfi}|${annotation.endCfi}',
  };
  for (final mark in remote) {
    if (mark.startCfi.trim().isEmpty) continue;
    final end = mark.endCfi.trim().isEmpty ? mark.startCfi : mark.endCfi;
    final key = '${mark.kind}|${mark.startCfi}|$end';
    if (!ranges.add(key)) continue;
    merged.add(annotationFromCloudMark(mark));
  }
  merged.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return merged;
}

/// 把阅微标注转为笔记页使用的通用标注。
ReaderAnnotation annotationFromCloudMark(ReaMicroMark mark) {
  final updatedAt = DateTime.fromMillisecondsSinceEpoch(
    mark.updatedAt > 0
        ? mark.updatedAt
        : mark.createdAt > 0
        ? mark.createdAt
        : DateTime.now().millisecondsSinceEpoch,
  );
  return ReaderAnnotation(
    id: 'mark-cloud-${mark.id}',
    type: ReaderAnnotationType.fromStorage(mark.kind),
    startCfi: mark.startCfi,
    endCfi: mark.endCfi.trim().isEmpty ? mark.startCfi : mark.endCfi,
    quote: mark.quote,
    color: _colorFromRemote(mark.color),
    style: ReaderAnnotationStyle.fromStorage(mark.style),
    note: mark.note.trim().isEmpty ? null : mark.note,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      mark.createdAt > 0 ? mark.createdAt : updatedAt.millisecondsSinceEpoch,
    ),
    updatedAt: updatedAt,
  );
}

/// 在本地书架中按关联、云端标识或唯一书名作者定位书籍。
BookEntry? matchLocalBook({
  required List<BookEntry> books,
  required Map<String, ReaMicroBookLink> links,
  required int cloudBookId,
  required int bookId,
  required String title,
  required String author,
}) {
  for (final book in books) {
    final link = links[book.id];
    if (link == null) continue;
    if (link.cloudBookId == cloudBookId ||
        (bookId > 0 && link.cloudBookId == bookId)) {
      return book;
    }
  }
  final normalizedTitle = normalizeCloudBookText(title);
  if (normalizedTitle.isEmpty) return null;
  final normalizedAuthor = normalizeCloudBookText(author);
  final matches = <BookEntry>[
    for (final book in books)
      if (normalizeCloudBookText(book.title) == normalizedTitle &&
          (normalizedAuthor.isEmpty ||
              normalizeCloudBookText(book.author) == normalizedAuthor))
        book,
  ];
  return matches.length == 1 ? matches.single : null;
}

/// 书名作者匹配使用的归一化文本。
String normalizeCloudBookText(String value) =>
    value.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();

/// 本地书库缺失的阅微笔记书占位。
BookEntry cloudNoteBook(ReaMicroMarkBook book) => BookEntry(
  id: 'rea-cloud-note-${book.cloudBookId > 0 ? book.cloudBookId : book.bookId}',
  title: book.name.trim().isEmpty ? '阅微云端书籍' : book.name.trim(),
  author: book.author.trim(),
  filePath: '',
  addedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

/// 本地书库缺失的阅微书评书占位。
BookEntry cloudReviewBook(CloudReviewRecord review) => BookEntry(
  id: 'rea-cloud-review-${review.cloudBookId}',
  title: review.bookName.trim().isEmpty ? '阅微云端书籍' : review.bookName.trim(),
  author: review.bookAuthor.trim(),
  filePath: '',
  addedAt: review.updatedAt,
);

int _larger(int left, int right) => left > right ? left : right;

int? _stars(int rating) {
  if (rating <= 0) return null;
  return ((rating + 1) ~/ 2).clamp(1, 5).toInt();
}

int? _colorFromRemote(String value) {
  var text = value.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('#')) text = text.substring(1);
  if (text.startsWith('0x') || text.startsWith('0X')) {
    text = text.substring(2);
  }
  if (text.length == 6) text = 'ff$text';
  return text.length == 8 ? int.tryParse(text, radix: 16) : null;
}
