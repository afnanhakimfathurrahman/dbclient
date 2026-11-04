import React, { useState } from 'react';
import { 
  Database, 
  ChevronRight, 
  ChevronDown, 
  Table, 
  Layers, 
  Key, 
  Split, 
  ShieldAlert, 
  Search, 
  Plus, 
  RotateCw, 
  Code2, 
  MoreVertical, 
  Trash2, 
  Edit3, 
  Eye, 
  Folder, 
  FolderOpen
} from 'lucide-react';
import { ConnectionConfig, DatabaseCatalog, TableMetadata, DriverInfo } from '../../types/db';

interface DatabaseNavigatorProps {
  connections: ConnectionConfig[];
  activeConnectionId: string;
  catalogs: Record<string, DatabaseCatalog>;
  drivers: DriverInfo[];
  onSelectConnection: (id: string) => void;
  onOpenTable: (connectionId: string, schema: string, tableName: string, viewTab?: any) => void;
  onOpenQueryTab: (connectionId: string, initialSql?: string) => void;
  onNewConnection: () => void;
  onEditConnection: (conn: ConnectionConfig) => void;
  onDeleteConnection: (connId: string) => void;
}

export const DatabaseNavigator: React.FC<DatabaseNavigatorProps> = ({
  connections,
  activeConnectionId,
  catalogs,
  drivers,
  onSelectConnection,
  onOpenTable,
  onOpenQueryTab,
  onNewConnection,
  onEditConnection,
  onDeleteConnection,
}) => {
  const [search, setSearch] = useState('');
  const [expandedNodes, setExpandedNodes] = useState<Record<string, boolean>>({
    'conn-pg-prod': true,
    'conn-pg-prod-schema-public': true,
    'conn-pg-prod-tables': true,
    'conn-mongo-cluster': false,
    'conn-clickhouse-olap': false,
  });
  const [menuConnId, setMenuConnId] = useState<string | null>(null);

  const toggleNode = (nodeId: string, e?: React.MouseEvent) => {
    if (e) e.stopPropagation();
    setExpandedNodes(prev => ({
      ...prev,
      [nodeId]: !prev[nodeId],
    }));
  };

  const getDriverIcon = (driverId: string) => {
    const driver = drivers.find(d => d.id === driverId);
    return driver?.icon || '🗄️';
  };

  return (
    <div className="h-full flex flex-col bg-slate-900 border-r border-slate-800 text-xs text-slate-300 select-none overflow-hidden">
      {/* Navigator Header */}
      <div className="px-3 py-2.5 bg-slate-950/80 border-b border-slate-800 flex items-center justify-between gap-2">
        <span className="font-semibold text-slate-200 tracking-wide flex items-center gap-1.5 text-xs">
          <Database className="w-3.5 h-3.5 text-sky-400" />
          <span>Database Navigator</span>
        </span>

        <div className="flex items-center gap-1">
          <button
            onClick={onNewConnection}
            className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-800 transition"
            title="Create New Database Connection"
          >
            <Plus className="w-3.5 h-3.5" />
          </button>
          <button
            onClick={() => setExpandedNodes({})}
            className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-800 transition"
            title="Collapse All Tree Nodes"
          >
            <RotateCw className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* Filter / Search input */}
      <div className="p-2 border-b border-slate-800/80 bg-slate-950/50">
        <div className="relative">
          <Search className="w-3 h-3 absolute left-2.5 top-2 text-slate-500" />
          <input
            type="text"
            placeholder="Filter database objects..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full bg-slate-900 border border-slate-700/80 rounded pl-7 pr-2 py-1 text-[11px] text-white placeholder-slate-500 focus:outline-none focus:border-sky-500"
          />
        </div>
      </div>

      {/* Tree Content */}
      <div className="flex-1 overflow-y-auto overflow-x-hidden p-1 space-y-1 font-mono text-[11px]">
        {connections.map(conn => {
          const isConnExpanded = expandedNodes[conn.id] ?? false;
          const isActive = conn.id === activeConnectionId;
          const catalog = catalogs[conn.id];

          return (
            <div key={conn.id} className="rounded-lg overflow-hidden">
              {/* Connection Node */}
              <div
                onClick={() => {
                  onSelectConnection(conn.id);
                  toggleNode(conn.id);
                }}
                className={`group flex items-center justify-between px-2 py-1.5 rounded cursor-pointer transition ${
                  isActive 
                    ? 'bg-sky-950/60 text-sky-200 font-semibold' 
                    : 'hover:bg-slate-800/60 text-slate-300'
                }`}
              >
                <div className="flex items-center gap-1.5 truncate">
                  {isConnExpanded ? (
                    <ChevronDown className="w-3.5 h-3.5 text-slate-400 shrink-0" />
                  ) : (
                    <ChevronRight className="w-3.5 h-3.5 text-slate-400 shrink-0" />
                  )}

                  <span className="text-sm shrink-0">{getDriverIcon(conn.driverId)}</span>

                  <span
                    className="w-2 h-2 rounded-full shrink-0"
                    style={{ backgroundColor: conn.colorTag || '#3b82f6' }}
                    title={`Environment tag`}
                  />

                  <span className="truncate">{conn.name}</span>
                </div>

                {/* Connection Quick Actions */}
                <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onOpenQueryTab(conn.id, `SELECT * FROM ${catalog?.schemas[0]?.tables[0]?.schema}.${catalog?.schemas[0]?.tables[0]?.name} LIMIT 50;`);
                    }}
                    className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-700"
                    title="Open SQL Query Console"
                  >
                    <Code2 className="w-3 h-3 text-sky-400" />
                  </button>

                  <div className="relative">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setMenuConnId(menuConnId === conn.id ? null : conn.id);
                      }}
                      className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-700"
                    >
                      <MoreVertical className="w-3 h-3" />
                    </button>

                    {menuConnId === conn.id && (
                      <div 
                        className="absolute right-0 mt-1 w-36 bg-slate-900 border border-slate-700 rounded-lg shadow-xl p-1 z-50 font-sans"
                        onClick={(e) => e.stopPropagation()}
                      >
                        <button
                          onClick={() => {
                            setMenuConnId(null);
                            onEditConnection(conn);
                          }}
                          className="w-full text-left px-2 py-1.5 text-[11px] text-slate-200 hover:bg-slate-800 rounded flex items-center gap-1.5"
                        >
                          <Edit3 className="w-3 h-3" />
                          <span>Edit Settings</span>
                        </button>
                        <button
                          onClick={() => {
                            setMenuConnId(null);
                            onDeleteConnection(conn.id);
                          }}
                          className="w-full text-left px-2 py-1.5 text-[11px] text-red-400 hover:bg-red-950/40 rounded flex items-center gap-1.5"
                        >
                          <Trash2 className="w-3 h-3" />
                          <span>Disconnect</span>
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* Schemas & Tables inside Connection */}
              {isConnExpanded && catalog && (
                <div className="ml-4 pl-2 border-l border-slate-800/80 space-y-0.5 mt-0.5">
                  {catalog.schemas.map(schema => {
                    const schemaNodeId = `${conn.id}-schema-${schema.name}`;
                    const isSchemaExpanded = expandedNodes[schemaNodeId] ?? true;

                    // Filter tables if searching
                    const visibleTables = schema.tables.filter(t => 
                      t.name.toLowerCase().includes(search.toLowerCase()) ||
                      t.columns.some(c => c.name.toLowerCase().includes(search.toLowerCase()))
                    );

                    if (search && visibleTables.length === 0) return null;

                    return (
                      <div key={schema.id}>
                        {/* Schema Node */}
                        <div
                          onClick={(e) => toggleNode(schemaNodeId, e)}
                          className="flex items-center gap-1.5 px-2 py-1 text-slate-400 hover:text-slate-200 hover:bg-slate-800/40 rounded cursor-pointer"
                        >
                          {isSchemaExpanded ? (
                            <ChevronDown className="w-3 h-3 text-slate-500" />
                          ) : (
                            <ChevronRight className="w-3 h-3 text-slate-500" />
                          )}
                          {isSchemaExpanded ? (
                            <FolderOpen className="w-3.5 h-3.5 text-amber-400" />
                          ) : (
                            <Folder className="w-3.5 h-3.5 text-amber-400" />
                          )}
                          <span className="font-semibold text-slate-300">{schema.name}</span>
                          <span className="text-[10px] text-slate-400 font-sans ml-auto">
                            ({visibleTables.length})
                          </span>
                        </div>

                        {/* Tables inside Schema */}
                        {isSchemaExpanded && (
                          <div className="ml-4 pl-2 border-l border-slate-800/60 space-y-0.5 mt-0.5">
                            {visibleTables.map(tbl => {
                              const tblNodeId = `${conn.id}-${schema.name}-${tbl.name}`;
                              const isTblExpanded = expandedNodes[tblNodeId] ?? false;

                              return (
                                <div key={tbl.id}>
                                  {/* Table Node */}
                                  <div
                                    onDoubleClick={() => onOpenTable(conn.id, schema.name, tbl.name)}
                                    onClick={(e) => toggleNode(tblNodeId, e)}
                                    className="group flex items-center justify-between px-2 py-1 text-slate-300 hover:bg-slate-800 hover:text-white rounded cursor-pointer"
                                  >
                                    <div className="flex items-center gap-1.5 truncate">
                                      {isTblExpanded ? (
                                        <ChevronDown className="w-3 h-3 text-slate-500" />
                                      ) : (
                                        <ChevronRight className="w-3 h-3 text-slate-500" />
                                      )}
                                      <Table className="w-3.5 h-3.5 text-sky-400 shrink-0" />
                                      <span className="truncate">{tbl.name}</span>
                                    </div>

                                    {/* Action on hover */}
                                    <button
                                      onClick={(e) => {
                                        e.stopPropagation();
                                        onOpenTable(conn.id, schema.name, tbl.name);
                                      }}
                                      className="opacity-0 group-hover:opacity-100 p-0.5 rounded text-slate-400 hover:text-white"
                                      title="Open Table View"
                                    >
                                      <Eye className="w-3 h-3" />
                                    </button>
                                  </div>

                                  {/* Table Sub-Objects (Columns, Indexes, Partitions, Constraints) */}
                                  {isTblExpanded && (
                                    <div className="ml-4 pl-2 border-l border-slate-800/50 space-y-0.5 text-[10px] text-slate-400">
                                      {/* Columns Folder */}
                                      <div 
                                        onClick={() => onOpenTable(conn.id, schema.name, tbl.name, 'columns')}
                                        className="flex items-center gap-1 px-1.5 py-0.5 hover:text-sky-300 hover:bg-slate-800/40 rounded cursor-pointer"
                                      >
                                        <Layers className="w-3 h-3 text-sky-400" />
                                        <span>Columns ({tbl.columns.length})</span>
                                      </div>

                                      {/* Indexes Folder */}
                                      <div 
                                        onClick={() => onOpenTable(conn.id, schema.name, tbl.name, 'indexes')}
                                        className="flex items-center gap-1 px-1.5 py-0.5 hover:text-amber-300 hover:bg-slate-800/40 rounded cursor-pointer"
                                      >
                                        <Key className="w-3 h-3 text-amber-400" />
                                        <span>Indexes ({tbl.indexes.length})</span>
                                      </div>

                                      {/* Partitions Folder (if any) */}
                                      {tbl.partitions.length > 0 && (
                                        <div 
                                          onClick={() => onOpenTable(conn.id, schema.name, tbl.name, 'partitions')}
                                          className="flex items-center gap-1 px-1.5 py-0.5 hover:text-emerald-300 hover:bg-slate-800/40 rounded cursor-pointer"
                                        >
                                          <Split className="w-3 h-3 text-emerald-400" />
                                          <span>Partitions ({tbl.partitions.length})</span>
                                        </div>
                                      )}

                                      {/* Constraints Folder */}
                                      {tbl.constraints.length > 0 && (
                                        <div 
                                          onClick={() => onOpenTable(conn.id, schema.name, tbl.name, 'constraints')}
                                          className="flex items-center gap-1 px-1.5 py-0.5 hover:text-rose-300 hover:bg-slate-800/40 rounded cursor-pointer"
                                        >
                                          <ShieldAlert className="w-3 h-3 text-rose-400" />
                                          <span>Constraints ({tbl.constraints.length})</span>
                                        </div>
                                      )}
                                    </div>
                                  )}
                                </div>
                              );
                            })}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};
