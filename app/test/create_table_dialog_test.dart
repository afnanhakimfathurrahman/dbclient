import 'package:db_client/drivers/sql_dialect.dart';
import 'package:db_client/features/navigator/create_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [1200.0, 400.0]) {
    testWidgets('create table dialog builds the DDL (width $width)', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? executed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCreateTableDialog(
                context,
                dialect: const MySqlDialect(),
                schema: 'shop',
                onExecute: (sql) async => executed = sql,
                onOpenInSql: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Table Name *'),
        'orders',
      );
      await tester.tap(find.text('Add column'));
      await tester.pumpAndSettle();
      final names = find.widgetWithText(TextFormField, 'Name');
      final types = find.widgetWithText(TextFormField, 'Type');
      await tester.enterText(names.last, 'note');
      await tester.enterText(types.last, 'TEXT');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create Table'));
      await tester.pumpAndSettle();

      expect(
        executed,
        'CREATE TABLE `shop`.`orders` (\n'
        '  `id` BIGINT NOT NULL,\n'
        '  `note` TEXT,\n'
        '  PRIMARY KEY (`id`)\n'
        ');',
      );
      expect(find.text('Create Table'), findsNothing);
    });
  }
}
