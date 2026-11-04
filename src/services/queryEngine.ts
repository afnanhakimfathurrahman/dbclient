import { DatabaseCatalog, QueryResult, QueryPlanNode, ExportFormat, ExportOptions } from '../types/db';

export class QueryEngine {
  /**
   * Executes a SQL query or NoSQL command against the provided catalog
   */
  static execute(
    queryText: string, 
    connectionId: string, 
    catalog: DatabaseCatalog,
    engine: string
  ): QueryResult {
    const startTime = performance.now();
    const trimmed = queryText.trim();
    const cleanQuery = trimmed.replace(/;+$/, '').trim();

    if (!cleanQuery) {
      return {
        queryId: `q-${Date.now()}`,
        sql: queryText,
        connectionId,
        database: catalog.name,
        executionTimeMs: 0,
        rowCount: 0,
        columns: [],
        rows: [],
        timestamp: new Date().toLocaleTimeString(),
        error: 'Empty query statement.',
      };
    }

    try {
      // Check for EXPLAIN / EXPLAIN ANALYZE
      const isExplain = /^EXPLAIN\s+/i.test(cleanQuery);
      const isAnalyze = /^EXPLAIN\s+ANALYZE\s+/i.test(cleanQuery);
      const queryToRun = isAnalyze 
        ? cleanQuery.replace(/^EXPLAIN\s+ANALYZE\s+/i, '').trim() 
        : isExplain 
          ? cleanQuery.replace(/^EXPLAIN\s+/i, '').trim() 
          : cleanQuery;

      // Handle MongoDB syntax: db.collection.find(...)
      if (engine === 'mongodb' || /^db\./i.test(queryToRun)) {
        return this.executeMongoQuery(queryToRun, connectionId, catalog, startTime);
      }

      // Handle standard SQL queries
      const result = this.executeSql(queryToRun, connectionId, catalog, startTime);

      if (isExplain) {
        // Wrap with execution plan
        const plan: QueryPlanNode = {
          nodeType: isAnalyze ? 'Hash Join (Actual Loops=1, Actual Rows=' + result.rowCount + ')' : 'Hash Join',
          startupCost: 12.4,
          totalCost: 145.8,
          planRows: result.rowCount,
          actualStartupTime: 0.12,
          actualTotalTime: Math.round((performance.now() - startTime) * 100) / 100,
          actualRows: result.rowCount,
          condition: 'u.id = o.user_id',
          plans: [
            {
              nodeType: isAnalyze ? 'Seq Scan on users u (Actual Rows=8, Filter=(is_active = true))' : 'Seq Scan on users u',
              relationName: 'users',
              alias: 'u',
              startupCost: 0.0,
              totalCost: 28.5,
              planRows: 8,
              actualStartupTime: 0.02,
              actualTotalTime: 0.15,
              filter: 'is_active = true',
            },
            {
              nodeType: isAnalyze ? 'Index Scan using idx_orders_user_id on orders o (Actual Rows=6)' : 'Index Scan on orders o',
              relationName: 'orders',
              alias: 'o',
              startupCost: 0.42,
              totalCost: 84.1,
              planRows: 6,
              actualStartupTime: 0.05,
              actualTotalTime: 0.38,
            },
          ],
        };

        const planTextRows = [
          { 'QUERY PLAN': `Hash Join  (cost=12.40..145.80 rows=${result.rowCount} width=118)` },
          { 'QUERY PLAN': `  Hash Cond: (o.user_id = u.id)` },
          { 'QUERY PLAN': `  ->  Seq Scan on public.users u  (cost=0.00..28.50 rows=8 width=64)` },
          { 'QUERY PLAN': `        Filter: (is_active = true)` },
          { 'QUERY PLAN': `  ->  Hash  (cost=84.10..84.10 rows=6 width=54)` },
          { 'QUERY PLAN': `        ->  Index Scan using idx_orders_user_id on public.orders o` },
          { 'QUERY PLAN': `Execution Time: ${(Math.round((performance.now() - startTime) * 100) / 100)} ms` },
        ];

        return {
          queryId: `q-${Date.now()}`,
          sql: queryText,
          connectionId,
          database: catalog.name,
          executionTimeMs: Math.round((performance.now() - startTime) * 10) / 10,
          rowCount: planTextRows.length,
          columns: ['QUERY PLAN'],
          rows: planTextRows,
          timestamp: new Date().toLocaleTimeString(),
          executionPlan: plan,
        };
      }

      return result;
    } catch (err: any) {
      return {
        queryId: `q-${Date.now()}`,
        sql: queryText,
        connectionId,
        database: catalog.name,
        executionTimeMs: Math.round((performance.now() - startTime) * 10) / 10,
        rowCount: 0,
        columns: [],
        rows: [],
        timestamp: new Date().toLocaleTimeString(),
        error: err.message || 'Syntax error in SQL query execution.',
      };
    }
  }

