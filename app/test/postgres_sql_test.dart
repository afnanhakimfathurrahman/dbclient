import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/postgres/postgres_sql.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('quoteIdent', () {
    test('leaves plain lowercase names bare', () {
      expect(quoteIdent('orders'), 'orders');
      expect(quoteIdent('_tmp1'), '_tmp1');
    });

    test('quotes mixed case, special characters and reserved words', () {
      expect(quoteIdent('Orders'), '"Orders"');
      expect(quoteIdent('service-campaign'), '"service-campaign"');
      expect(quoteIdent('user'), '"user"');
      expect(quoteIdent('order'), '"order"');
      expect(quoteIdent('a"b'), '"a""b"');
    });
  });

  test('quoteLiteral escapes single quotes', () {
    expect(quoteLiteral("it's"), "'it''s'");
  });

  group('buildPgTableDdl', () {
    test('columns, constraints, comments, indexes and triggers', () {
      final ddl = buildPgTableDdl(
        schema: 'service-campaign',
        name: 'user',
        columns: const [
          PgColumnDdl(name: 'id', type: 'bigint', notNull: true, identity: 'a'),
          PgColumnDdl(
            name: 'email',
            type: 'text',
            notNull: true,
            comment: "user's email",
          ),
          PgColumnDdl(
            name: 'status',
            type: 'text',
            notNull: false,
            defaultExpr: "'new'::text",
          ),
          PgColumnDdl(
            name: 'total',
            type: 'numeric',
            notNull: false,
            defaultExpr: '(qty * price)',
            generated: 's',
          ),
        ],
        constraints: const [
          ConstraintInfo(
            name: 'user_pkey',
            kind: ConstraintKind.primaryKey,
            definition: 'PRIMARY KEY (id)',
          ),
        ],
        indexes: const [
          IndexInfo(
            name: 'user_email_idx',
            definition: 'CREATE INDEX user_email_idx ON x USING btree (email)',
            isUnique: false,
            isPrimary: false,
          ),
        ],
        comment: 'App users',
      );

      expect(
        ddl,
        'CREATE TABLE "service-campaign"."user" (\n'
        '    id bigint GENERATED ALWAYS AS IDENTITY,\n'
        '    email text NOT NULL,\n'
        "    status text DEFAULT 'new'::text,\n"
        '    total numeric GENERATED ALWAYS AS ((qty * price)) STORED,\n'
        '    CONSTRAINT user_pkey PRIMARY KEY (id)\n'
        ');\n'
        '\n'
        "COMMENT ON TABLE \"service-campaign\".\"user\" IS 'App users';\n"
        'COMMENT ON COLUMN "service-campaign"."user".email '
        "IS 'user''s email';\n"
        '\n'
        'CREATE INDEX user_email_idx ON x USING btree (email);\n',
      );
    });

    test('partitioned table', () {
      final ddl = buildPgTableDdl(
        schema: 'public',
        name: 'events',
        columns: const [PgColumnDdl(name: 'at', type: 'date', notNull: true)],
        partitionKey: 'RANGE (at)',
      );
      expect(ddl, endsWith(')\nPARTITION BY RANGE (at);\n'));
    });

    test('partition of a parent omits columns and indexes', () {
      final ddl = buildPgTableDdl(
        schema: 'public',
        name: 'events_2026',
        columns: const [PgColumnDdl(name: 'at', type: 'date', notNull: true)],
        indexes: const [
          IndexInfo(
            name: 'i',
            definition: 'CREATE INDEX i ON events_2026 (at)',
            isUnique: false,
            isPrimary: false,
          ),
        ],
        partitionOf: 'events',
        partitionBound: "FOR VALUES FROM ('2026-01-01') TO ('2027-01-01')",
      );
      expect(
        ddl,
        'CREATE TABLE public.events_2026 PARTITION OF events\n'
        "    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');\n",
      );
    });
  });

  test('buildPgViewDdl adds a missing semicolon', () {
    expect(
      buildPgViewDdl(schema: 'public', name: 'v', definition: ' SELECT 1'),
      'CREATE OR REPLACE VIEW public.v AS\nSELECT 1;\n',
    );
  });

  test('buildPgSequenceDdl', () {
    expect(
      buildPgSequenceDdl(
        schema: 'public',
        name: 's',
        type: 'bigint',
        start: 1,
        increment: 1,
        min: 1,
        max: 9223372036854775807,
        cache: 1,
        cycle: false,
      ),
      contains('MAXVALUE 9223372036854775807\n    CACHE 1\n    NO CYCLE;'),
    );
  });
}
