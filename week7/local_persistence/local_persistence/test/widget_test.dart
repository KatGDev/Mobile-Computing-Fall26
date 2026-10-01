// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_persistence/main.dart';

void main() {
  testWidgets('saves and loads the entered name', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Hello Ada'), findsNothing);

    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();

    final greeting = find.text('Hello Ada');
    expect(greeting, findsOneWidget);
    expect(
      tester.getTopLeft(greeting).dy,
      lessThan(tester.getTopLeft(find.text('Save')).dy),
    );
  });
}
