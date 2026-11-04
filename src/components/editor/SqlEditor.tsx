import React, { useState, useRef, useEffect } from 'react';
import { 
  Play, 
  GitFork, 
  Trash2, 
  AlignLeft, 
  Plus, 
  X, 
  Sparkles, 
  Save, 
  ChevronDown
} from 'lucide-react';
import { EditorTab, ConnectionConfig, DatabaseCatalog, QueryResult, QueryHistoryItem } from '../../types/db';
import { QueryEngine } from '../../services/queryEngine';
import { QueryResults } from './QueryResults';

interface SqlEditorProps {
  tabs: EditorTab[];
  activeTabId: string;
  onSelectTab: (tabId: string) => void;
  onCloseTab: (tabId: string) => void;
  onNewTab: () => void;
  onUpdateTabContent: (tabId: string, content: string) => void;
  activeConnection: ConnectionConfig;
  catalog: DatabaseCatalog;
  onAddHistory: (item: QueryHistoryItem) => void;
}

const SNIPPETS = [
  {
    label: 'PostgreSQL: Users & Lifetime Order Spend',
    engine: 'postgresql',
    sql: `-- Multi-table aggregation with JOIN and COALESCE
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
  {
    label: 'PostgreSQL: Partitioned Ledger Audit',
    engine: 'postgresql',
    sql: `-- Partition Pruning query on payment_transactions
SELECT 
    p.id,
    p.transaction_ref,
    p.amount,
    p.provider,
    p.status,
    p.payment_date
FROM public.payment_transactions p
WHERE p.payment_date >= '2024-10-01'
  AND p.status = 'SUCCEEDED'
ORDER BY p.payment_date DESC;`,
  },
  {
    label: 'ClickHouse: Columnar Latency & Aggregations',
    engine: 'clickhouse',
    sql: `-- ClickHouse high-throughput analytical query
SELECT 
    country_code,
    device_type,
    count() AS total_views,
    round(avg(duration_ms), 2) AS avg_duration_ms,
    countIf(http_status = 200) AS successful_hits
FROM analytics_warehouse.pageviews_mergetree
WHERE event_date >= '2024-11-01'
GROUP BY country_code, device_type
ORDER BY total_views DESC;`,
  },
  {
    label: 'MongoDB: db.customers.find()',
    engine: 'mongodb',
    sql: `// Query active customers with high loyalty points
db.customers.find({
  loyaltyPoints: { $gt: 500 }
});`,
  },
  {
    label: 'MongoDB: Collection Document Counts',
    engine: 'mongodb',
    sql: `// Inspect total documents in collection
db.customers.countDocuments();`,
  },
  {
    label: 'EXPLAIN ANALYZE Cost Plan',
    engine: 'any',
    sql: `EXPLAIN ANALYZE
SELECT u.username, o.order_number, o.total_amount
FROM public.users u
JOIN public.orders o ON u.id = o.user_id
WHERE o.status = 'COMPLETED';`,
  },
];

export const SqlEditor: React.FC<SqlEditorProps> = ({
  tabs,
  activeTabId,
  onSelectTab,
  onCloseTab,
  onNewTab,
  onUpdateTabContent,
  activeConnection,
  catalog,
  onAddHistory,
}) => {
  const activeTab = tabs.find(t => t.id === activeTabId) || tabs[0];
  const [isRunning, setIsRunning] = useState(false);
  const [queryResult, setQueryResult] = useState<QueryResult | null>(null);
  const [showSnippets, setShowSnippets] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Line numbers calculation
  const lines = (activeTab?.content || '').split('\n');
  const lineCount = Math.max(lines.length, 12);

  const handleExecute = (overrideSql?: string) => {
    const textToRun = overrideSql || activeTab?.content || '';
    if (!textToRun.trim()) return;

    setIsRunning(true);
    setTimeout(() => {
      const res = QueryEngine.execute(textToRun, activeConnection.id, catalog, activeConnection.engine);
      setQueryResult(res);
      setIsRunning(false);

      onAddHistory({
        id: `hist-${Date.now()}`,
        connectionId: activeConnection.id,
        connectionName: activeConnection.name,
        sql: textToRun,
        executionTimeMs: res.executionTimeMs,
        rowCount: res.rowCount,
        status: res.error ? 'ERROR' : 'SUCCESS',
        errorMessage: res.error,
        timestamp: new Date().toLocaleTimeString(),
      });
    }, 120);
  };

  const handleExplain = () => {
    const textToRun = activeTab?.content || '';
    if (!textToRun.trim()) return;
    const explainQuery = textToRun.trim().toUpperCase().startsWith('EXPLAIN') 
      ? textToRun 
      : `EXPLAIN ${textToRun}`;
    handleExecute(explainQuery);
  };

  const handleFormat = () => {
    const content = activeTab?.content || '';
    if (!content) return;

    // Clean formatting for SQL keywords
    const keywords = ['SELECT', 'FROM', 'WHERE', 'JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'INNER JOIN', 'GROUP BY', 'ORDER BY', 'HAVING', 'LIMIT', 'INSERT INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE FROM'];
    let formatted = content;
    keywords.forEach(kw => {
      const regex = new RegExp(`\\b${kw}\\b`, 'gi');
      formatted = formatted.replace(regex, kw);
    });

    onUpdateTabContent(activeTab.id, formatted);
  };

  // Shortcut Ctrl+Enter / Cmd+Enter
  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault();
      handleExecute();
    }
  };

  return (
    <div className="h-full flex flex-col bg-slate-950 overflow-hidden">
      {/* Script Tabs Bar */}
      <div className="flex items-center justify-between px-3 pt-1.5 bg-slate-900 border-b border-slate-800 select-none">
        <div className="flex items-center gap-1 overflow-x-auto max-w-2xl">
          {tabs.map(tab => {
            const isActive = tab.id === activeTabId;
            return (
              <div
                key={tab.id}
                onClick={() => onSelectTab(tab.id)}
                className={`flex items-center gap-2 px-3 py-1.5 rounded-t-lg border-t border-x cursor-pointer text-xs transition ${
                  isActive
                    ? 'bg-slate-950 border-slate-700/80 text-sky-400 font-semibold'
                    : 'bg-slate-900/60 border-transparent text-slate-400 hover:text-slate-200 hover:bg-slate-800'
                }`}
              >
                <span className="font-mono">{tab.title}</span>
                {tabs.length > 1 && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onCloseTab(tab.id);
                    }}
                    className="p-0.5 rounded text-slate-500 hover:text-white hover:bg-slate-700/60"
                  >
                    <X className="w-3 h-3" />
                  </button>
                )}
              </div>
            );
          })}

          <button
            onClick={onNewTab}
            className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-800 ml-1 transition"
            title="Open new SQL Script Tab"
          >
            <Plus className="w-4 h-4" />
          </button>
        </div>

        {/* Active DB Info */}
        <div className="flex items-center gap-2 pb-1 text-[11px] text-slate-400 font-mono">
          <span className="w-2 h-2 rounded-full" style={{ backgroundColor: activeConnection.colorTag || '#3b82f6' }} />
          <span className="text-slate-200 font-medium truncate max-w-xs">{activeConnection.name}</span>
          <span className="text-slate-500">({catalog.name})</span>
        </div>
      </div>

      {/* Editor Action Toolbar */}
      <div className="px-4 py-2 bg-slate-900/70 border-b border-slate-800 flex items-center justify-between gap-3 text-xs">
        <div className="flex items-center gap-2">
          {/* Run Button */}
          <button
            onClick={() => handleExecute()}
            disabled={isRunning}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-semibold text-xs shadow-xs transition active:scale-95"
            title="Execute SQL Query (Ctrl + Enter)"
          >
            <Play className="w-3.5 h-3.5 fill-current" />
            <span>Execute</span>
            <span className="text-[10px] bg-emerald-800/80 px-1 py-0.2 rounded text-emerald-200 font-mono ml-0.5">
              ⌘↵
            </span>
          </button>

          {/* Explain Plan Button */}
          <button
            onClick={handleExplain}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-sky-300 border border-slate-700 font-medium transition"
            title="Generate Query Execution Plan (Cost, Index Scans, Joins)"
          >
            <GitFork className="w-3.5 h-3.5" />
            <span>Explain Plan</span>
          </button>

          {/* Format SQL */}
          <button
            onClick={handleFormat}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 font-medium transition"
            title="Format and align SQL syntax keywords"
          >
            <AlignLeft className="w-3.5 h-3.5" />
            <span>Format</span>
          </button>

          {/* Clear Button */}
          <button
            onClick={() => onUpdateTabContent(activeTab.id, '')}
            className="p-1.5 rounded text-slate-400 hover:text-white hover:bg-slate-800 transition"
            title="Clear Editor"
          >
            <Trash2 className="w-3.5 h-3.5" />
          </button>
        </div>

        {/* Snippets / Templates Dropdown */}
        <div className="relative">
          <button
            onClick={() => setShowSnippets(!showSnippets)}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-slate-800/90 hover:bg-slate-700 text-amber-300 border border-slate-700/80 font-medium text-xs transition"
          >
            <Sparkles className="w-3.5 h-3.5 text-amber-400" />
            <span>SQL Snippets</span>
            <ChevronDown className="w-3 h-3 text-slate-400" />
          </button>

          {showSnippets && (
            <div className="absolute right-0 mt-1 w-80 rounded-xl bg-slate-900 border border-slate-700 shadow-2xl p-2 z-50 space-y-1">
              <div className="px-2 py-1 text-[10px] font-semibold text-slate-400 uppercase tracking-wider">
                Pre-built Query Templates
              </div>
              {SNIPPETS.map((snippet, idx) => (
                <button
                  key={idx}
                  onClick={() => {
                    onUpdateTabContent(activeTab.id, snippet.sql);
                    setShowSnippets(false);
                  }}
                  className="w-full text-left p-2 rounded-lg hover:bg-slate-800 text-xs text-slate-200 transition flex flex-col"
                >
                  <span className="font-semibold text-slate-100">{snippet.label}</span>
                  <span className="text-[10px] text-slate-400 font-mono truncate mt-0.5">
                    {snippet.sql.split('\n')[1] || snippet.sql.split('\n')[0]}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Editor Workspace (Split Pane: Code Area on Top, Results on Bottom) */}
      <div className="flex-1 flex flex-col min-h-0">
        {/* Code Input Area with Line Numbers */}
        <div className="h-2/5 min-h-[160px] flex bg-slate-950 border-b border-slate-800 relative overflow-hidden">
          {/* Line Numbers */}
          <div className="w-12 py-3 bg-slate-900/60 border-r border-slate-800/80 text-right pr-3 select-none font-mono text-xs text-slate-400 leading-6 shrink-0">
            {Array.from({ length: lineCount }, (_, i) => (
              <div key={i}>{i + 1}</div>
            ))}
          </div>

          {/* Textarea code editor */}
          <textarea
            ref={textareaRef}
            value={activeTab?.content || ''}
            onChange={(e) => onUpdateTabContent(activeTab.id, e.target.value)}
            onKeyDown={handleKeyDown}
            spellCheck={false}
            placeholder="Type your SQL query statement or NoSQL command here... (e.g. SELECT * FROM public.users;)"
            className="flex-1 p-3 bg-transparent text-slate-100 font-mono text-xs leading-6 outline-none resize-none placeholder-slate-600 selection:bg-sky-700/60"
          />
        </div>

        {/* Results Viewer on Bottom */}
        <div className="flex-1 min-h-[220px] overflow-hidden">
          <QueryResults
            result={queryResult}
            isRunning={isRunning}
          />
        </div>
      </div>
    </div>
  );
};
