import 'package:db_client/features/documents/json_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('large arrays expand in chunks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: JsonTree(
              document: {
                'items': [for (var i = 0; i < 250; i++) i],
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Array (250)'));
    await tester.pump();
    expect(find.text('99: '), findsOneWidget);
    expect(find.text('100: '), findsNothing);
    expect(find.text('Show 100 more (150 remaining)'), findsOneWidget);

    await tester.ensureVisible(find.text('Show 100 more (150 remaining)'));
    await tester.tap(find.text('Show 100 more (150 remaining)'));
    await tester.pump();
    expect(find.text('199: '), findsOneWidget);
    expect(find.text('Show 50 more (50 remaining)'), findsOneWidget);

    await tester.ensureVisible(find.text('Show 50 more (50 remaining)'));
    await tester.tap(find.text('Show 50 more (50 remaining)'));
    await tester.pump();
    expect(find.text('249: '), findsOneWidget);
    expect(find.textContaining('remaining'), findsNothing);
  });
}
