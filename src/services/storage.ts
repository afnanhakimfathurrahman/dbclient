import { ConnectionConfig, DriverInfo, DatabaseCatalog, QueryHistoryItem, EditorTab } from '../types/db';
import { INITIAL_CONNECTIONS, INITIAL_DRIVERS, INITIAL_CATALOGS } from './sampleData';

const STORAGE_KEYS = {
  CONNECTIONS: 'dbeaver_connections_v1',
  DRIVERS: 'dbeaver_drivers_v1',
  CATALOGS: 'dbeaver_catalogs_v1',
  QUERY_HISTORY: 'dbeaver_history_v1',
  TABS: 'dbeaver_tabs_v1',
  ACTIVE_TAB_ID: 'dbeaver_active_tab_id_v1',
  ACTIVE_CONN_ID: 'dbeaver_active_conn_id_v1',
};

export const StorageService = {
  getConnections(): ConnectionConfig[] {
    try {
      const data = localStorage.getItem(STORAGE_KEYS.CONNECTIONS);
      if (data) return JSON.parse(data);
    } catch (e) {
      console.error('Failed to parse connections from storage', e);
    }
    return INITIAL_CONNECTIONS;
  },

  saveConnections(connections: ConnectionConfig[]): void {
    try {
      localStorage.setItem(STORAGE_KEYS.CONNECTIONS, JSON.stringify(connections));
    } catch (e) {
      console.error('Failed to save connections', e);
    }
  },

  getDrivers(): DriverInfo[] {
    try {
      const data = localStorage.getItem(STORAGE_KEYS.DRIVERS);
      if (data) return JSON.parse(data);
    } catch (e) {
      console.error('Failed to parse drivers from storage', e);
    }
    return INITIAL_DRIVERS;
  },

  saveDrivers(drivers: DriverInfo[]): void {
    try {
      localStorage.setItem(STORAGE_KEYS.DRIVERS, JSON.stringify(drivers));
    } catch (e) {
      console.error('Failed to save drivers', e);
    }
  },

  getCatalogs(): Record<string, DatabaseCatalog> {
    try {
      const data = localStorage.getItem(STORAGE_KEYS.CATALOGS);
      if (data) return JSON.parse(data);
    } catch (e) {
      console.error('Failed to parse catalogs from storage', e);
    }
    return INITIAL_CATALOGS;
  },

  saveCatalogs(catalogs: Record<string, DatabaseCatalog>): void {
    try {
      localStorage.setItem(STORAGE_KEYS.CATALOGS, JSON.stringify(catalogs));
    } catch (e) {
      console.error('Failed to save catalogs', e);
    }
  },

  getQueryHistory(): QueryHistoryItem[] {
    try {
      const data = localStorage.getItem(STORAGE_KEYS.QUERY_HISTORY);
      if (data) return JSON.parse(data);
    } catch (e) {
      console.error('Failed to parse query history', e);
    }
    return [
      {
        id: 'hist-1',
        connectionId: 'conn-pg-prod',
        connectionName: 'PostgreSQL 16 - Production OLTP',
        sql: 'SELECT u.id, u.username, u.email, COUNT(o.id) AS total_orders, COALESCE(SUM(o.total_amount), 0) AS total_spent\nFROM public.users u\nLEFT JOIN public.orders o ON u.id = o.user_id\nGROUP BY u.id, u.username, u.email\nORDER BY total_spent DESC;',
        executionTimeMs: 14.8,
        rowCount: 8,
        status: 'SUCCESS',
        timestamp: 'Today, 11:24 AM',
      },
      {
        id: 'hist-2',
        connectionId: 'conn-clickhouse-olap',
        connectionName: 'ClickHouse 24.3 - BigData Events Warehouse',
        sql: 'SELECT country_code, device_type, count() AS pageviews, avg(duration_ms) AS avg_latency\nFROM analytics_warehouse.pageviews_mergetree\nWHERE event_date >= \'2024-11-01\'\nGROUP BY country_code, device_type\nORDER BY pageviews DESC;',
        executionTimeMs: 4.2,
        rowCount: 6,
        status: 'SUCCESS',
        timestamp: 'Today, 10:45 AM',
      },
    ];
  },

  addQueryHistory(item: QueryHistoryItem): void {
    try {
      const history = this.getQueryHistory();
      const updated = [item, ...history.slice(0, 49)];
      localStorage.setItem(STORAGE_KEYS.QUERY_HISTORY, JSON.stringify(updated));
    } catch (e) {
      console.error('Failed to add query history', e);
    }
  },

  clearQueryHistory(): void {
    localStorage.removeItem(STORAGE_KEYS.QUERY_HISTORY);
  },

  getSavedTabs(): EditorTab[] {
    try {
      const data = localStorage.getItem(STORAGE_KEYS.TABS);
      if (data) return JSON.parse(data);
    } catch (e) {
      console.error('Failed to parse editor tabs', e);
    }
    return [
      {
        id: 'tab-sql-1',
        title: 'Script-1.sql',
        type: 'SQL',
        connectionId: 'conn-pg-prod',
        content: `-- PostgreSQL Query Console: public.users & orders
SELECT 
    u.id, 
    u.username, 
    u.email, 
    u.role,
    u.balance_usd,
    COUNT(o.id) AS total_orders,
    COALESCE(SUM(o.total_amount), 0) AS lifetime_value
FROM public.users u
LEFT JOIN public.orders o ON u.id = o.user_id
WHERE u.is_active = true
GROUP BY u.id, u.username, u.email, u.role, u.balance_usd
ORDER BY lifetime_value DESC;`,
      },
    ];
  },

  saveTabs(tabs: EditorTab[]): void {
    try {
      localStorage.setItem(STORAGE_KEYS.TABS, JSON.stringify(tabs));
    } catch (e) {
      console.error('Failed to save editor tabs', e);
    }
  },

  getActiveTabId(): string {
    return localStorage.getItem(STORAGE_KEYS.ACTIVE_TAB_ID) || 'tab-sql-1';
  },

  saveActiveTabId(id: string): void {
    localStorage.setItem(STORAGE_KEYS.ACTIVE_TAB_ID, id);
  },

  getActiveConnectionId(): string {
    return localStorage.getItem(STORAGE_KEYS.ACTIVE_CONN_ID) || 'conn-pg-prod';
  },

  saveActiveConnectionId(id: string): void {
    localStorage.setItem(STORAGE_KEYS.ACTIVE_CONN_ID, id);
  },
};
