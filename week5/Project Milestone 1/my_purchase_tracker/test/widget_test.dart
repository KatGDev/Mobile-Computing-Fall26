// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_purchase_tracker/main.dart';

void main() {
  testWidgets('description and price are entered when creating an item', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text(r'$3.49'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Item details'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a description'), findsOneWidget);
    expect(find.text('Enter a valid price'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Apples');
    await tester.enterText(find.byType(TextFormField).at(1), '4.25');
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();

    expect(find.text('Apples'), findsOneWidget);
    expect(find.text(r'$4.25'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
}
