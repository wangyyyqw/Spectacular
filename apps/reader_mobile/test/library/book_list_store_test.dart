import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/book_list_store.dart';
import 'package:reader_mobile/library/library_store.dart';

void main() {
  test('书单可创建、改名、改简介并按添加顺序保存书籍', () async {
    final library = LibraryStore.memory();
    final store = library.bookListStore();

    final created = await store.create(
      name: ' 长期主义 ',
      description: ' 慢慢拉开差距 ',
    );
    expect(created.name, '长期主义');
    expect(created.description, '慢慢拉开差距');
    expect(created.bookIds, isEmpty);

    await store.addBooks(created.id, <String>['b', 'a', 'b']);
    expect((await store.list()).single.bookIds, <String>['b', 'a']);

    await store.update(created.id, name: '经典', description: '');
    await store.removeBook(created.id, 'b');
    final stored = (await store.list()).single;
    expect(stored.name, '经典');
    expect(stored.description, '');
    expect(stored.bookIds, <String>['a']);

    expect(await store.listIdsForBook('a'), <String>{created.id});
    expect(await store.listIdsForBook('b'), isEmpty);

    await store.delete(created.id);
    expect(await store.list(), isEmpty);
  });

  test('空名称拒绝保存，损坏的存储内容按空书单处理', () async {
    final library = LibraryStore.memory();
    final store = library.bookListStore();

    expect(() => store.create(name: '  '), throwsFormatException);
    expect(await store.list(), isEmpty);

    await library.setSetting(BookListStore.settingKey, '{oops');
    expect(await store.list(), isEmpty);
  });
}
