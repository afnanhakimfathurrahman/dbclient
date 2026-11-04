import { 
  ConnectionConfig, 
  DriverInfo, 
  TableMetadata, 
  DatabaseCatalog, 
  ColumnDefinition, 
  IndexDefinition, 
  PartitionDefinition, 
  ConstraintDefinition 
} from '../types/db';

export const INITIAL_DRIVERS: DriverInfo[] = [
  // Built-in drivers
  {
    id: 'driver-postgres',
    name: 'PostgreSQL JDBC Driver',
    engine: 'postgresql',
    version: '42.7.3',
    category: 'SQL',
    defaultPort: 5432,
    driverClass: 'org.postgresql.Driver',
    fileSize: '1.4 MB',
    isInstalled: true,
    isBuiltIn: true,
    description: 'Official production driver for PostgreSQL 11-16 with SSL, UUID, JSONB, and array support.',
    icon: '🐘',
    sampleUrl: 'jdbc:postgresql://localhost:5432/postgres',
    docUrl: 'https://jdbc.postgresql.org/',
  },
  {
    id: 'driver-mongo',
    name: 'MongoDB Java / BSON Driver',
    engine: 'mongodb',
    version: '5.1.0',
    category: 'NoSQL',
    defaultPort: 27017,
    driverClass: 'com.mongodb.client.MongoClient',
    fileSize: '4.2 MB',
    isInstalled: true,
    isBuiltIn: true,
    description: 'High performance driver for MongoDB Replica Sets, Sharded Clusters, and Atlas deployments.',
    icon: '🍃',
    sampleUrl: 'mongodb://localhost:27017/admin',
    docUrl: 'https://www.mongodb.com/docs/drivers/java/sync/current/',
  },
  {
    id: 'driver-clickhouse',
    name: 'ClickHouse Native JDBC',
    engine: 'clickhouse',
    version: '0.6.0',
    category: 'Analytical',
    defaultPort: 8123,
    driverClass: 'com.clickhouse.jdbc.ClickHouseDriver',
    fileSize: '6.8 MB',
    isInstalled: true,
    isBuiltIn: true,
    description: 'Ultra-fast columnar OLAP database driver supporting MergeTree, codecs, and parallel query pipelines.',
    icon: '⚡',
    sampleUrl: 'jdbc:clickhouse://localhost:8123/default',
    docUrl: 'https://clickhouse.com/docs/en/integrations/jdbc',
  },
  // Extensible drivers (Available to download)
  {
    id: 'driver-mysql',
    name: 'MySQL Connector/J',
    engine: 'mysql',
    version: '8.3.0',
    category: 'SQL',
    defaultPort: 3306,
    driverClass: 'com.mysql.cj.jdbc.Driver',
    fileSize: '2.5 MB',
    isInstalled: false,
    isBuiltIn: false,
    description: 'Type 4 pure Java driver for MySQL 8.0+ and MariaDB with X DevAPI support.',
    icon: '🐬',
    sampleUrl: 'jdbc:mysql://localhost:3306/mysql',
    docUrl: 'https://dev.mysql.com/doc/connector-j/en/',
  },
  {
    id: 'driver-sqlite',
    name: 'SQLite JDBC Engine',
    engine: 'sqlite',
    version: '3.45.2',
    category: 'SQL',
    defaultPort: 0,
    driverClass: 'org.sqlite.JDBC',
    fileSize: '11.8 MB',
    isInstalled: false,
    isBuiltIn: false,
    description: 'Self-contained embedded SQL database engine driver with full ACID transactions.',
    icon: '🪶',
    sampleUrl: 'jdbc:sqlite:/var/data/app.db',
    docUrl: 'https://github.com/xerial/sqlite-jdbc',
  },
  {
    id: 'driver-redis',
    name: 'Redis RESP3 Client',
    engine: 'redis',
    version: '7.2.4',
    category: 'Key-Value',
    defaultPort: 6379,
    driverClass: 'redis.clients.jedis.JedisPool',
    fileSize: '3.1 MB',
    isInstalled: false,
    isBuiltIn: false,
    description: 'In-memory data structure store driver for caching, streaming, and pub/sub.',
    icon: '🔴',
    sampleUrl: 'redis://:auth@localhost:6379/0',
    docUrl: 'https://redis.io/docs/connect/clients/',
  },
  {
    id: 'driver-snowflake',
    name: 'Snowflake JDBC Driver',
    engine: 'snowflake',
    version: '3.16.0',
    category: 'Analytical',
    defaultPort: 443,
    driverClass: 'net.snowflake.client.jdbc.SnowflakeDriver',
    fileSize: '22.4 MB',
    isInstalled: false,
    isBuiltIn: false,
    description: 'Cloud data platform driver for Snowflake virtual warehouses and data mesh.',
    icon: '❄️',
    sampleUrl: 'jdbc:snowflake://xy12345.snowflakecomputing.com/?db=ANALYTICS',
    docUrl: 'https://docs.snowflake.com/en/developer-guide/jdbc/jdbc',
  },
  {
    id: 'driver-duckdb',
    name: 'DuckDB In-Memory OLAP',
    engine: 'duckdb',
    version: '0.10.1',
    category: 'Analytical',
    defaultPort: 0,
    driverClass: 'org.duckdb.DuckDBDriver',
    fileSize: '18.2 MB',
    isInstalled: false,
    isBuiltIn: false,
    description: 'Fast analytical in-process database management system optimized for columnar processing.',
    icon: '🦆',
    sampleUrl: 'jdbc:duckdb:analytics.duckdb',
    docUrl: 'https://duckdb.org/docs/api/java',
  },
  {
    id: 'driver-cassandra',
    name: 'Apache Cassandra Driver',
    engine: 'cassandra',
    version: '4.17.0',
    category: 'NoSQL',
    defaultPort: 9042,
    driverClass: 'com.datastax.oss.driver.api.core.CqlSession',
    fileSize: '5.6 MB',
    isInstalled: false,
    isBuiltIn: false,
    description: 'Distributed wide-column store CQL driver for Cassandra and ScyllaDB clusters.',
    icon: '👁️',
    sampleUrl: 'cql://localhost:9042/keyspace',
    docUrl: 'https://cassandra.apache.org/',
  },
  {
    id: 'driver-sqlserver',
    name: 'Microsoft JDBC for SQL Server',
    engine: 'sqlserver',
    version: '12.6.1',
    category: 'SQL',
    defaultPort: 1433,
    driverClass: 'com.microsoft.sqlserver.jdbc.SQLServerDriver',
    fileSize: '4.8 MB',
    isInstalled: false,
    isBuiltIn: false,
    description: 'Enterprise driver for Microsoft SQL Server and Azure SQL Database with Always Encrypted.',
    icon: '🟦',
    sampleUrl: 'jdbc:sqlserver://localhost:1433;databaseName=master',
    docUrl: 'https://learn.microsoft.com/en-us/sql/connect/jdbc/',
  },
];

