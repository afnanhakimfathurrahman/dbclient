import React, { useState } from 'react';
import { History, Play, Search, Trash2, Clock, CheckCircle2, AlertCircle } from 'lucide-react';
import { Modal } from '../common/Modal';
import { QueryHistoryItem } from '../../types/db';

interface QueryHistoryModalProps {
  isOpen: boolean;
  onClose: () => void;
  history: QueryHistoryItem[];
  onSelectQuery: (sql: string) => void;
  onClearHistory: () => void;
}

export const QueryHistoryModal: React.FC<QueryHistoryModalProps> = ({
  isOpen,
  onClose,
  history,
  onSelectQuery,
  onClearHistory,
}) => {
  const [search, setSearch] = useState('');

  const filtered = history.filter(h => 
    h.sql.toLowerCase().includes(search.toLowerCase()) ||
    h.connectionName.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      maxWidth="max-w-3xl"
      title={
        <div className="flex items-center gap-2">
          <History className="w-4 h-4 text-sky-400" />
          <span>SQL Execution History</span>
          <span className="text-[11px] px-2 py-0.5 rounded bg-slate-800 text-slate-300">
            {history.length} recorded
          </span>
        </div>
      }
      footer={
        <div className="flex items-center justify-between w-full">
          <button
            type="button"
            onClick={onClearHistory}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-slate-400 hover:text-red-400 hover:bg-red-950/20 text-xs transition"
          >
            <Trash2 className="w-3.5 h-3.5" />
            <span>Clear History</span>
          </button>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-medium"
          >
            Close
          </button>
        </div>
      }
    >
      <div className="space-y-3">
        {/* Search */}
        <div className="relative">
          <Search className="w-3.5 h-3.5 absolute left-3 top-2.5 text-slate-400" />
          <input
            type="text"
            placeholder="Search query history..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full bg-slate-950 border border-slate-700 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-sky-500"
          />
        </div>

        {/* History list */}
        <div className="space-y-2 max-h-[55vh] overflow-y-auto pr-1">
          {filtered.length === 0 ? (
            <div className="p-8 text-center text-slate-500 text-xs">
              No query history found matching your search.
            </div>
          ) : (
            filtered.map(item => (
              <div
                key={item.id}
                className="p-3 rounded-xl bg-slate-950/80 border border-slate-800/80 hover:border-slate-700 transition flex flex-col gap-2"
              >
                <div className="flex items-center justify-between gap-2 text-[11px]">
                  <div className="flex items-center gap-2">
                    {item.status === 'SUCCESS' ? (
                      <span className="flex items-center gap-1 text-emerald-400 font-medium">
                        <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
                        SUCCESS
                      </span>
                    ) : (
                      <span className="flex items-center gap-1 text-red-400 font-medium">
                        <AlertCircle className="w-3.5 h-3.5 text-red-400" />
                        FAILED
                      </span>
                    )}
                    <span className="text-slate-500">•</span>
                    <span className="text-slate-300 font-medium">{item.connectionName}</span>
                  </div>

                  <div className="flex items-center gap-3 text-slate-400">
                    <span className="flex items-center gap-1 font-mono">
                      <Clock className="w-3 h-3 text-slate-400" />
                      {item.executionTimeMs} ms
                    </span>
                    <span>{item.rowCount} rows</span>
                    <span className="text-slate-400">{item.timestamp}</span>
                  </div>
                </div>

                <pre className="font-mono text-[11px] text-slate-300 bg-slate-900 p-2.5 rounded-lg overflow-x-auto whitespace-pre-wrap max-h-24">
                  {item.sql}
                </pre>

                <div className="flex justify-end">
                  <button
                    onClick={() => {
                      onSelectQuery(item.sql);
                      onClose();
                    }}
                    className="flex items-center gap-1 px-2.5 py-1 rounded bg-sky-600/90 hover:bg-sky-500 text-white text-[11px] font-medium transition"
                  >
                    <Play className="w-3 h-3" />
                    <span>Load & Run Query</span>
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </Modal>
  );
};
