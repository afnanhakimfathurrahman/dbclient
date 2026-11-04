import React from 'react';
import { Key, Link, Hash, FileText } from 'lucide-react';
import { TableMetadata } from '../../types/db';

interface ERDiagramProps {
  currentTable: TableMetadata;
  allTables: TableMetadata[];
  onSelectTable: (tableName: string) => void;
}

export const ERDiagram: React.FC<ERDiagramProps> = ({
  currentTable,
  allTables,
  onSelectTable,
}) => {
  // Find tables related to currentTable (either referencing or referenced)
  const relatedTables = allTables.filter(t => {
    if (t.name === currentTable.name) return true;

    // Does t reference currentTable?
    const referencesCurrent = t.constraints.some(c => 
      c.type === 'FOREIGN KEY' && c.referencedTable?.toLowerCase() === currentTable.name.toLowerCase()
    );
    // Does currentTable reference t?
    const referencedByCurrent = currentTable.constraints.some(c =>
      c.type === 'FOREIGN KEY' && c.referencedTable?.toLowerCase() === t.name.toLowerCase()
    );

    return referencesCurrent || referencedByCurrent;
  });

  return (
    <div className="h-full flex flex-col bg-slate-950 p-6 overflow-auto">
      <div className="flex items-center justify-between pb-4 border-b border-slate-800">
        <div>
          <h3 className="text-sm font-semibold text-white flex items-center gap-2">
            <Link className="w-4 h-4 text-sky-400" />
            Entity-Relationship (ER) Schema Graph
          </h3>
          <p className="text-xs text-slate-400 mt-0.5">
            Visualizing relationships and foreign key references for <span className="font-semibold text-sky-300 font-mono">{currentTable.name}</span>
          </p>
        </div>

        <div className="flex items-center gap-4 text-xs text-slate-400">
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded bg-sky-500" />
            <span>Active Table</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded bg-slate-700" />
            <span>Related Tables</span>
          </div>
          <div className="flex items-center gap-1.5">
            <Key className="w-3 h-3 text-amber-400" />
            <span>Primary Key</span>
          </div>
          <div className="flex items-center gap-1.5">
            <Link className="w-3 h-3 text-sky-400" />
            <span>Foreign Key</span>
          </div>
        </div>
      </div>

      {/* Diagram Canvas */}
      <div className="flex-1 min-h-[400px] flex items-center justify-center p-8">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 items-start max-w-5xl w-full">
          {relatedTables.map(table => {
            const isMain = table.name === currentTable.name;

            return (
              <div
                key={table.id}
                onClick={() => onSelectTable(table.name)}
                className={`rounded-xl border shadow-xl transition cursor-pointer overflow-hidden ${
                  isMain
                    ? 'bg-slate-900 border-sky-500 ring-2 ring-sky-500/30'
                    : 'bg-slate-900/90 border-slate-800 hover:border-slate-700 hover:scale-[1.01]'
                }`}
              >
                {/* Table Header */}
                <div className={`px-4 py-2.5 border-b flex items-center justify-between ${
                  isMain ? 'bg-sky-950/80 border-sky-800' : 'bg-slate-950/80 border-slate-800'
                }`}>
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-xs font-mono text-white">
                      {table.schema}.{table.name}
                    </span>
                    {isMain && (
                      <span className="text-[10px] px-1.5 py-0.2 rounded bg-sky-500 text-white font-semibold">
                        Focus
                      </span>
                    )}
                  </div>
                  <span className="text-[10px] text-slate-400 font-mono">
                    {table.rowCount} rows
                  </span>
                </div>

                {/* Columns List */}
                <div className="p-3 space-y-1.5 max-h-60 overflow-y-auto">
                  {table.columns.map(col => {
                    const isFk = table.constraints.some(c => 
                      c.type === 'FOREIGN KEY' && c.columns.includes(col.name)
                    );

                    return (
                      <div
                        key={col.name}
                        className={`flex items-center justify-between px-2 py-1 rounded text-[11px] font-mono transition ${
                          col.isPrimaryKey 
                            ? 'bg-amber-950/30 text-amber-200 font-semibold' 
                            : isFk 
                              ? 'bg-sky-950/30 text-sky-200' 
                              : 'text-slate-300'
                        }`}
                      >
                        <div className="flex items-center gap-1.5 truncate">
                          {col.isPrimaryKey ? (
                            <Key className="w-3 h-3 text-amber-400 shrink-0" />
                          ) : isFk ? (
                            <Link className="w-3 h-3 text-sky-400 shrink-0" />
                          ) : (
                            <Hash className="w-3 h-3 text-slate-500 shrink-0" />
                          )}
                          <span className="truncate">{col.name}</span>
                        </div>

                        <span className="text-[10px] text-slate-400 ml-2 shrink-0">
                          {col.type}
                        </span>
                      </div>
                    );
                  })}
                </div>

                {/* Constraints Summary Badge */}
                <div className="px-3 py-2 bg-slate-950/60 border-t border-slate-800/80 flex items-center justify-between text-[10px] text-slate-400">
                  <span>Indexes: {table.indexes.length}</span>
                  <span>Partitions: {table.partitions.length}</span>
                  <span>FKs: {table.constraints.filter(c => c.type === 'FOREIGN KEY').length}</span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