export const INITIAL_CONNECTIONS: ConnectionConfig[] = [
  {
    id: 'conn-pg-prod',
    name: 'PostgreSQL 16 - Production OLTP',
    driverId: 'driver-postgres',
    engine: 'postgresql',
    host: 'db.prod.us-east.aws.internal',
    port: 5432,
    database: 'ecommerce_prod',
    username: 'postgres_admin',
    ssl: true,
    colorTag: '#3b82f6', // blue
    isConnected: true,
    lastConnected: 'Just now',
    pingMs: 24,
  },
  {
    id: 'conn-mongo-cluster',
    name: 'MongoDB 7.0 - E-Commerce Atlas',
    driverId: 'driver-mongo',
    engine: 'mongodb',
    host: 'cluster0.mongodb.net',
    port: 27017,
    database: 'shop_db',
    username: 'app_user',
    ssl: true,
    colorTag: '#10b981', // green
    isConnected: true,
    lastConnected: '5m ago',
    pingMs: 38,
  },
  {
    id: 'conn-clickhouse-olap',
    name: 'ClickHouse 24.3 - BigData Events Warehouse',
    driverId: 'driver-clickhouse',
    engine: 'clickhouse',
    host: 'clickhouse.analytics.cloud',
    port: 8123,
    database: 'analytics_warehouse',
    username: 'clickhouse_reader',
    ssl: false,
    colorTag: '#f59e0b', // amber
    isConnected: true,
    lastConnected: '12m ago',
    pingMs: 18,
  },
];

