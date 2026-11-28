import '../library/library_store.dart';

/// 书架排序方式（P4-08）。
enum BookSortOrder {
  /// 最近阅读优先（默认）。
  recent('最近阅读', 'recent'),

  /// 按导入时间排列，方向由新书位置设置决定。
  added('导入时间', 'added'),

  /// 书名升序。
  title('书名', 'title');

  const BookSortOrder(this.label, this.value);

  /// 菜单文案。
  final String label;

  /// 持久化值。
  final String value;

  /// 按持久化值还原，未知值回退最近阅读。
  static BookSortOrder fromValue(String? value) {
    for (final order in values) {
      if (order.value == value) {
        return order;
      }
    }
    return recent;
  }

  /// 新书按导入时间参与排序；阅读后正常进入最近阅读顺序，置顶由书架处理。
  int compare(BookEntry a, BookEntry b, {required bool newBooksFirst}) {
    switch (this) {
      case recent:
        if (!newBooksFirst) {
          if (a.lastReadAt == null) {
            return b.lastReadAt == null ? a.addedAt.compareTo(b.addedAt) : 1;
          }
          if (b.lastReadAt == null) return -1;
        }
        final compared = (b.lastReadAt ?? b.addedAt).compareTo(
          a.lastReadAt ?? a.addedAt,
        );
        return compared != 0 ? compared : b.addedAt.compareTo(a.addedAt);
      case added:
        return newBooksFirst
            ? b.addedAt.compareTo(a.addedAt)
            : a.addedAt.compareTo(b.addedAt);
      case title:
        return a.title.compareTo(b.title);
    }
  }
}

/// 书架排序设置键。
const bookshelfSortKey = 'bookshelf.sort';

/// 新导入书籍是否排在最前；缺省为开启，书名排序不使用此设置。
const bookshelfNewBooksFirstKey = 'bookshelf.newBooksFirst';

/// 自定义分组页签的本机顺序，不包含固定的「默认」。
const bookshelfGroupOrderKey = 'bookshelf.groupOrder';

/// 书架是否显示书名设置键；缺省为显示。
const bookshelfShowTitlesKey = 'bookshelf.showTitles';
