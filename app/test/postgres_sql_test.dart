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

  group('column DDL operations', () {
    test('buildAddColumnSql basic and with options', () {
      expect(
        buildAddColumnSql(
          schema: 'public',
          table: 'users',
          name: 'email',
          type: 'text',
          notNull: true,
          defaultExpr: "''",
          comment: 'User email',
        ),
        'ALTER TABLE public.users ADD COLUMN email text DEFAULT \'\' NOT NULL;\n'
        "COMMENT ON COLUMN public.users.email IS 'User email';",
      );

      expect(
        buildAddColumnSql(
          schema: 'public',
          table: 'users',
          name: 'id',
          type: 'bigint',
          isPrimaryKey: true,
        ),
        'ALTER TABLE public.users ADD COLUMN id bigint PRIMARY KEY;',
      );
    });

    test('buildDropColumnSql without and with cascade', () {
      expect(
        buildDropColumnSql(schema: 'public', table: 'users', name: 'temp'),
        'ALTER TABLE public.users DROP COLUMN temp;',
      );
      expect(
        buildDropColumnSql(
          schema: 'public',
          table: 'users',
          name: 'temp',
          cascade: true,
        ),
        'ALTER TABLE public.users DROP COLUMN temp CASCADE;',
      );
    });

    test('buildAlterColumnSql rename, type, nullability and default', () {
      final sql = buildAlterColumnSql(
        schema: 'public',
        table: 'users',
        oldName: 'phone',
        newName: 'phone_number',
        oldType: 'varchar(20)',
        newType: 'varchar(50)',
        oldNotNull: false,
        newNotNull: true,
        oldDefault: null,
        newDefault: "'+1'",
        comment: 'Formatted phone',
      );

      expect(
        sql,
        'ALTER TABLE public.users RENAME COLUMN phone TO phone_number;\n'
        'ALTER TABLE public.users ALTER COLUMN phone_number TYPE varchar(50);\n'
        'ALTER TABLE public.users ALTER COLUMN phone_number SET NOT NULL;\n'
        "ALTER TABLE public.users ALTER COLUMN phone_number SET DEFAULT '+1';\n"
        "COMMENT ON COLUMN public.users.phone_number IS 'Formatted phone';",
      );
    });
  });

  group('constraint DDL operations', () {
    test('buildAddConstraintSql primary key, unique, check, foreign key', () {
      expect(
        buildAddConstraintSql(
          schema: 'public',
          table: 'orders',
          name: 'orders_pk',
          kind: ConstraintKind.primaryKey,
          columns: const ['id'],
        ),
        'ALTER TABLE public.orders ADD CONSTRAINT orders_pk PRIMARY KEY (id);',
      );

      expect(
        buildAddConstraintSql(
          schema: 'public',
          table: 'users',
          name: 'users_email_uniq',
          kind: ConstraintKind.unique,
          columns: const ['email'],
        ),
        'ALTER TABLE public.users ADD CONSTRAINT users_email_uniq UNIQUE (email);',
      );

      expect(
        buildAddConstraintSql(
          schema: 'public',
          table: 'items',
          name: 'check_qty',
          kind: ConstraintKind.check,
          expression: 'qty >= 0',
        ),
        'ALTER TABLE public.items ADD CONSTRAINT check_qty CHECK (qty >= 0);',
      );

      expect(
        buildAddConstraintSql(
          schema: 'public',
          table: 'orders',
          name: 'fk_orders_user',
          kind: ConstraintKind.foreignKey,
          columns: const ['user_id'],
          referencedSchema: 'public',
          referencedTable: 'users',
          referencedColumns: const ['id'],
          onDelete: 'CASCADE',
        ),
        'ALTER TABLE public.orders ADD CONSTRAINT fk_orders_user '
        'FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE;',
      );
    });

    test('buildDropConstraintSql', () {
      expect(
        buildDropConstraintSql(
          schema: 'public',
          table: 'orders',
          name: 'orders_pk',
          cascade: true,
        ),
        'ALTER TABLE public.orders DROP CONSTRAINT orders_pk CASCADE;',
      );
    });

    test('buildAlterConstraintSql rename or replace', () {
      expect(
        buildAlterConstraintSql(
          schema: 'public',
          table: 'orders',
          oldName: 'orders_pk',
          newName: 'pk_orders',
        ),
        'ALTER TABLE public.orders RENAME CONSTRAINT orders_pk TO pk_orders;',
      );

      expect(
        buildAlterConstraintSql(
          schema: 'public',
          table: 'items',
          oldName: 'check_qty',
          newName: 'check_qty',
          newDefinition: 'CHECK (qty > 0)',
        ),
        'ALTER TABLE public.items DROP CONSTRAINT check_qty,\n'
        '    ADD CONSTRAINT check_qty CHECK (qty > 0);',
      );
    });
  });

  group('index DDL operations', () {
    test('buildCreateIndexSql basic and options', () {
      expect(
        buildCreateIndexSql(
          schema: 'public',
          table: 'users',
          name: 'users_email_idx',
          columns: const ['email'],
          isUnique: true,
          method: 'btree',
          predicate: 'deleted_at IS NULL',
        ),
        'CREATE UNIQUE INDEX users_email_idx ON public.users (email) WHERE deleted_at IS NULL;',
      );
    });

    test('buildDropIndexSql', () {
      expect(
        buildDropIndexSql(schema: 'public', name: 'users_email_idx', cascade: true),
        'DROP INDEX public.users_email_idx CASCADE;',
      );
    });

    test('buildAlterIndexSql', () {
      expect(
        buildAlterIndexSql(
          schema: 'public',
          oldName: 'old_idx',
          newName: 'new_idx',
        ),
        'ALTER INDEX public.old_idx RENAME TO new_idx;',
      );
    });
  });

  group('trigger DDL operations', () {
    test('buildCreateTriggerSql', () {
      expect(
        buildCreateTriggerSql(
          schema: 'public',
          table: 'users',
          name: 'trg_users_updated',
          timing: 'BEFORE',
          events: const ['UPDATE'],
          functionName: 'set_timestamp',
        ),
        'CREATE TRIGGER trg_users_updated\n'
        '    BEFORE UPDATE\n'
        '    ON public.users\n'
        '    FOR EACH ROW\n'
        '    EXECUTE FUNCTION set_timestamp();',
      );
    });

    test('buildDropTriggerSql', () {
      expect(
        buildDropTriggerSql(schema: 'public', table: 'users', name: 'trg_test'),
        'DROP TRIGGER trg_test ON public.users;',
      );
    });

    test('buildAlterTriggerSql rename and enable/disable', () {
      expect(
        buildAlterTriggerSql(
          schema: 'public',
          table: 'users',
          oldName: 'old_trg',
          newName: 'new_trg',
          enabled: false,
        ),
        'ALTER TRIGGER old_trg ON public.users RENAME TO new_trg;\n'
        'ALTER TABLE public.users DISABLE TRIGGER new_trg;',
      );
    });
  });

  test('buildAlterColumnSql type change with USING', () {
    expect(
      buildAlterColumnSql(
        schema: 'public',
        table: 'orders',
        oldName: 'amount',
        oldType: 'text',
        newType: 'numeric(10,2)',
        using: 'amount::numeric',
      ),
      'ALTER TABLE public.orders ALTER COLUMN amount TYPE numeric(10,2) '
      'USING amount::numeric;',
    );
  });

  test('buildAlterColumnSql removes a cleared comment', () {
    expect(
      buildAlterColumnSql(
        schema: 'public',
        table: 'orders',
        oldName: 'amount',
        comment: '',
      ),
      'COMMENT ON COLUMN public.orders.amount IS NULL;',
    );
  });

  test('foreign key without target columns references the primary key', () {
    expect(
      buildAddConstraintSql(
        schema: 'public',
        table: 'orders',
        kind: ConstraintKind.foreignKey,
        columns: ['user_id'],
        referencedTable: 'users',
      ),
      'ALTER TABLE public.orders ADD FOREIGN KEY (user_id) '
      'REFERENCES public.users;',
    );
  });
}