// Helper to generate DDL string from table metadata
export function generateDDL(table: TableMetadata, engine: string = 'postgresql'): string {
  if (engine === 'mongodb' || table.type === 'COLLECTION') {
    return `// MongoDB Collection Definition: ${table.name}
db.createCollection("${table.name}", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ${JSON.stringify(table.columns.filter(c => !c.isNullable).map(c => c.name))},
      properties: {
${table.columns.map(c => `        "${c.name}": { bsonType: "${c.type.toLowerCase()}", description: "${c.comment || c.name}" }`).join(',\n')}
      }
    }
  }
});

// Indexes:
${table.indexes.map(idx => `db.${table.name}.createIndex(${JSON.stringify(idx.columns.reduce((acc, col) => ({ ...acc, [col]: 1 }), {}))}, { name: "${idx.name}", unique: ${idx.isUnique} });`).join('\n')}`;
  }

  if (engine === 'clickhouse') {
    const colLines = table.columns.map(col => {
      let str = `  "${col.name}" ${col.type}`;
      if (col.codec) str += ` CODEC(${col.codec})`;
      if (col.defaultValue) str += ` DEFAULT ${col.defaultValue}`;
      if (col.comment) str += ` COMMENT '${col.comment}'`;
      return str;
    });

    let ddl = `CREATE TABLE ${table.schema}.${table.name} (\n${colLines.join(',\n')}\n)\n`;
    ddl += `ENGINE = ${table.engine || 'MergeTree()'}\n`;
    
    if (table.partitions && table.partitions.length > 0) {
      ddl += `PARTITION BY ${table.partitions[0].expression}\n`;
    }
    
    const pk = table.indexes.find(i => i.type === 'ORDER_BY' || i.isUnique);
    if (pk) {
      ddl += `PRIMARY KEY (${pk.columns.join(', ')})\n`;
      ddl += `ORDER BY (${pk.columns.join(', ')})\n`;
    }
    ddl += `SETTINGS index_granularity = 8192;`;
    return ddl;
  }

  // Standard PostgreSQL DDL
  const colLines = table.columns.map(col => {
    let str = `  "${col.name}" ${col.type}`;
    if (col.isPrimaryKey) str += ' PRIMARY KEY';
    else if (!col.isNullable) str += ' NOT NULL';
    if (col.defaultValue) str += ` DEFAULT ${col.defaultValue}`;
    return str;
  });

  // Constraints in DDL
  const constraintLines = table.constraints
    .filter(c => c.type !== 'PRIMARY KEY')
    .map(c => {
      if (c.type === 'FOREIGN KEY') {
        return `  CONSTRAINT "${c.name}" FOREIGN KEY ("${c.columns.join('", "')}") REFERENCES "${c.referencedTable}" ("${c.referencedColumns?.join('", "')}") ON DELETE ${c.onDelete || 'NO ACTION'}`;
      }
      if (c.type === 'CHECK') {
        return `  CONSTRAINT "${c.name}" CHECK (${c.checkExpression})`;
      }
      if (c.type === 'UNIQUE') {
        return `  CONSTRAINT "${c.name}" UNIQUE ("${c.columns.join('", "')}")`;
      }
      return '';
    })
    .filter(Boolean);

  let body = [...colLines, ...constraintLines].join(',\n');
  let ddl = `CREATE TABLE "${table.schema}"."${table.name}" (\n${body}\n)`;

  if (table.partitions && table.partitions.length > 0) {
    ddl += ` PARTITION BY ${table.partitions[0].expression};\n\n`;
    // Add partition creation statements
    table.partitions.forEach(p => {
      ddl += `-- Partition: ${p.name}\nCREATE TABLE "${table.schema}"."${p.name}" PARTITION OF "${table.schema}"."${table.name}"\n  FOR VALUES ${p.valuesRange ? `FROM (${p.valuesRange.split(' to ')[0]}) TO (${p.valuesRange.split(' to ')[1]})` : 'DEFAULT'};\n\n`;
    });
  } else {
    ddl += ';\n\n';
  }

  // Indexes statements
  const indexStatements = table.indexes
    .filter(idx => !idx.columns.every(col => table.columns.find(c => c.name === col)?.isPrimaryKey))
    .map(idx => {
      const unique = idx.isUnique ? 'UNIQUE ' : '';
      return `CREATE ${unique}INDEX "${idx.name}" ON "${table.schema}"."${table.name}" USING ${idx.type.toLowerCase()} ("${idx.columns.join('", "')}");`;
    });

  if (indexStatements.length > 0) {
    ddl += indexStatements.join('\n');
  }

  return ddl;
}

