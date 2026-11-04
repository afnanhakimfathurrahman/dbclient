import React, { useState } from 'react';
import { 
  Table, 
  Layers, 
  Key, 
  Grid3X3, 
  Split, 
  ShieldAlert, 
  Code2, 
  Share2, 
  Search, 
  Plus, 
  Trash2, 
  Download, 
  RefreshCw, 
  Copy, 
  Check, 
  Info,
  Maximize2
} from 'lucide-react';
import { TableMetadata, ColumnDefinition, DatabaseEngine } from '../../types/db';
import { ERDiagram } from './ERDiagram';
import { ExportModal } from '../export/ExportModal';
import { generateDDL } from '../../services/sampleData';

interface TableInspectorProps {
  table: TableMetadata;
  allTables: TableMetadata[];
  engine: DatabaseEngine;
  onUpdateTable: (updated: TableMetadata) => void;
  onSelectTable: (tableName: string) => void;
  initialTab?: 'data' | 'columns' | 'indexes' | 'partitions' | 'constraints' | 'ddl' | 'erd';
}

export const TableInspector: React.FC<TableInspectorProps> = ({
  table,
  allTables,
  engine,
  onUpdateTable,
  onSelectTable,
  initialTab = 'data',
}) => {
  const [activeTab, setActiveTab] = useState<'data' | 'columns' | 'indexes' | 'partitions' | 'constraints' | 'ddl' | 'erd'>(initialTab);
  const [filterText, setFilterText] = useState('');
  const [sortCol, setSortCol] = useState<string | null>(null);
  const [sortAsc, setSortAsc] = useState<boolean>(true);
  const [selectedRowIndex, setSelectedRowIndex] = useState<number | null>(null);
  const [showExportModal, setShowExportModal] = useState<boolean>(false);
  const [copiedDdl, setCopiedDdl] = useState<boolean>(false);

  // New row modal state
  const [isAddingRow, setIsAddingRow] = useState(false);
  const [newRowData, setNewRowData] = useState<Record<string, any>>({});

  // Cell inspector modal (for JSON or long text)
  const [inspectCell, setInspectCell] = useState<{ col: string; val: any } | null>(null);

  const columns = table.columns;
  const colNames = columns.map(c => c.name);

  // Filter & Sort table rows
  let displayedRows = [...table.rows];

  if (filterText) {
    const query = filterText.toLowerCase();
    displayedRows = displayedRows.filter(r => 
      Object.values(r).some(val => 
        String(val ?? '').toLowerCase().includes(query)
      )
    );
  }

  if (sortCol) {
    displayedRows.sort((a, b) => {
      const valA = a[sortCol];
      const valB = b[sortCol];
      if (valA === valB) return 0;
      if (valA === null || valA === undefined) return 1;
      if (valB === null || valB === undefined) return -1;
      if (valA < valB) return sortAsc ? -1 : 1;
      return sortAsc ? 1 : -1;
    });
  }

  const handleSort = (colName: string) => {
    if (sortCol === colName) {
      setSortAsc(!sortAsc);
    } else {
      setSortCol(colName);
      setSortAsc(true);
    }
  };

  const handleDeleteRow = (index: number) => {
    const updatedRows = [...table.rows];
    updatedRows.splice(index, 1);
    onUpdateTable({
      ...table,
      rows: updatedRows,
      rowCount: Math.max(0, table.rowCount - 1),
    });
    setSelectedRowIndex(null);
  };

  const handleSaveNewRow = (e: React.FormEvent) => {
    e.preventDefault();
    const updatedRows = [newRowData, ...table.rows];
    onUpdateTable({
      ...table,
      rows: updatedRows,
      rowCount: table.rowCount + 1,
    });
    setIsAddingRow(false);
    setNewRowData({});
  };

  const fullDdl = table.ddl || generateDDL(table, engine);

  const handleCopyDdl = () => {
    navigator.clipboard.writeText(fullDdl);
    setCopiedDdl(true);
    setTimeout(() => setCopiedDdl(false), 2000);
  };

  const tabs: { id: typeof activeTab; label: string; icon: React.ReactNode; badge?: number }[] = [
    { id: 'data', label: 'Data Grid', icon: <Grid3X3 className="w-3.5 h-3.5" />, badge: table.rows.length },
    { id: 'columns', label: 'Columns', icon: <Layers className="w-3.5 h-3.5" />, badge: table.columns.length },
    { id: 'indexes', label: 'Indexes', icon: <Key className="w-3.5 h-3.5" />, badge: table.indexes.length },
    { id: 'partitions', label: 'Partitions', icon: <Split className="w-3.5 h-3.5" />, badge: table.partitions.length },
    { id: 'constraints', label: 'Constraints', icon: <ShieldAlert className="w-3.5 h-3.5" />, badge: table.constraints.length },
    { id: 'ddl', label: 'DDL / Source', icon: <Code2 className="w-3.5 h-3.5" /> },
    { id: 'erd', label: 'ER Diagram', icon: <Share2 className="w-3.5 h-3.5" /> },
  ];

  return (
    <div className="h-full flex flex-col bg-slate-950 overflow-hidden">
      {/* Top Header Information Bar */}
      <div className="px-4 py-2.5 bg-slate-900 border-b border-slate-800 flex items-center justify-between gap-4">
        <div className="flex items-center gap-2.5">
          <div className="p-1.5 rounded-lg bg-sky-950/80 border border-sky-800/80 text-sky-400">
            <Table className="w-4 h-4" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-mono text-xs text-slate-400">{table.schema}.</span>
              <span className="font-mono font-bold text-sm text-white">{table.name}</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded bg-slate-800 text-slate-300 font-mono">
                {table.engine || 'Table'}
              </span>
            </div>
            {table.comment && (
              <p className="text-[11px] text-slate-400 mt-0.5 line-clamp-1">{table.comment}</p>
            )}
          </div>
        </div>

        {/* Quick Stats & Actions */}
        <div className="flex items-center gap-3">
          <div className="hidden sm:flex items-center gap-3 text-xs text-slate-400 font-mono">
            <span>{table.rowCount.toLocaleString()} Total Rows</span>
            <span>•</span>
            <span>{(table.sizeBytes / 1024 / 1024).toFixed(1)} MB</span>
          </div>

          <button
            onClick={() => setShowExportModal(true)}
            className="flex items-center gap-1.5 px-2.5 py-1 rounded bg-sky-600/90 hover:bg-sky-500 text-white text-xs font-medium transition shadow-xs"
          >
            <Download className="w-3.5 h-3.5" />
            <span>Export Data</span>
          </button>
        </div>
      </div>

      {/* Tabs Header */}
      <div className="flex items-center gap-1 px-4 bg-slate-950 border-b border-slate-800/80 overflow-x-auto text-xs">
        {tabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`flex items-center gap-1.5 px-3 py-2 border-b-2 font-medium whitespace-nowrap transition ${
              activeTab === tab.id
                ? 'border-sky-500 text-sky-400 bg-slate-900/50'
                : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
            }`}
          >
            {tab.icon}
            <span>{tab.label}</span>
            {tab.badge !== undefined && (
              <span className={`text-[10px] px-1.5 py-0.2 rounded-full ${
                activeTab === tab.id ? 'bg-sky-900 text-sky-200' : 'bg-slate-800 text-slate-400'
              }`}>
                {tab.badge}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Tab Contents */}
      <div className="flex-1 overflow-hidden relative">
        {/* TAB 1: DATA GRID */}
        {activeTab === 'data' && (
          <div className="h-full flex flex-col">
            {/* Data Toolbar */}
            <div className="px-4 py-2 bg-slate-900/70 border-b border-slate-800/80 flex items-center justify-between gap-3 text-xs">
              <div className="flex items-center gap-2 flex-1 max-w-sm">
                <div className="relative w-full">
                  <Search className="w-3.5 h-3.5 absolute left-2.5 top-2 text-slate-400" />
                  <input
                    type="text"
                    placeholder="Filter rows in view..."
                    value={filterText}
                    onChange={(e) => setFilterText(e.target.value)}
                    className="w-full bg-slate-950 border border-slate-700 rounded pl-8 pr-2 py-1 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-sky-500"
                  />
                </div>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={() => setIsAddingRow(true)}
                  className="flex items-center gap-1 px-2.5 py-1 rounded bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 font-medium transition"
                >
                  <Plus className="w-3.5 h-3.5 text-emerald-400" />
                  <span>Insert Row</span>
                </button>

                {selectedRowIndex !== null && (
                  <button
                    onClick={() => handleDeleteRow(selectedRowIndex)}
                    className="flex items-center gap-1 px-2.5 py-1 rounded bg-red-950/60 hover:bg-red-900 text-red-300 border border-red-800 font-medium transition"
                  >
                    <Trash2 className="w-3.5 h-3.5 text-red-400" />
                    <span>Delete Row</span>
                  </button>
                )}

                <button
                  onClick={() => { setFilterText(''); setSortCol(null); }}
                  className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-800"
                  title="Reset filters"
                >
                  <RefreshCw className="w-3.5 h-3.5" />
                </button>
              </div>
            </div>

            {/* Table Spreadsheet View */}
            <div className="flex-1 overflow-auto">
              <table className="w-full text-left text-xs border-collapse">
                <thead className="bg-slate-900 sticky top-0 z-10 border-b border-slate-800 text-slate-400 font-mono text-[11px]">
                  <tr>
                    <th className="w-10 px-3 py-2 text-center border-r border-slate-800 text-slate-400 font-normal">#</th>
                    {columns.map(col => (
                      <th
                        key={col.name}
                        onClick={() => handleSort(col.name)}
                        className="px-3 py-2 border-r border-slate-800 cursor-pointer select-none hover:bg-slate-800/80 transition"
                      >
                        <div className="flex items-center justify-between gap-2">
                          <div className="flex items-center gap-1.5 truncate">
                            {col.isPrimaryKey && <Key className="w-3 h-3 text-amber-400 shrink-0" />}
                            <span className="font-semibold text-slate-200">{col.name}</span>
                          </div>
                          <span className="text-[10px] text-slate-400 font-normal shrink-0">
                            {col.type}
                            {sortCol === col.name ? (sortAsc ? ' ▲' : ' ▼') : ''}
                          </span>
                        </div>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/50 font-mono text-[11px]">
                  {displayedRows.length === 0 ? (
                    <tr>
                      <td colSpan={columns.length + 1} className="p-8 text-center text-slate-500 font-sans">
                        No rows found matching current filter.
                      </td>
                    </tr>
                  ) : (
                    displayedRows.map((row, idx) => {
                      const isSelected = selectedRowIndex === idx;
                      return (
                        <tr
                          key={idx}
                          onClick={() => setSelectedRowIndex(isSelected ? null : idx)}
                          className={`hover:bg-slate-800/50 cursor-pointer transition ${
                            isSelected ? 'bg-sky-950/40 text-sky-200' : 'text-slate-300'
                          }`}
                        >
                          <td className="px-3 py-1.5 text-center text-slate-400 border-r border-slate-800/60 text-[10px] select-none">
                            {idx + 1}
                          </td>
                          {columns.map(col => {
                            const val = row[col.name];
                            const isNull = val === null || val === undefined;
                            const isObject = typeof val === 'object' && !isNull;

                            return (
                              <td
                                key={col.name}
                                onDoubleClick={() => setInspectCell({ col: col.name, val })}
                                className="px-3 py-1.5 border-r border-slate-800/50 truncate max-w-xs"
                                title="Double-click to inspect"
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
                                  <span>{String(val)}</span>
                                )}
                              </td>
                            );
                          })}
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>

            {/* Bottom Status bar */}
            <div className="px-4 py-1.5 bg-slate-900 border-t border-slate-800 flex items-center justify-between text-[11px] text-slate-400 font-mono">
              <div>
                Showing {displayedRows.length} of {table.rowCount.toLocaleString()} records
              </div>
              <div>
                {selectedRowIndex !== null ? `Selected Row #${selectedRowIndex + 1}` : 'Ready'}
              </div>
            </div>
          </div>
        )}

        {/* TAB 2: COLUMNS / SCHEMA */}
        {activeTab === 'columns' && (
          <div className="h-full overflow-auto p-4">
            <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-950">
              <table className="w-full text-left text-xs border-collapse">
                <thead className="bg-slate-900 border-b border-slate-800 text-slate-400 font-mono text-[11px]">
                  <tr>
                    <th className="px-4 py-2.5">Name</th>
                    <th className="px-4 py-2.5">Data Type</th>
                    <th className="px-4 py-2.5">Key</th>
                    <th className="px-4 py-2.5">Nullable</th>
                    <th className="px-4 py-2.5">Default Value</th>
                    <th className="px-4 py-2.5">Codec / Compression</th>
                    <th className="px-4 py-2.5">Comment</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 font-mono text-xs">
                  {columns.map(col => (
                    <tr key={col.name} className="hover:bg-slate-900/50">
                      <td className="px-4 py-2.5 font-semibold text-slate-100 flex items-center gap-1.5">
                        {col.isPrimaryKey && <Key className="w-3.5 h-3.5 text-amber-400 shrink-0" />}
                        <span>{col.name}</span>
                      </td>
                      <td className="px-4 py-2.5 text-sky-400">{col.type}</td>
                      <td className="px-4 py-2.5">
                        {col.isPrimaryKey ? (
                          <span className="px-1.5 py-0.5 rounded bg-amber-950 text-amber-300 border border-amber-800 text-[10px] font-bold">
                            PRIMARY KEY
                          </span>
                        ) : col.isForeignKey ? (
                          <span className="px-1.5 py-0.5 rounded bg-sky-950 text-sky-300 border border-sky-800 text-[10px]">
                            FK → {col.foreignKeyRef?.table}
                          </span>
                        ) : (
                          <span className="text-slate-400">-</span>
                        )}
                      </td>
                      <td className="px-4 py-2.5">
                        <span className={col.isNullable ? 'text-slate-400' : 'text-rose-400 font-semibold'}>
                          {col.isNullable ? 'YES' : 'NO'}
                        </span>
                      </td>
                      <td className="px-4 py-2.5 text-slate-400">
                        {col.defaultValue || <span className="text-slate-400 italic">None</span>}
                      </td>
                      <td className="px-4 py-2.5 text-slate-400">
                        {col.codec ? (
                          <span className="px-1.5 py-0.5 rounded bg-purple-950 text-purple-300 border border-purple-800 text-[10px]">
                            {col.codec}
                          </span>
                        ) : (
                          <span className="text-slate-400">-</span>
                        )}
                      </td>
                      <td className="px-4 py-2.5 text-slate-400 font-sans">
                        {col.comment || '-'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* TAB 3: INDEXES */}
        {activeTab === 'indexes' && (
          <div className="h-full overflow-auto p-4 space-y-4">
            <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-950">
              <table className="w-full text-left text-xs border-collapse">
                <thead className="bg-slate-900 border-b border-slate-800 text-slate-400 font-mono text-[11px]">
                  <tr>
                    <th className="px-4 py-2.5">Index Name</th>
                    <th className="px-4 py-2.5">Type / Engine</th>
                    <th className="px-4 py-2.5">Unique</th>
                    <th className="px-4 py-2.5">Columns Indexed</th>
                    <th className="px-4 py-2.5">Disk Size</th>
                    <th className="px-4 py-2.5">Details</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 font-mono text-xs">
                  {table.indexes.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="p-8 text-center text-slate-500 font-sans">
                        No secondary indexes created on this table.
                      </td>
                    </tr>
                  ) : (
                    table.indexes.map(idx => (
                      <tr key={idx.name} className="hover:bg-slate-900/50">
                        <td className="px-4 py-2.5 font-semibold text-slate-200 flex items-center gap-2">
                          <Key className="w-3.5 h-3.5 text-sky-400" />
                          <span>{idx.name}</span>
                        </td>
                        <td className="px-4 py-2.5">
                          <span className="px-2 py-0.5 rounded bg-slate-800 text-sky-300 border border-slate-700 text-[11px]">
                            {idx.type}
                          </span>
                        </td>
                        <td className="px-4 py-2.5">
                          <span className={idx.isUnique ? 'text-amber-400 font-bold' : 'text-slate-400'}>
                            {idx.isUnique ? 'YES (Unique)' : 'NO'}
                          </span>
                        </td>
                        <td className="px-4 py-2.5 text-slate-300">
                          ({idx.columns.join(', ')})
                        </td>
                        <td className="px-4 py-2.5 text-slate-400">
                          {idx.sizeBytes ? `${(idx.sizeBytes / 1024 / 1024).toFixed(2)} MB` : 'Dynamic'}
                        </td>
                        <td className="px-4 py-2.5 text-slate-400 font-sans text-[11px]">
                          {idx.comment || 'Optimized B-Tree index'}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-900/60 border border-slate-800 text-xs text-slate-400 flex items-start gap-2.5">
              <Info className="w-4 h-4 text-sky-400 shrink-0 mt-0.5" />
              <div>
                <span className="font-semibold text-slate-300">DBeaver Index Optimizer:</span> Indexes speed up query execution for <code className="text-sky-300 font-mono">WHERE</code>, <code className="text-sky-300 font-mono">JOIN</code>, and <code className="text-sky-300 font-mono">ORDER BY</code> operations.
              </div>
            </div>
          </div>
        )}

        {/* TAB 4: PARTITIONS */}
        {activeTab === 'partitions' && (
          <div className="h-full overflow-auto p-4 space-y-4">
            {table.partitions.length > 0 ? (
              <>
                <div className="p-3.5 rounded-xl bg-sky-950/30 border border-sky-800/60 text-xs text-slate-300 flex items-start gap-2.5">
                  <Split className="w-4 h-4 text-sky-400 shrink-0 mt-0.5" />
                  <div>
                    <span className="font-semibold text-sky-300">Partitioned Table Configuration:</span>
                    <div className="mt-1 font-mono text-[11px] text-slate-300">
                      Strategy: <strong className="text-sky-400">{table.partitions[0]?.type}</strong> • Expression: <code className="text-amber-300 font-semibold">{table.partitions[0]?.expression}</code>
                    </div>
                  </div>
                </div>

                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-950">
                  <table className="w-full text-left text-xs border-collapse">
                    <thead className="bg-slate-900 border-b border-slate-800 text-slate-400 font-mono text-[11px]">
                      <tr>
                        <th className="px-4 py-2.5">Partition Name</th>
                        <th className="px-4 py-2.5">Partition Type</th>
                        <th className="px-4 py-2.5">Range / Value Bounds</th>
                        <th className="px-4 py-2.5">Row Count</th>
                        <th className="px-4 py-2.5">Storage Size</th>
                        <th className="px-4 py-2.5">Status</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-800/60 font-mono text-xs">
                      {table.partitions.map(part => (
                        <tr key={part.name} className="hover:bg-slate-900/50">
                          <td className="px-4 py-2.5 font-semibold text-slate-200 flex items-center gap-2">
                            <Split className="w-3.5 h-3.5 text-sky-400" />
                            <span>{part.name}</span>
                          </td>
                          <td className="px-4 py-2.5 text-slate-300">{part.type}</td>
                          <td className="px-4 py-2.5 text-amber-300 font-semibold">
                            {part.valuesRange || 'DEFAULT'}
                          </td>
                          <td className="px-4 py-2.5 text-slate-300">
                            {part.rowCount.toLocaleString()} rows
                          </td>
                          <td className="px-4 py-2.5 text-slate-400">
                            {(part.sizeBytes / 1024 / 1024).toFixed(2)} MB
                          </td>
                          <td className="px-4 py-2.5">
                            <span className="px-2 py-0.5 rounded bg-emerald-950 text-emerald-300 border border-emerald-800 text-[10px] font-bold">
                              ACTIVE
                            </span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </>
            ) : (
              <div className="p-8 text-center bg-slate-950 border border-slate-800 rounded-xl space-y-2">
                <Split className="w-8 h-8 text-slate-600 mx-auto" />
                <h4 className="text-sm font-semibold text-slate-300">Not a Partitioned Table</h4>
                <p className="text-xs text-slate-500 max-w-md mx-auto">
                  This table is stored as a single relation. For high-volume tables (e.g. <code className="text-sky-400 font-mono">payment_transactions</code> in PostgreSQL or <code className="text-sky-400 font-mono">pageviews_mergetree</code> in ClickHouse), partition pruning divides data into quarterly or monthly segments.
                </p>
              </div>
            )}
          </div>
        )}

        {/* TAB 5: CONSTRAINTS */}
        {activeTab === 'constraints' && (
          <div className="h-full overflow-auto p-4 space-y-4">
            <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-950">
              <table className="w-full text-left text-xs border-collapse">
                <thead className="bg-slate-900 border-b border-slate-800 text-slate-400 font-mono text-[11px]">
                  <tr>
                    <th className="px-4 py-2.5">Constraint Name</th>
                    <th className="px-4 py-2.5">Type</th>
                    <th className="px-4 py-2.5">Columns</th>
                    <th className="px-4 py-2.5">Referenced Table / Condition</th>
                    <th className="px-4 py-2.5">On Delete / Update</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 font-mono text-xs">
                  {table.constraints.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="p-8 text-center text-slate-500 font-sans">
                        No explicit constraints defined on this table.
                      </td>
                    </tr>
                  ) : (
                    table.constraints.map(c => (
                      <tr key={c.name} className="hover:bg-slate-900/50">
                        <td className="px-4 py-2.5 font-semibold text-slate-200 flex items-center gap-2">
                          <ShieldAlert className="w-3.5 h-3.5 text-sky-400" />
                          <span>{c.name}</span>
                        </td>
                        <td className="px-4 py-2.5">
                          <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                            c.type === 'PRIMARY KEY' 
                              ? 'bg-amber-950 text-amber-300 border border-amber-800' 
                              : c.type === 'FOREIGN KEY'
                                ? 'bg-sky-950 text-sky-300 border border-sky-800'
                                : 'bg-emerald-950 text-emerald-300 border border-emerald-800'
                          }`}>
                            {c.type}
                          </span>
                        </td>
                        <td className="px-4 py-2.5 text-slate-300">
                          ({c.columns.join(', ')})
                        </td>
                        <td className="px-4 py-2.5 text-slate-400">
                          {c.type === 'FOREIGN KEY' ? (
                            <span className="text-sky-400">
                              → {c.referencedTable} ({c.referencedColumns?.join(', ')})
                            </span>
                          ) : c.type === 'CHECK' ? (
                            <code className="text-amber-300 bg-slate-900 px-1 py-0.5 rounded">
                              {c.checkExpression}
                            </code>
                          ) : (
                            '-'
                          )}
                        </td>
                        <td className="px-4 py-2.5 text-slate-400">
                          {c.onDelete ? `CASCADE: ${c.onDelete}` : '-'}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* TAB 6: DDL / SOURCE */}
        {activeTab === 'ddl' && (
          <div className="h-full flex flex-col p-4">
            <div className="flex items-center justify-between pb-3">
              <span className="text-xs text-slate-400 font-mono">
                Generated DDL for {table.schema}.{table.name} ({engine.toUpperCase()})
              </span>
              <button
                onClick={handleCopyDdl}
                className="flex items-center gap-1.5 px-3 py-1 rounded bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-medium border border-slate-700 transition"
              >
                {copiedDdl ? (
                  <>
                    <Check className="w-3.5 h-3.5 text-emerald-400" />
                    <span className="text-emerald-400">Copied!</span>
                  </>
                ) : (
                  <>
                    <Copy className="w-3.5 h-3.5" />
                    <span>Copy DDL</span>
                  </>
                )}
              </button>
            </div>

            <pre className="flex-1 p-4 rounded-xl bg-slate-900/90 border border-slate-800 text-xs font-mono text-slate-200 overflow-auto whitespace-pre leading-relaxed select-text">
              {fullDdl}
            </pre>
          </div>
        )}

        {/* TAB 7: ER DIAGRAM */}
        {activeTab === 'erd' && (
          <ERDiagram
            currentTable={table}
            allTables={allTables}
            onSelectTable={onSelectTable}
          />
        )}
      </div>

      {/* Export Data Modal */}
      {showExportModal && (
        <ExportModal
          isOpen={showExportModal}
          onClose={() => setShowExportModal(false)}
          tableName={table.name}
          columns={colNames}
          rows={table.rows}
        />
      )}

      {/* Cell Detail / JSON Inspector Modal */}
      {inspectCell && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-xs p-4">
          <div className="w-full max-w-lg bg-slate-900 border border-slate-700 rounded-xl p-5 shadow-2xl flex flex-col max-h-[80vh]">
            <div className="flex items-center justify-between pb-3 border-b border-slate-800">
              <span className="text-xs font-semibold text-slate-200 flex items-center gap-1.5">
                <Maximize2 className="w-3.5 h-3.5 text-sky-400" />
                Value Inspector: <code className="text-sky-300 font-mono">{inspectCell.col}</code>
              </span>
              <button
                onClick={() => setInspectCell(null)}
                className="text-slate-400 hover:text-white text-xs"
              >
                Close
              </button>
            </div>
            <pre className="mt-4 p-3 bg-slate-950 rounded-lg text-xs font-mono text-slate-200 overflow-auto flex-1 whitespace-pre-wrap">
              {typeof inspectCell.val === 'object'
                ? JSON.stringify(inspectCell.val, null, 2)
                : String(inspectCell.val ?? 'NULL')}
            </pre>
          </div>
        </div>
      )}

      {/* Insert Row Modal */}
      {isAddingRow && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-xs p-4">
          <form
            onSubmit={handleSaveNewRow}
            className="w-full max-w-md bg-slate-900 border border-slate-700 rounded-xl p-5 shadow-2xl space-y-4"
          >
            <div className="flex items-center justify-between pb-2 border-b border-slate-800">
              <span className="text-xs font-semibold text-slate-200 flex items-center gap-1.5">
                <Plus className="w-3.5 h-3.5 text-emerald-400" />
                Insert Row into {table.name}
              </span>
              <button
                type="button"
                onClick={() => setIsAddingRow(false)}
                className="text-slate-400 hover:text-white text-xs"
              >
                Cancel
              </button>
            </div>

            <div className="space-y-2.5 max-h-72 overflow-y-auto pr-1">
              {columns.map(col => (
                <div key={col.name}>
                  <label className="block text-[11px] text-slate-400 font-mono mb-1">
                    {col.name} ({col.type})
                  </label>
                  <input
                    type="text"
                    placeholder={col.defaultValue ? `Default: ${col.defaultValue}` : ''}
                    value={newRowData[col.name] ?? ''}
                    onChange={(e) => setNewRowData({ ...newRowData, [col.name]: e.target.value })}
                    className="w-full bg-slate-950 border border-slate-700 rounded px-2.5 py-1.5 text-xs text-white font-mono placeholder-slate-600 focus:outline-none focus:border-sky-500"
                  />
                </div>
              ))}
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-slate-800">
              <button
                type="button"
                onClick={() => setIsAddingRow(false)}
                className="px-3 py-1.5 text-slate-400 hover:text-white text-xs"
              >
                Cancel
              </button>
              <button
                type="submit"
                className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded text-xs font-semibold shadow-xs"
              >
                Save Row
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
};