  private static executeMongoQuery(
    command: string, 
    connectionId: string, 
    catalog: DatabaseCatalog, 
    startTime: number
  ): QueryResult {
    // db.customers.find()
    const match = command.match(/^db\.([a-zA-Z0-9_-]+)\.(find|countDocuments|aggregate)\((.*)\)/i);
    if (!match) {
      // Fallback: list collections
      const collections = catalog.schemas.flatMap(s => s.tables);
      return {
        queryId: `q-${Date.now()}`,
        sql: command,
        connectionId,
        database: catalog.name,
        executionTimeMs: Math.round((performance.now() - startTime) * 10) / 10,
        rowCount: collections.length,
        columns: ['collection_name', 'document_count', 'storage_bytes'],
        rows: collections.map(c => ({
          collection_name: c.name,
          document_count: c.rowCount,
          storage_bytes: c.sizeBytes,
        })),
        timestamp: new Date().toLocaleTimeString(),
      };
    }

    const colName = match[1];
    const op = match[2].toLowerCase();

    // Find table/collection in catalog
    const allTables = catalog.schemas.flatMap(s => s.tables);
    const target = allTables.find(t => t.name.toLowerCase() === colName.toLowerCase());

    if (!target) {
      throw new Error(`Namespace not found: ${catalog.name}.${colName}`);
    }

    if (op === 'countdocuments') {
      return {
        queryId: `q-${Date.now()}`,
        sql: command,
        connectionId,
        database: catalog.name,
        executionTimeMs: Math.round((performance.now() - startTime) * 10) / 10,
        rowCount: 1,
        columns: ['count'],
        rows: [{ count: target.rowCount }],
        timestamp: new Date().toLocaleTimeString(),
      };
    }

    // Default find()
    const rows = [...target.rows];
    const cols = target.columns.map(c => c.name);

    return {
      queryId: `q-${Date.now()}`,
      sql: command,
      connectionId,
      database: catalog.name,
      executionTimeMs: Math.round((performance.now() - startTime) * 10) / 10,
      rowCount: rows.length,
      columns: cols,
      rows,
      timestamp: new Date().toLocaleTimeString(),
    };
  }

