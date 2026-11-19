import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reviews_cloud.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_ui/annotations/annotation.dart';

BookEntry _book(String id, String title, String author) => BookEntry(
  id: id,
  title: title,
  author: author,
  filePath: '',
  addedAt: DateTime(2026),
);

ReaMicroBookLink _link(int cloudBookId) => ReaMicroBookLink(
  cloudBookId: cloudBookId,
  name: '云端书',
  linkedAt: DateTime(2026),
);

void main() {
  test('云端标注书按关联并入本地计数，本地缺失的书补入列表', () {
    final local = _book('local', '本地书', '作者');
    final merge = mergeCloudMarkBooks(
      books: <BookEntry>[local],
      counts: <String, BookNoteCounts>{
        local.id: (thoughts: 2, marks: 1, updatedAt: DateTime(2026)),
      },
      links: <String, ReaMicroBookLink>{local.id: _link(21)},
      markBooks: const <ReaMicroMarkBook>[
        ReaMicroMarkBook(
          bookId: 8,
          cloudBookId: 21,
          name: '本地书',
          author: '作者',
          cover: '',
          thoughtCount: 4,
          underlineCount: 2,
        ),
        ReaMicroMarkBook(
          bookId: 9,
          cloudBookId: 22,
          name: '仅云端笔记',
          author: '另一位作者',
          cover: '',
          thoughtCount: 1,
          underlineCount: 3,
        ),
      ],
    );

    expect(merge.counts[local.id]?.thoughts, 4);
    expect(merge.counts[local.id]?.marks, 2);
    expect(merge.extraBooks.single.title, '仅云端笔记');
    expect(merge.counts[merge.extraBooks.single.id]?.marks, 3);
    expect(merge.markBooks[local.id]?.cloudBookId, 21);
  });

  test('云端书评并入本地列表并把十分制评分换算为五星', () {
    final local = _book('local', '本地书', '作者');
    final updatedAt = DateTime(2026, 11, 19, 10);
    final merge = mergeCloudReviews(
      books: <BookEntry>[local],
      reviews: const <String, BookReview>{},
      links: <String, ReaMicroBookLink>{local.id: _link(21)},
      records: <CloudReviewRecord>[
        CloudReviewRecord(
          cloudBookId: 21,
          bookId: 8,
          bookName: '本地书',
          bookAuthor: '作者',
          bookCover: '',
          rating: 9,
          comment: '云端书评正文',
          updatedAt: updatedAt,
          readSeconds: 7200,
        ),
        CloudReviewRecord(
          cloudBookId: 22,
          bookId: 9,
          bookName: '仅云端书评',
          bookAuthor: '另一位作者',
          bookCover: '',
          rating: 0,
          comment: '只有正文',
          updatedAt: updatedAt,
          readSeconds: 600,
        ),
      ],
    );

    expect(merge.reviews[local.id]?.rating, 5);
    expect(merge.reviews[local.id]?.content, '云端书评正文');
    expect(merge.durations[local.id], const Duration(hours: 2));
    expect(merge.extraBooks.single.title, '仅云端书评');
    expect(merge.reviews[merge.extraBooks.single.id]?.rating, isNull);
  });

  test('本地已导入的云端标注不重复显示', () {
    final now = DateTime(2026, 11, 19, 10);
    final local = ReaderAnnotation(
      id: 'mark-cloud-5',
      type: ReaderAnnotationType.mark,
      startCfi: 'epubcfi(/6/2!/4/2/1:4)',
      endCfi: 'epubcfi(/6/2!/4/2/1:12)',
      quote: '原文',
      createdAt: now,
      updatedAt: now,
    );
    final merged = mergeCloudMarks(
      <ReaderAnnotation>[local],
      <ReaMicroMark>[
        ReaMicroMark(
          id: 5,
          bookId: '21',
          chapter: '',
          kind: 0,
          startCfi: local.startCfi,
          endCfi: local.endCfi,
          quote: local.quote,
          note: '',
          style: 0,
          color: '',
          synced: 1,
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
      ],
    );

    expect(merged, hasLength(1));
  });
}
