import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/rating/reader_rating.dart';

void main() {
  testWidgets('五星支持左半点击、整星点击和再次点击清除', (tester) async {
    num? rating = 3.5;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReaderRatingPicker(
              rating: rating,
              keyPrefix: 'rating',
              onChanged: (value) => setState(() => rating = value),
            ),
          ),
        ),
      ),
    );
    for (var star = 1; star <= 5; star++) {
      expect(find.byKey(ValueKey('rating-$star')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('rating-half-9')));
    await tester.pump();
    expect(rating, 4.5);
    await tester.tap(find.byKey(const ValueKey('rating-half-10')));
    await tester.pump();
    expect(rating, 5);
    await tester.tap(find.byKey(const ValueKey('rating-half-10')));
    await tester.pump();
    expect(rating, isNull);
    expect(tester.takeException(), isNull);
  });
}