  private static executeSql(
    sql: string, 
    connectionId: string, 
    catalog: DatabaseCatalog, 
    startTime: number
  ): QueryResult {
    const allTables = catalog.schemas.flatMap(s => s.tables);

    // Show tables / schemas commands
    if (/^SHOW\s+TABLES/i.test(sql)) {
      return {
        queryId: `q-${Date.now()}`,
        sql,
        connectionId,
        database: catalog.name,
        executionTimeMs: 1.2,
        rowCount: allTables.length,
        columns: ['table_schema', 'table_name', 'table_type', 'engine', 'row_count'],
        rows: allTables.map(t => ({
          table_schema: t.schema,
          table_name: t.name,
          table_type: t.type,
          engine: t.engine || 'default',
          row_count: t.rowCount,
        })),
        timestamp: new Date().toLocaleTimeString(),
      };
    }

    if (/^SHOW\s+SCHEMAS/i.test(sql) || /^SHOW\s+DATABASES/i.test(sql)) {
      return {
        queryId: `q-${Date.now()}`,
        sql,
        connectionId,
        database: catalog.name,
        executionTimeMs: 0.8,
        rowCount: catalog.schemas.length,
        columns: ['schema_name', 'table_count'],
        rows: catalog.schemas.map(s => ({
          schema_name: s.name,
          table_count: s.tables.length,
        })),
        timestamp: new Date().toLocaleTimeString(),
      };
    }

    // Identify target table(s) from FROM clause
    const fromMatch = sql.match(/FROM\s+([a-zA-Z0-9_\."]+)/i);
    let targetTable = allTables[0];

    if (fromMatch) {
      const rawName = fromMatch[1].replace(/["']/g, '');
      const parts = rawName.split('.');
      const tableNameOnly = parts[parts.length - 1];

      const found = allTables.find(t => 
        t.name.toLowerCase() === tableNameOnly.toLowerCase() ||
        `${t.schema}.${t.name}`.toLowerCase() === rawName.toLowerCase()
      );
      if (found) targetTable = found;
    }

    // Default simulation of query response based on targetTable
    let resultRows = [...targetTable.rows];
    let columns = targetTable.columns.map(c => c.name);

    // Check if query selects specific columns or aggregates
    const selectMatch = sql.match(/SELECT\s+(.*?)\s+FROM/is);
    if (selectMatch) {
      const selectExpr = selectMatch[1].trim();

      if (selectExpr.includes('COUNT(*)') || selectExpr.includes('count()')) {
        return {
          queryId: `q-${Date.now()}`,
          sql,
          connectionId,
          database: catalog.name,
          executionTimeMs: Math.round((performance.now() - startTime) * 10) / 10,
          rowCount: 1,
          columns: ['total_count'],
          rows: [{ total_count: targetTable.rowCount }],
          timestamp: new Date().toLocaleTimeString(),
        };
      }

      // Check if JOIN with orders and users is being requested
      if (/JOIN/i.test(sql) && /users/i.test(sql) && /orders/i.test(sql)) {
        const usersTable = allTables.find(t => t.name === 'users');
        const ordersTable = allTables.find(t => t.name === 'orders');
        
        if (usersTable && ordersTable) {
          columns = ['id', 'username', 'email', 'role', 'balance_usd', 'total_orders', 'lifetime_value'];
          resultRows = usersTable.rows.map(u => {
            const userOrders = ordersTable.rows.filter(o => o.user_id === u.id);
            const totalSpent = userOrders.reduce((sum, o) => sum + (o.total_amount || 0), 0);
            return {
              id: u.id,
              username: u.username,
              email: u.email,
              role: u.role,
              balance_usd: u.balance_usd,
              total_orders: userOrders.length,
              lifetime_value: Math.round(totalSpent * 100) / 100,
            };
          });
        }
      }
    }

    // Check WHERE filters
    if (/WHERE\s+is_active\s*=\s*true/i.test(sql)) {
      resultRows = resultRows.filter(r => r.is_active === true || r.is_active === undefined);
    }
    if (/WHERE\s+status\s*=\s*'COMPLETED'/i.test(sql)) {
      resultRows = resultRows.filter(r => r.status === 'COMPLETED');
    }

    // Check LIMIT clause
    const limitMatch = sql.match(/LIMIT\s+(\d+)/i);
    if (limitMatch) {
      const limit = parseInt(limitMatch[1], 10);
      resultRows = resultRows.slice(0, limit);
    }

    const elapsed = Math.round((performance.now() - startTime) * 10) / 10;

    return {
      queryId: `q-${Date.now()}`,
      sql,
      connectionId,
      database: catalog.name,
      executionTimeMs: elapsed || 2.4,
      rowCount: resultRows.length,
      columns,
      rows: resultRows,
      timestamp: new Date().toLocaleTimeString(),
    };
  }

  /**
   * Data Export Formatter
   */
  static formatExport(
    columns: string[], 
    rows: Record<string, any>[], 
    options: ExportOptions
  ): string {
    const { format, delimiter, includeHeaders, tableName, quoteStrings } = options;

    if (format === 'JSON') {
      return JSON.stringify(rows, null, 2);
    }

    if (format === 'CSV' || format === 'TSV') {
      const sep = format === 'TSV' ? '\t' : delimiter;
      const lines: string[] = [];

      if (includeHeaders) {
        lines.push(columns.join(sep));
      }

      for (const row of rows) {
        const line = columns.map(col => {
          let val = row[col];
          if (val === null || val === undefined) return '';
          if (typeof val === 'object') val = JSON.stringify(val);
          val = String(val);

          if (quoteStrings || val.includes(sep) || val.includes('"') || val.includes('\n')) {
            val = `"${val.replace(/"/g, '""')}"`;
          }
          return val;
        }).join(sep);

        lines.push(line);
      }
      return lines.join('\n');
    }

    if (format === 'SQL') {
      const lines: string[] = [];
      const tbl = tableName || 'exported_table';

      lines.push(`-- Exported ${rows.length} rows from table ${tbl}`);
      lines.push(`-- Generated by DBeaver Web on ${new Date().toISOString()}`);
      lines.push('');

      for (const row of rows) {
        const vals = columns.map(col => {
          const val = row[col];
          if (val === null || val === undefined) return 'NULL';
          if (typeof val === 'number') return val;
          if (typeof val === 'boolean') return val ? 'TRUE' : 'FALSE';
          if (typeof val === 'object') return `'${JSON.stringify(val).replace(/'/g, "''")}'`;
          return `'${String(val).replace(/'/g, "''")}'`;
        }).join(', ');

        lines.push(`INSERT INTO "${tbl}" ("${columns.join('", "')}") VALUES (${vals});`);
      }
      return lines.join('\n');
    }

    if (format === 'MARKDOWN') {
      const headerLine = `| ${columns.join(' | ')} |`;
      const sepLine = `| ${columns.map(() => '---').join(' | ')} |`;
      const rowLines = rows.map(r => {
        return `| ${columns.map(c => {
          const v = r[c];
          if (typeof v === 'object' && v !== null) return JSON.stringify(v);
          return v ?? '';
        }).join(' | ')} |`;
      });
      return [headerLine, sepLine, ...rowLines].join('\n');
    }

    if (format === 'HTML') {
      let html = `<table border="1" cellpadding="6" cellspacing="0" style="border-collapse: collapse; font-family: sans-serif;">\n`;
      if (includeHeaders) {
        html += `  <thead>\n    <tr style="background-color: #f3f4f6;">\n`;
        for (const col of columns) {
          html += `      <th>${col}</th>\n`;
        }
        html += `    </tr>\n  </thead>\n`;
      }
      html += `  <tbody>\n`;
      for (const row of rows) {
        html += `    <tr>\n`;
        for (const col of columns) {
          const val = row[col];
          html += `      <td>${typeof val === 'object' && val !== null ? JSON.stringify(val) : (val ?? '')}</td>\n`;
        }
        html += `    </tr>\n`;
      }
      html += `  </tbody>\n</table>`;
      return html;
    }

    return '';
  }

  /**
   * Triggers client-side browser file download
   */
  static downloadFile(content: string, filename: string, mimeType: string): void {
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }
}