// Full Initial Catalog Data
export const INITIAL_CATALOGS: Record<string, DatabaseCatalog> = {
  'conn-pg-prod': {
    name: 'ecommerce_prod',
    schemas: [
      {
        id: 'pg-schema-public',
        name: 'public',
        tables: [
          {
            id: 'tbl-users',
            name: 'users',
            schema: 'public',
            type: 'TABLE',
            engine: 'PostgreSQL Heap',
            rowCount: 45200,
            sizeBytes: 14800000,
            comment: 'Primary customer and staff credentials table',
            columns: [
              { name: 'id', type: 'BIGSERIAL', isPrimaryKey: true, isNullable: false, comment: 'Internal auto-increment user ID' },
              { name: 'username', type: 'VARCHAR(64)', isNullable: false, comment: 'Unique login username' },
              { name: 'email', type: 'VARCHAR(255)', isNullable: false, comment: 'Verified contact email' },
              { name: 'full_name', type: 'VARCHAR(128)', isNullable: true, comment: 'Legal name' },
              { name: 'role', type: 'VARCHAR(32)', isNullable: false, defaultValue: "'customer'", comment: 'Role: admin, customer, vendor' },
              { name: 'is_active', type: 'BOOLEAN', isNullable: false, defaultValue: 'true' },
              { name: 'balance_usd', type: 'NUMERIC(12,2)', isNullable: false, defaultValue: '0.00' },
              { name: 'created_at', type: 'TIMESTAMPTZ', isNullable: false, defaultValue: 'NOW()' },
              { name: 'updated_at', type: 'TIMESTAMPTZ', isNullable: true },
            ],
            indexes: [
              { name: 'idx_users_pkey', columns: ['id'], type: 'BTREE', isUnique: true, sizeBytes: 1240000 },
              { name: 'idx_users_email_unique', columns: ['email'], type: 'BTREE', isUnique: true, sizeBytes: 1840000 },
              { name: 'idx_users_role_status', columns: ['role', 'is_active'], type: 'BTREE', isUnique: false, sizeBytes: 980000 },
              { name: 'idx_users_created_at', columns: ['created_at'], type: 'BTREE', isUnique: false, sizeBytes: 1100000 },
            ],
            partitions: [],
            constraints: [
              { name: 'users_pkey', type: 'PRIMARY KEY', columns: ['id'] },
              { name: 'users_email_key', type: 'UNIQUE', columns: ['email'] },
              { name: 'users_username_check', type: 'CHECK', columns: ['username'], checkExpression: 'length(username) >= 3' },
              { name: 'users_balance_check', type: 'CHECK', columns: ['balance_usd'], checkExpression: 'balance_usd >= 0' },
            ],
            rows: [
              { id: 101, username: 'alex_chen', email: 'alex.chen@datatech.io', full_name: 'Alex Chen', role: 'admin', is_active: true, balance_usd: 1450.50, created_at: '2024-01-15T08:30:00Z', updated_at: '2024-11-01T12:00:00Z' },
              { id: 102, username: 'sarah_miller', email: 'sarah.m@gmail.com', full_name: 'Sarah Miller', role: 'customer', is_active: true, balance_usd: 320.00, created_at: '2024-02-10T14:22:15Z', updated_at: '2024-10-28T09:15:30Z' },
              { id: 103, username: 'dev_raj', email: 'raj.developer@nexus.org', full_name: 'Raj Patel', role: 'vendor', is_active: true, balance_usd: 8940.25, created_at: '2024-03-05T19:40:00Z', updated_at: '2024-11-02T16:20:00Z' },
              { id: 104, username: 'elena_rostova', email: 'elena.rostova@cloud.de', full_name: 'Elena Rostova', role: 'customer', is_active: true, balance_usd: 75.00, created_at: '2024-04-12T11:05:40Z', updated_at: '2024-09-14T18:45:00Z' },
              { id: 105, username: 'marcus_vance', email: 'm.vance@venture.com', full_name: 'Marcus Vance', role: 'customer', is_active: false, balance_usd: 0.00, created_at: '2024-05-18T16:50:22Z', updated_at: '2024-08-20T10:11:00Z' },
              { id: 106, username: 'keiko_tanaka', email: 'keiko.tanaka@tokyo.jp', full_name: 'Keiko Tanaka', role: 'customer', is_active: true, balance_usd: 2190.80, created_at: '2024-06-25T03:15:10Z', updated_at: '2024-11-03T07:22:18Z' },
              { id: 107, username: 'carlos_silva', email: 'csilva@brasil.net', full_name: 'Carlos Silva', role: 'vendor', is_active: true, balance_usd: 4410.00, created_at: '2024-07-08T22:30:00Z', updated_at: '2024-10-30T14:10:00Z' },
              { id: 108, username: 'amira_hassan', email: 'amira.h@cairo-tech.eg', full_name: 'Amira Hassan', role: 'customer', is_active: true, balance_usd: 620.40, created_at: '2024-08-19T09:12:00Z', updated_at: '2024-11-02T11:45:30Z' },
            ],
          },
          {
            id: 'tbl-products',
            name: 'products',
            schema: 'public',
            type: 'TABLE',
            engine: 'PostgreSQL Heap',
            rowCount: 8400,
            sizeBytes: 9400000,
            comment: 'E-commerce goods catalog with inventory and jsonb attributes',
            columns: [
              { name: 'id', type: 'BIGSERIAL', isPrimaryKey: true, isNullable: false },
              { name: 'sku', type: 'VARCHAR(48)', isNullable: false, comment: 'Stock keeping unit barcode' },
              { name: 'name', type: 'VARCHAR(200)', isNullable: false },
              { name: 'category', type: 'VARCHAR(64)', isNullable: false },
              { name: 'price', type: 'NUMERIC(10,2)', isNullable: false },
              { name: 'cost_price', type: 'NUMERIC(10,2)', isNullable: false },
              { name: 'stock_quantity', type: 'INT', isNullable: false, defaultValue: '0' },
              { name: 'attributes', type: 'JSONB', isNullable: true, comment: 'Flexible specs (weight, color, dims)' },
              { name: 'is_published', type: 'BOOLEAN', isNullable: false, defaultValue: 'true' },
              { name: 'created_at', type: 'TIMESTAMPTZ', isNullable: false, defaultValue: 'NOW()' },
            ],
            indexes: [
              { name: 'idx_products_pkey', columns: ['id'], type: 'BTREE', isUnique: true, sizeBytes: 740000 },
              { name: 'idx_products_sku_uniq', columns: ['sku'], type: 'BTREE', isUnique: true, sizeBytes: 820000 },
              { name: 'idx_products_category', columns: ['category'], type: 'BTREE', isUnique: false, sizeBytes: 510000 },
              { name: 'idx_products_attributes_gin', columns: ['attributes'], type: 'GIN', isUnique: false, sizeBytes: 1650000 },
            ],
            partitions: [],
            constraints: [
              { name: 'products_pkey', type: 'PRIMARY KEY', columns: ['id'] },
              { name: 'products_sku_unique', type: 'UNIQUE', columns: ['sku'] },
              { name: 'products_price_positive', type: 'CHECK', columns: ['price'], checkExpression: 'price > 0' },
              { name: 'products_stock_positive', type: 'CHECK', columns: ['stock_quantity'], checkExpression: 'stock_quantity >= 0' },
            ],
            rows: [
              { id: 501, sku: 'TECH-LOGI-MX3', name: 'Logitech MX Master 3S Mouse', category: 'Peripherals', price: 99.99, cost_price: 55.00, stock_quantity: 142, attributes: { dpi: 8000, wireless: true, color: 'Graphite' }, is_published: true, created_at: '2024-01-20T10:00:00Z' },
              { id: 502, sku: 'TECH-KEY-K2PRO', name: 'Keychron K2 Pro Mechanical Keyboard', category: 'Peripherals', price: 119.00, cost_price: 68.50, stock_quantity: 78, attributes: { switch: 'Gateron Brown', layout: '75%', rgb: true }, is_published: true, created_at: '2024-02-05T14:30:00Z' },
              { id: 503, sku: 'MON-DELL-U2723', name: 'Dell UltraSharp 27" 4K USB-C Hub Monitor', category: 'Displays', price: 579.99, cost_price: 410.00, stock_quantity: 26, attributes: { panel: 'IPS Black', resolution: '3840x2160', usb_pd: '90W' }, is_published: true, created_at: '2024-02-18T09:15:00Z' },
              { id: 504, sku: 'AUDIO-SONY-WHXM5', name: 'Sony WH-1000XM5 Wireless Headphones', category: 'Audio', price: 348.00, cost_price: 240.00, stock_quantity: 65, attributes: { anc: true, battery_hours: 30, codec: 'LDAC' }, is_published: true, created_at: '2024-03-12T16:40:00Z' },
              { id: 505, sku: 'FURN-ERGO-CHAIR', name: 'Herman Miller Embody Chair', category: 'Furniture', price: 1795.00, cost_price: 1100.00, stock_quantity: 12, attributes: { fabric: 'Sync Black', warranty: '12yr', armrests: '4D' }, is_published: true, created_at: '2024-03-25T11:20:00Z' },
              { id: 506, sku: 'STOR-SAMS-990PRO', name: 'Samsung 990 PRO 2TB PCIe 4.0 NVMe SSD', category: 'Storage', price: 169.99, cost_price: 115.00, stock_quantity: 210, attributes: { speed_read_mb: 7450, form_factor: 'M.2 2280' }, is_published: true, created_at: '2024-04-02T13:00:00Z' },
            ],
          },
          {
            id: 'tbl-orders',
            name: 'orders',
            schema: 'public',
            type: 'TABLE',
            engine: 'PostgreSQL Heap',
            rowCount: 98400,
            sizeBytes: 28500000,
            comment: 'E-commerce purchase orders master table',
            columns: [
              { name: 'id', type: 'BIGSERIAL', isPrimaryKey: true, isNullable: false },
              { name: 'order_number', type: 'VARCHAR(32)', isNullable: false },
              { name: 'user_id', type: 'BIGINT', isNullable: false, isForeignKey: true, foreignKeyRef: { table: 'users', column: 'id' } },
              { name: 'status', type: 'VARCHAR(24)', isNullable: false, defaultValue: "'PENDING'" },
              { name: 'total_amount', type: 'NUMERIC(12,2)', isNullable: false },
              { name: 'tax_amount', type: 'NUMERIC(10,2)', isNullable: false, defaultValue: '0.00' },
              { name: 'shipping_city', type: 'VARCHAR(64)', isNullable: true },
              { name: 'shipping_country', type: 'VARCHAR(3)', isNullable: false, defaultValue: "'USA'" },
              { name: 'created_at', type: 'TIMESTAMPTZ', isNullable: false, defaultValue: 'NOW()' },
            ],
            indexes: [
              { name: 'idx_orders_pkey', columns: ['id'], type: 'BTREE', isUnique: true, sizeBytes: 2400000 },
              { name: 'idx_orders_order_number', columns: ['order_number'], type: 'BTREE', isUnique: true, sizeBytes: 3100000 },
              { name: 'idx_orders_user_id', columns: ['user_id'], type: 'BTREE', isUnique: false, sizeBytes: 1950000 },
              { name: 'idx_orders_status_date', columns: ['status', 'created_at'], type: 'BTREE', isUnique: false, sizeBytes: 2600000 },
            ],
            partitions: [],
            constraints: [
              { name: 'orders_pkey', type: 'PRIMARY KEY', columns: ['id'] },
              { name: 'orders_number_uniq', type: 'UNIQUE', columns: ['order_number'] },
              { name: 'fk_orders_user', type: 'FOREIGN KEY', columns: ['user_id'], referencedTable: 'users', referencedColumns: ['id'], onDelete: 'RESTRICT', onUpdate: 'CASCADE' },
              { name: 'orders_total_check', type: 'CHECK', columns: ['total_amount'], checkExpression: 'total_amount >= 0' },
            ],
            rows: [
              { id: 9001, order_number: 'ORD-2024-8891', user_id: 101, status: 'COMPLETED', total_amount: 679.98, tax_amount: 54.40, shipping_city: 'San Francisco', shipping_country: 'USA', created_at: '2024-10-15T11:20:00Z' },
              { id: 9002, order_number: 'ORD-2024-8892', user_id: 102, status: 'SHIPPED', total_amount: 119.00, tax_amount: 9.52, shipping_city: 'Austin', shipping_country: 'USA', created_at: '2024-10-18T14:45:10Z' },
              { id: 9003, order_number: 'ORD-2024-8893', user_id: 104, status: 'PROCESSING', total_amount: 348.00, tax_amount: 27.84, shipping_city: 'Berlin', shipping_country: 'DEU', created_at: '2024-10-22T08:12:30Z' },
              { id: 9004, order_number: 'ORD-2024-8894', user_id: 106, status: 'COMPLETED', total_amount: 1795.00, tax_amount: 179.50, shipping_city: 'Tokyo', shipping_country: 'JPN', created_at: '2024-10-25T03:00:00Z' },
              { id: 9005, order_number: 'ORD-2024-8895', user_id: 103, status: 'PENDING', total_amount: 269.98, tax_amount: 21.60, shipping_city: 'London', shipping_country: 'GBR', created_at: '2024-11-01T17:35:00Z' },
              { id: 9006, order_number: 'ORD-2024-8896', user_id: 108, status: 'DELIVERED', total_amount: 99.99, tax_amount: 8.00, shipping_city: 'Cairo', shipping_country: 'EGY', created_at: '2024-11-02T19:10:00Z' },
            ],
          },
          {
            id: 'tbl-payments-partitioned',
            name: 'payment_transactions',
            schema: 'public',
            type: 'TABLE',
            engine: 'PostgreSQL Partitioned Table',
            rowCount: 142000,
            sizeBytes: 46200000,
            comment: 'High-throughput payment audit ledger partitioned by quarterly range',
            columns: [
              { name: 'id', type: 'BIGSERIAL', isPrimaryKey: true, isNullable: false },
              { name: 'order_id', type: 'BIGINT', isNullable: false, isForeignKey: true, foreignKeyRef: { table: 'orders', column: 'id' } },
              { name: 'amount', type: 'NUMERIC(12,2)', isNullable: false },
              { name: 'provider', type: 'VARCHAR(32)', isNullable: false, comment: 'Stripe, PayPal, Adyen' },
              { name: 'status', type: 'VARCHAR(24)', isNullable: false, defaultValue: "'SUCCEEDED'" },
              { name: 'transaction_ref', type: 'VARCHAR(64)', isNullable: false },
              { name: 'payment_date', type: 'DATE', isNullable: false, comment: 'Partition key column' },
              { name: 'created_at', type: 'TIMESTAMPTZ', isNullable: false, defaultValue: 'NOW()' },
            ],
            indexes: [
              { name: 'idx_payments_pkey', columns: ['id', 'payment_date'], type: 'BTREE', isUnique: true, sizeBytes: 3200000 },
              { name: 'idx_payments_order_id', columns: ['order_id'], type: 'BTREE', isUnique: false, sizeBytes: 2400000 },
              { name: 'idx_payments_ref', columns: ['transaction_ref'], type: 'BTREE', isUnique: true, sizeBytes: 2900000 },
            ],
            partitions: [
              { name: 'payments_2024_q1', expression: 'RANGE (payment_date)', type: 'RANGE', valuesRange: "'2024-01-01' to '2024-04-01'", rowCount: 28400, sizeBytes: 9200000, isActive: true },
              { name: 'payments_2024_q2', expression: 'RANGE (payment_date)', type: 'RANGE', valuesRange: "'2024-04-01' to '2024-07-01'", rowCount: 34100, sizeBytes: 11100000, isActive: true },
              { name: 'payments_2024_q3', expression: 'RANGE (payment_date)', type: 'RANGE', valuesRange: "'2024-07-01' to '2024-10-01'", rowCount: 41800, sizeBytes: 13600000, isActive: true },
              { name: 'payments_2024_q4', expression: 'RANGE (payment_date)', type: 'RANGE', valuesRange: "'2024-10-01' to '2025-01-01'", rowCount: 37700, sizeBytes: 12300000, isActive: true },
            ],
            constraints: [
              { name: 'pk_payment_trans', type: 'PRIMARY KEY', columns: ['id', 'payment_date'] },
              { name: 'fk_payments_order', type: 'FOREIGN KEY', columns: ['order_id'], referencedTable: 'orders', referencedColumns: ['id'], onDelete: 'CASCADE' },
              { name: 'chk_amount_positive', type: 'CHECK', columns: ['amount'], checkExpression: 'amount > 0' },
              { name: 'chk_valid_provider', type: 'CHECK', columns: ['provider'], checkExpression: "provider IN ('Stripe', 'PayPal', 'Adyen', 'ApplePay')" },
            ],
            rows: [
              { id: 4001, order_id: 9001, amount: 679.98, provider: 'Stripe', status: 'SUCCEEDED', transaction_ref: 'ch_3Nxy82kL90pQ', payment_date: '2024-10-15', created_at: '2024-10-15T11:21:05Z' },
              { id: 4002, order_id: 9002, amount: 119.00, provider: 'ApplePay', status: 'SUCCEEDED', transaction_ref: 'ap_884719283741', payment_date: '2024-10-18', created_at: '2024-10-18T14:46:12Z' },
              { id: 4003, order_id: 9003, amount: 348.00, provider: 'PayPal', status: 'PENDING', transaction_ref: 'pp_capture_99182', payment_date: '2024-10-22', created_at: '2024-10-22T08:13:00Z' },
              { id: 4004, order_id: 9004, amount: 1795.00, provider: 'Stripe', status: 'SUCCEEDED', transaction_ref: 'ch_4Az711mB820k', payment_date: '2024-10-25', created_at: '2024-10-25T03:01:40Z' },
              { id: 4005, order_id: 9006, amount: 99.99, provider: 'Adyen', status: 'SUCCEEDED', transaction_ref: 'adyen_tx_771892', payment_date: '2024-11-02', created_at: '2024-11-02T19:11:15Z' },
            ],
          },
        ],
      },
      {
        id: 'pg-schema-analytics',
        name: 'analytics',
        tables: [
          {
            id: 'tbl-daily-kpis',
            name: 'daily_revenue_kpis',
            schema: 'analytics',
            type: 'VIEW',
            rowCount: 365,
            sizeBytes: 128000,
            comment: 'Materialized aggregation view for executive BI dashboards',
            columns: [
              { name: 'report_date', type: 'DATE', isPrimaryKey: true, isNullable: false },
              { name: 'gross_merchandise_usd', type: 'NUMERIC(14,2)', isNullable: false },
              { name: 'orders_count', type: 'INT', isNullable: false },
              { name: 'unique_buyers', type: 'INT', isNullable: false },
              { name: 'average_order_value', type: 'NUMERIC(10,2)', isNullable: false },
            ],
            indexes: [
              { name: 'idx_kpi_date', columns: ['report_date'], type: 'BTREE', isUnique: true, sizeBytes: 32000 },
            ],
            partitions: [],
            constraints: [],
            rows: [
              { report_date: '2024-11-01', gross_merchandise_usd: 48920.50, orders_count: 512, unique_buyers: 480, average_order_value: 95.54 },
              { report_date: '2024-11-02', gross_merchandise_usd: 62410.00, orders_count: 648, unique_buyers: 610, average_order_value: 96.31 },
              { report_date: '2024-11-03', gross_merchandise_usd: 54100.25, orders_count: 570, unique_buyers: 535, average_order_value: 94.91 },
            ],
          },
        ],
      },
    ],
  },
  'conn-mongo-cluster': {
    name: 'shop_db',
    schemas: [
      {
        id: 'mongo-schema-shop',
        name: 'shop_db',
        tables: [
          {
            id: 'col-customers',
            name: 'customers',
            schema: 'shop_db',
            type: 'COLLECTION',
            engine: 'WiredTiger',
            rowCount: 86500,
            sizeBytes: 38200000,
            comment: 'MongoDB document collection with nested JSON profiles',
            columns: [
              { name: '_id', type: 'ObjectId', isPrimaryKey: true, isNullable: false },
              { name: 'email', type: 'String', isNullable: false },
              { name: 'profile', type: 'Object', isNullable: false, comment: '{ fullName, tier, preferences }' },
              { name: 'loyaltyPoints', type: 'Int32', isNullable: false, defaultValue: '0' },
              { name: 'tags', type: 'Array', isNullable: true },
              { name: 'lastLogin', type: 'Date', isNullable: true },
            ],
            indexes: [
              { name: '_id_', columns: ['_id'], type: 'BTREE', isUnique: true, sizeBytes: 2800000 },
              { name: 'email_1', columns: ['email'], type: 'BTREE', isUnique: true, sizeBytes: 3400000 },
              { name: 'tags_1', columns: ['tags'], type: 'COMPOUND', isUnique: false, sizeBytes: 1900000 },
            ],
            partitions: [],
            constraints: [
              { name: 'validator_jsonSchema', type: 'CHECK', columns: ['email', 'profile'], checkExpression: '$jsonSchema validation enabled' },
            ],
            rows: [
              { _id: '65f8a1b2c3d4e5f607182901', email: 'jordan.lee@techhub.com', profile: { fullName: 'Jordan Lee', tier: 'Platinum', vip: true }, loyaltyPoints: 3450, tags: ['early-adopter', 'peripherals'], lastLogin: '2024-11-02T18:30:00Z' },
              { _id: '65f8a1b2c3d4e5f607182902', email: 'maya.lin@designstudio.ca', profile: { fullName: 'Maya Lin', tier: 'Gold', vip: false }, loyaltyPoints: 1200, tags: ['designer', 'monitors'], lastLogin: '2024-11-03T11:15:20Z' },
              { _id: '65f8a1b2c3d4e5f607182903', email: 'samir.khan@startups.co', profile: { fullName: 'Samir Khan', tier: 'Silver', vip: false }, loyaltyPoints: 450, tags: ['audio', 'workstation'], lastLogin: '2024-10-31T09:40:00Z' },
            ],
          },
          {
            id: 'col-events',
            name: 'events_stream',
            schema: 'shop_db',
            type: 'COLLECTION',
            engine: 'WiredTiger',
            rowCount: 320000,
            sizeBytes: 84000000,
            comment: 'TTL telemetry event collection',
            columns: [
              { name: '_id', type: 'ObjectId', isPrimaryKey: true, isNullable: false },
              { name: 'sessionId', type: 'String', isNullable: false },
              { name: 'action', type: 'String', isNullable: false },
              { name: 'metadata', type: 'Object', isNullable: true },
              { name: 'createdAt', type: 'Date', isNullable: false },
            ],
            indexes: [
              { name: '_id_', columns: ['_id'], type: 'BTREE', isUnique: true, sizeBytes: 5200000 },
              { name: 'createdAt_ttl', columns: ['createdAt'], type: 'TTL', isUnique: false, sizeBytes: 4100000, comment: 'expireAfterSeconds: 2592000 (30 days)' },
            ],
            partitions: [],
            constraints: [],
            rows: [
              { _id: '6720f1882a9d816172a01', sessionId: 'sess_99182a', action: 'page_view_home', metadata: { referrer: 'google.com', device: 'desktop' }, createdAt: '2024-11-03T22:10:00Z' },
              { _id: '6720f1882a9d816172a02', sessionId: 'sess_99182a', action: 'add_to_cart', metadata: { sku: 'TECH-LOGI-MX3', qty: 1 }, createdAt: '2024-11-03T22:12:15Z' },
              { _id: '6720f1882a9d816172a03', sessionId: 'sess_44109b', action: 'search_query', metadata: { q: 'ergonomic keyboard' }, createdAt: '2024-11-03T22:15:40Z' },
            ],
          },
        ],
      },
    ],
  },
  'conn-clickhouse-olap': {
    name: 'analytics_warehouse',
    schemas: [
      {
        id: 'ch-schema-warehouse',
        name: 'analytics_warehouse',
        tables: [
          {
            id: 'ch-tbl-pageviews',
            name: 'pageviews_mergetree',
            schema: 'analytics_warehouse',
            type: 'TABLE',
            engine: 'MergeTree()',
            rowCount: 2450000,
            sizeBytes: 184000000,
            comment: 'ClickHouse columnar table partitioned monthly with ZSTD codecs and sorting keys',
            columns: [
              { name: 'event_date', type: 'Date', isPrimaryKey: true, isNullable: false, comment: 'Date partition key' },
              { name: 'event_time', type: 'DateTime64(3)', isNullable: false },
              { name: 'user_id', type: 'UInt64', isPrimaryKey: true, isNullable: false, codec: 'DoubleDelta' },
              { name: 'url_path', type: 'String', isNullable: false, codec: 'ZSTD(3)' },
              { name: 'http_status', type: 'UInt16', isNullable: false, defaultValue: '200' },
              { name: 'duration_ms', type: 'UInt32', isNullable: false },
              { name: 'country_code', type: 'LowCardinality(String)', isNullable: false },
              { name: 'device_type', type: 'LowCardinality(String)', isNullable: false },
            ],
            indexes: [
              { name: 'order_by_key', columns: ['event_date', 'user_id', 'event_time'], type: 'ORDER_BY', isUnique: true, comment: 'Primary sorting key' },
              { name: 'idx_country', columns: ['country_code'], type: 'BTREE', isUnique: false, comment: 'MinMax skip index' },
            ],
            partitions: [
              { name: '202408', expression: 'toYYYYMM(event_date)', type: 'MERGETREE_PARTITION', valuesRange: '2024-08-01 to 2024-08-31', rowCount: 580000, sizeBytes: 42000000, isActive: true },
              { name: '202409', expression: 'toYYYYMM(event_date)', type: 'MERGETREE_PARTITION', valuesRange: '2024-09-01 to 2024-09-30', rowCount: 640000, sizeBytes: 48000000, isActive: true },
              { name: '202410', expression: 'toYYYYMM(event_date)', type: 'MERGETREE_PARTITION', valuesRange: '2024-10-01 to 2024-10-31', rowCount: 710000, sizeBytes: 54000000, isActive: true },
              { name: '202411', expression: 'toYYYYMM(event_date)', type: 'MERGETREE_PARTITION', valuesRange: '2024-11-01 to 2024-11-30', rowCount: 520000, sizeBytes: 40000000, isActive: true },
            ],
            constraints: [
              { name: 'chk_status', type: 'CHECK', columns: ['http_status'], checkExpression: 'http_status >= 100 AND http_status < 600' },
            ],
            rows: [
              { event_date: '2024-11-01', event_time: '2024-11-01 10:14:22.184', user_id: 10048192, url_path: '/products/logi-mx3', http_status: 200, duration_ms: 42, country_code: 'US', device_type: 'Desktop' },
              { event_date: '2024-11-01', event_time: '2024-11-01 10:15:01.092', user_id: 10048192, url_path: '/checkout/review', http_status: 200, duration_ms: 118, country_code: 'US', device_type: 'Desktop' },
              { event_date: '2024-11-02', event_time: '2024-11-02 14:20:11.750', user_id: 20091823, url_path: '/search?q=keychron', http_status: 200, duration_ms: 65, country_code: 'DE', device_type: 'Mobile' },
              { event_date: '2024-11-02', event_time: '2024-11-02 16:45:33.401', user_id: 30018274, url_path: '/api/v1/recommendations', http_status: 200, duration_ms: 28, country_code: 'JP', device_type: 'Desktop' },
              { event_date: '2024-11-03', event_time: '2024-11-03 08:30:19.512', user_id: 40091829, url_path: '/products/dell-u2723', http_status: 200, duration_ms: 84, country_code: 'GB', device_type: 'Mobile' },
              { event_date: '2024-11-03', event_time: '2024-11-03 19:12:45.890', user_id: 50012938, url_path: '/cart', http_status: 200, duration_ms: 36, country_code: 'BR', device_type: 'Tablet' },
            ],
          },
        ],
      },
    ],
  },
};
