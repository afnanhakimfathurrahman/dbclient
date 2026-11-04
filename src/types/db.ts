export type DatabaseEngine = 
  | 'postgresql'
  | 'mongodb'
  | 'clickhouse'
  | 'mysql'
  | 'sqlite'
  | 'redis'
  | 'cassandra'
  | 'snowflake'
  | 'duckdb'
  | 'oracle'
  | 'sqlserver'
  | 'custom';

export interface DriverInfo {
  id: string;
  name: string;
  engine: DatabaseEngine;
  version: string;
  category: 'SQL' | 'NoSQL' | 'Analytical' | 'Key-Value' | 'Time-Series';
  defaultPort: number;
  driverClass: string;
  downloadUrl?: string;
  fileSize: string;
  isInstalled: boolean;
  isBuiltIn: boolean;
  description: string;
  icon: string;
  sampleUrl: string;
  docUrl: string;
}

export interface ConnectionConfig {
  id: string;
  name: string;
  driverId: string;
  engine: DatabaseEngine;
  host: string;
  port: number;
  database: string;
  username: string;
  password?: string;
  ssl: boolean;
  colorTag?: string; // e.g. blue for dev, red for prod
  isConnected?: boolean;
  lastConnected?: string;
  pingMs?: number;
  customParameters?: Record<string, string>;
}

export interface ColumnDefinition {
  name: string;
  type: string;
  isPrimaryKey?: boolean;
  isNullable: boolean;
  defaultValue?: string | null;
  comment?: string;
  isForeignKey?: boolean;
  foreignKeyRef?: {
    table: string;
    column: string;
  };
  codec?: string; // ClickHouse codec, e.g. ZSTD(1), LZ4
}

export interface IndexDefinition {
  name: string;
  columns: string[];
  type: 'BTREE' | 'HASH' | 'GIN' | 'GIST' | 'COMPOUND' | 'TEXT' | 'TTL' | 'UNIQUE' | 'ORDER_BY';
  isUnique: boolean;
  sizeBytes?: number;
  definition?: string;
  comment?: string;
}

export interface PartitionDefinition {
  name: string;
  expression: string; // e.g. RANGE (payment_date) or toYYYYMM(event_time)
  type: 'RANGE' | 'LIST' | 'HASH' | 'MERGETREE_PARTITION';
  valuesRange?: string; // e.g. '2024-01-01' to '2024-02-01'
  rowCount: number;
  sizeBytes: number;
  isActive: boolean;
}

export interface ConstraintDefinition {
  name: string;
  type: 'PRIMARY KEY' | 'FOREIGN KEY' | 'CHECK' | 'UNIQUE' | 'EXCLUSION';
  columns: string[];
  referencedTable?: string;
  referencedColumns?: string[];
  onDelete?: 'CASCADE' | 'SET NULL' | 'RESTRICT' | 'NO ACTION';
  onUpdate?: 'CASCADE' | 'SET NULL' | 'RESTRICT' | 'NO ACTION';
  checkExpression?: string;
}

export interface TableMetadata {
  id: string;
  name: string;
  schema: string;
  type: 'TABLE' | 'VIEW' | 'COLLECTION' | 'MATERIALIZED_VIEW';
  engine?: string; // e.g., 'MergeTree', 'InnoDB', 'PostgreSQL Heap'
  rowCount: number;
  sizeBytes: number;
  comment?: string;
  columns: ColumnDefinition[];
  indexes: IndexDefinition[];
  partitions: PartitionDefinition[];
  constraints: ConstraintDefinition[];
  rows: Record<string, any>[];
  ddl?: string;
}

export interface SchemaMetadata {
  id: string;
  name: string;
  tables: TableMetadata[];
}

export interface DatabaseCatalog {
  name: string;
  schemas: SchemaMetadata[];
}

export interface QueryResult {
  queryId: string;
  sql: string;
  connectionId: string;
  database: string;
  executionTimeMs: number;
  rowCount: number;
  columns: string[];
  rows: Record<string, any>[];
  error?: string;
  timestamp: string;
  executionPlan?: QueryPlanNode;
}

export interface QueryPlanNode {
  nodeType: string;
  relationName?: string;
  alias?: string;
  startupCost?: number;
  totalCost?: number;
  planRows?: number;
  planWidth?: number;
  actualStartupTime?: number;
  actualTotalTime?: number;
  actualRows?: number;
  actualLoops?: number;
  filter?: string;
  condition?: string;
  plans?: QueryPlanNode[];
}

export interface QueryHistoryItem {
  id: string;
  connectionId: string;
  connectionName: string;
  sql: string;
  executionTimeMs: number;
  rowCount: number;
  status: 'SUCCESS' | 'ERROR';
  errorMessage?: string;
  timestamp: string;
}

export interface EditorTab {
  id: string;
  title: string;
  type: 'SQL' | 'TABLE_VIEW' | 'ERD' | 'DRIVERS';
  connectionId: string;
  content?: string; // SQL text
  tableTarget?: {
    connectionId: string;
    schema: string;
    tableName: string;
    activeTab?: 'data' | 'columns' | 'indexes' | 'partitions' | 'constraints' | 'ddl' | 'erd';
  };
}

export type ExportFormat = 'CSV' | 'JSON' | 'SQL' | 'MARKDOWN' | 'TSV' | 'HTML';

export interface ExportOptions {
  format: ExportFormat;
  includeHeaders: boolean;
  delimiter: string;
  tableName: string;
  selectedOnly: boolean;
  quoteStrings: boolean;
}
