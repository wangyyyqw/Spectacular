import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/rea_micro/rea_micro_lan_book_picker.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';

void main() {
  testWidgets('互联选书可搜索和全选，返回只包含勾选UUID', (tester) async {
    Set<String>? selected;
    final books = [
      for (final name in ['甲书', '乙书'])
        ReaMicroLanBookProgress(
          uuid: name,
          title: name,
          author: '作者',
          cloudId: 0,
          cfi: '',
          chapterName: '',
          progress: 0,
          updatedAt: 0,
          finished: false,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await Navigator.of(context).push<Set<String>>(
                MaterialPageRoute(
                  builder: (_) => ReaMicroLanBookPicker(books: books),
                ),
              );
            },
            child: const Text('互联'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('互联'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('lan-sync-selected')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '乙');
    await tester.pump();
    expect(find.text('甲书'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lan-book-乙书')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lan-sync-selected')));
    await tester.pumpAndSettle();
    expect(selected, {'乙书'});
  });
}
