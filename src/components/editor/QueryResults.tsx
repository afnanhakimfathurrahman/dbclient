import React, { useState } from 'react';
import { 
  Grid3X3, 
  FileText, 
  GitFork, 
  Download, 
  Clock, 
  CheckCircle2, 
  AlertCircle, 
  Search,
  Maximize2
} from 'lucide-react';
import { QueryResult, QueryPlanNode } from '../../types/db';
import { ExportModal } from '../export/ExportModal';

interface QueryResultsProps {
  result: QueryResult | null;
  isRunning: boolean;
}

export const QueryResults: React.FC<QueryResultsProps> = ({
  result,
  isRunning,
}) => {
  const [activeTab, setActiveTab] = useState<'grid' | 'text' | 'plan'>('grid');
  const [search, setSearch] = useState('');
  const [showExport, setShowExport] = useState(false);
  const [selectedCell, setSelectedCell] = useState<{ col: string; val: any } | null>(null);

  if (isRunning) {
    return (
      <div className="h-full flex flex-col items-center justify-center p-8 bg-slate-950 text-slate-400 gap-3">
        <span className="w-6 h-6 border-2 border-sky-400 border-t-transparent rounded-full animate-spin" />
        <span className="text-xs font-mono">Executing query statement on database engine...</span>
      </div>
    );
  }

  if (!result) {
    return (
      <div className="h-full flex flex-col items-center justify-center p-8 bg-slate-950 text-slate-500 gap-2">
        <Grid3X3 className="w-8 h-8 text-slate-700" />
        <div className="text-xs font-mono">Execute a query (Ctrl+Enter or ▶ Run) to view results</div>
      </div>
    );
  }

  if (result.error) {
    return (
      <div className="h-full p-6 bg-slate-950 overflow-auto">
        <div className="p-4 rounded-xl bg-red-950/40 border border-red-800/80 text-red-300 space-y-2">
          <div className="flex items-center gap-2 font-semibold text-xs">
            <AlertCircle className="w-4 h-4 text-red-400" />
            <span>SQL Execution Error</span>
            <span className="text-[10px] font-mono text-red-400/80">({result.executionTimeMs} ms)</span>
          </div>
          <pre className="p-3 bg-slate-950 rounded-lg text-xs font-mono text-red-200 overflow-x-auto whitespace-pre-wrap">
            {result.error}
          </pre>
          <div className="text-[11px] text-slate-400">
            Check SQL syntax, table names, and ensure the target schema exists on connection {result.connectionId}.
          </div>
        </div>
      </div>
    );
  }

  // Filter rows
  let displayedRows = result.rows;
  if (search) {
    const q = search.toLowerCase();
    displayedRows = displayedRows.filter(r => 
      Object.values(r).some(v => String(v ?? '').toLowerCase().includes(q))
    );
  }

  const renderPlanNode = (node: QueryPlanNode, depth: number = 0) => {
    return (
      <div key={`${node.nodeType}-${depth}`} className="ml-4 border-l border-slate-800 pl-3 my-1.5 font-mono text-xs">
        <div className="flex items-center gap-2 p-1.5 rounded bg-slate-900/80 hover:bg-slate-850 border border-slate-800">
          <GitFork className="w-3.5 h-3.5 text-sky-400 shrink-0" />
          <span className="font-semibold text-slate-200">{node.nodeType}</span>
          {node.relationName && (
            <span className="text-sky-300">
              on {node.relationName} {node.alias ? `as ${node.alias}` : ''}
            </span>
          )}
          {node.totalCost && (
            <span className="text-[10px] px-1.5 py-0.2 rounded bg-slate-800 text-slate-400 ml-auto">
              cost: {node.startupCost}..{node.totalCost}
            </span>
          )}
          {node.actualTotalTime !== undefined && (
            <span className="text-[10px] px-1.5 py-0.2 rounded bg-emerald-950 text-emerald-300 border border-emerald-800">
              time: {node.actualTotalTime} ms
            </span>
          )}
        </div>
        {node.filter && (
          <div className="text-[10px] text-amber-300/90 ml-6 mt-0.5">
            Filter: {node.filter}
          </div>
        )}
        {node.condition && (
          <div className="text-[10px] text-sky-400/90 ml-6 mt-0.5">
            Cond: {node.condition}
          </div>
        )}
        {node.plans && node.plans.map(sub => renderPlanNode(sub, depth + 1))}
      </div>
    );
  };

  return (
    <div className="h-full flex flex-col bg-slate-950 overflow-hidden">
      {/* Top Results Navigation */}
      <div className="px-4 py-2 bg-slate-900/90 border-b border-slate-800 flex items-center justify-between gap-4 text-xs">
        {/* Tabs */}
        <div className="flex items-center gap-1">
          <button
            onClick={() => setActiveTab('grid')}
            className={`flex items-center gap-1.5 px-3 py-1 rounded-lg font-medium transition ${
              activeTab === 'grid'
                ? 'bg-sky-600 text-white shadow-xs'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
            }`}
          >
            <Grid3X3 className="w-3.5 h-3.5" />
            <span>Data Grid</span>
            <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-slate-900/80 text-slate-300 font-mono">
              {result.rowCount}
            </span>
          </button>

          <button
            onClick={() => setActiveTab('text')}
            className={`flex items-center gap-1.5 px-3 py-1 rounded-lg font-medium transition ${
              activeTab === 'text'
                ? 'bg-sky-600 text-white shadow-xs'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
            }`}
          >
            <FileText className="w-3.5 h-3.5" />
            <span>Text / JSON</span>
          </button>

          {result.executionPlan && (
            <button
              onClick={() => setActiveTab('plan')}
              className={`flex items-center gap-1.5 px-3 py-1 rounded-lg font-medium transition ${
                activeTab === 'plan'
                  ? 'bg-sky-600 text-white shadow-xs'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <GitFork className="w-3.5 h-3.5" />
              <span>Execution Plan</span>
            </button>
          )}
        </div>

        {/* Stats & Search */}
        <div className="flex items-center gap-3">
          {activeTab === 'grid' && (
            <div className="relative w-44">
              <Search className="w-3 h-3 absolute left-2 top-2 text-slate-500" />
              <input
                type="text"
                placeholder="Filter results..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full bg-slate-950 border border-slate-700 rounded pl-7 pr-2 py-0.5 text-[11px] text-white placeholder-slate-500 focus:outline-none focus:border-sky-500"
              />
            </div>
          )}

          <div className="flex items-center gap-2 text-[11px] font-mono text-slate-400">
            <span className="flex items-center gap-1 text-emerald-400 font-medium">
              <CheckCircle2 className="w-3 h-3" />
              <span>OK</span>
            </span>
            <span>•</span>
            <span className="flex items-center gap-1">
              <Clock className="w-3 h-3 text-slate-500" />
              <span>{result.executionTimeMs} ms</span>
            </span>
            <span>•</span>
            <span>{result.rowCount} rows</span>
          </div>

          <button
            onClick={() => setShowExport(true)}
            className="flex items-center gap-1 px-2.5 py-1 rounded bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 font-medium text-[11px] transition"
          >
            <Download className="w-3 h-3 text-sky-400" />
            <span>Export</span>
          </button>
        </div>
      </div>

      {/* Tab Panels */}
      <div className="flex-1 overflow-auto">
        {/* GRID TAB */}
        {activeTab === 'grid' && (
          <table className="w-full text-left text-xs border-collapse">
            <thead className="bg-slate-900 sticky top-0 z-10 border-b border-slate-800 text-slate-400 font-mono text-[11px]">
              <tr>
                <th className="w-10 px-3 py-2 text-center border-r border-slate-800 text-slate-400 font-normal">#</th>
                {result.columns.map(col => (
                  <th key={col} className="px-3 py-2 border-r border-slate-800 font-semibold text-slate-200">
                    {col}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 font-mono text-[11px]">
              {displayedRows.length === 0 ? (
                <tr>
                  <td colSpan={result.columns.length + 1} className="p-8 text-center text-slate-500 font-sans">
                    Query returned zero rows.
                  </td>
                </tr>
              ) : (
                displayedRows.map((row, idx) => (
                  <tr key={idx} className="hover:bg-slate-850 transition">
                    <td className="px-3 py-1.5 text-center text-slate-400 border-r border-slate-800 text-[10px] select-none">
                      {idx + 1}
                    </td>
                    {result.columns.map(col => {
                      const val = row[col];
                      const isNull = val === null || val === undefined;
                      const isObject = typeof val === 'object' && !isNull;

                      return (
                        <td
                          key={col}
                          onDoubleClick={() => setSelectedCell({ col, val })}
                          className="px-3 py-1.5 border-r border-slate-800/50 truncate max-w-sm text-slate-300"
                        >
                          {isNull ? (
                            <span className="text-slate-400 italic">NULL</span>
                          ) : isObject ? (
                            <span className="text-amber-400/90 underline cursor-pointer">
                              {JSON.stringify(val)}
                            </span>
                          ) : typeof val === 'boolean' ? (
                            <span className={val ? 'text-emerald-400' : 'text-red-400'}>
                              {val ? 'TRUE' : 'FALSE'}
                            </span>
                          ) : (
                            String(val)
                          )}
                        </td>
                      );
                    })}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        )}

        {/* TEXT / JSON TAB */}
        {activeTab === 'text' && (
          <div className="p-4">
            <pre className="p-4 rounded-xl bg-slate-900 border border-slate-800 font-mono text-xs text-slate-200 overflow-auto whitespace-pre leading-relaxed select-text">
              {JSON.stringify(result.rows, null, 2)}
            </pre>
          </div>
        )}

        {/* EXECUTION PLAN TAB */}
        {activeTab === 'plan' && result.executionPlan && (
          <div className="p-6 space-y-4">
            <div className="text-xs font-semibold text-slate-300 flex items-center gap-2">
              <GitFork className="w-4 h-4 text-sky-400" />
              <span>Visual Execution Tree & Cost Breakdown</span>
            </div>
            {renderPlanNode(result.executionPlan)}
          </div>
        )}
      </div>

      {/* Export Modal */}
      {showExport && (
        <ExportModal
          isOpen={showExport}
          onClose={() => setShowExport(false)}
          tableName="query_results"
          columns={result.columns}
          rows={result.rows}
        />
      )}

      {/* Cell Value Modal */}
      {selectedCell && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-xs p-4">
          <div className="w-full max-w-md bg-slate-900 border border-slate-700 rounded-xl p-5 shadow-2xl flex flex-col max-h-[80vh]">
            <div className="flex items-center justify-between pb-3 border-b border-slate-800">
              <span className="text-xs font-semibold text-slate-200 flex items-center gap-1.5">
                <Maximize2 className="w-3.5 h-3.5 text-sky-400" />
                Value: <code className="text-sky-300 font-mono">{selectedCell.col}</code>
              </span>
              <button
                onClick={() => setSelectedCell(null)}
                className="text-slate-400 hover:text-white text-xs"
              >
                Close
              </button>
            </div>
            <pre className="mt-4 p-3 bg-slate-950 rounded-lg text-xs font-mono text-slate-200 overflow-auto flex-1 whitespace-pre-wrap">
              {typeof selectedCell.val === 'object'
                ? JSON.stringify(selectedCell.val, null, 2)
                : String(selectedCell.val ?? 'NULL')}
            </pre>
          </div>
        </div>
      )}
    </div>
  );
};
