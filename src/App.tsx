import React, { useState, useEffect } from 'react';
import { 
  Database, 
  Code2, 
  Table, 
  X, 
  Plus, 
  PanelLeftClose, 
  PanelLeft, 
  Share2, 
  Layers
} from 'lucide-react';
import { 
  ConnectionConfig, 
  DriverInfo, 
  DatabaseCatalog, 
  EditorTab, 
  QueryHistoryItem, 
  TableMetadata 
} from './types/db';
import { StorageService } from './services/storage';
import { TopBar } from './components/navigation/TopBar';
import { DatabaseNavigator } from './components/navigation/DatabaseNavigator';
import { SqlEditor } from './components/editor/SqlEditor';
import { TableInspector } from './components/inspector/TableInspector';
import { ConnectionModal } from './components/connections/ConnectionModal';
import { DriverManagerModal } from './components/drivers/DriverManagerModal';
import { QueryHistoryModal } from './components/history/QueryHistoryModal';
import { ExportModal } from './components/export/ExportModal';
import { AboutModal } from './components/common/AboutModal';
import { OfflineIndicator } from './components/common/OfflineIndicator';

export default function App() {
  // Connections and Active State
  const [connections, setConnections] = useState<ConnectionConfig[]>(() => StorageService.getConnections());
  const [activeConnectionId, setActiveConnectionId] = useState<string>(() => StorageService.getActiveConnectionId());
  const [catalogs, setCatalogs] = useState<Record<string, DatabaseCatalog>>(() => StorageService.getCatalogs());
  const [drivers, setDrivers] = useState<DriverInfo[]>(() => StorageService.getDrivers());

  // Editor Tabs
  const [tabs, setTabs] = useState<EditorTab[]>(() => StorageService.getSavedTabs());
  const [activeTabId, setActiveTabId] = useState<string>(() => StorageService.getActiveTabId());

  // Sidebar visibility
  const [sidebarOpen, setSidebarOpen] = useState(true);

  // Modals
  const [isConnectionModalOpen, setIsConnectionModalOpen] = useState(false);
  const [editingConnection, setEditingConnection] = useState<ConnectionConfig | null>(null);
  const [isDriverManagerOpen, setIsDriverManagerOpen] = useState(false);
  const [isHistoryModalOpen, setIsHistoryModalOpen] = useState(false);
  const [isExportModalOpen, setIsExportModalOpen] = useState(false);
  const [isAboutModalOpen, setIsAboutModalOpen] = useState(false);

  // Query History
  const [history, setHistory] = useState<QueryHistoryItem[]>(() => StorageService.getQueryHistory());

  // Synchronize state with Storage
  useEffect(() => {
    StorageService.saveConnections(connections);
  }, [connections]);

  useEffect(() => {
    StorageService.saveCatalogs(catalogs);
  }, [catalogs]);

  useEffect(() => {
    StorageService.saveDrivers(drivers);
  }, [drivers]);

  useEffect(() => {
    StorageService.saveTabs(tabs);
  }, [tabs]);

  useEffect(() => {
    StorageService.saveActiveTabId(activeTabId);
  }, [activeTabId]);

  useEffect(() => {
    StorageService.saveActiveConnectionId(activeConnectionId);
  }, [activeConnectionId]);

  const activeConnection = connections.find(c => c.id === activeConnectionId) || connections[0];
  const activeCatalog = catalogs[activeConnectionId] || Object.values(catalogs)[0];
  const activeTab = tabs.find(t => t.id === activeTabId) || tabs[0];

  // Helper: Open a table in an inspector tab
  const handleOpenTable = (
    connectionId: string, 
    schema: string, 
    tableName: string, 
    viewTab: any = 'data'
  ) => {
    setActiveConnectionId(connectionId);
    const existingTabIndex = tabs.findIndex(t => 
      t.type === 'TABLE_VIEW' && 
      t.tableTarget?.connectionId === connectionId && 
      t.tableTarget?.tableName === tableName
    );

    if (existingTabIndex !== -1) {
      const existingTab = tabs[existingTabIndex];
      // Update target viewTab if specified
      if (existingTab.tableTarget) {
        existingTab.tableTarget.activeTab = viewTab;
      }
      setActiveTabId(existingTab.id);
    } else {
      const newTab: EditorTab = {
        id: `tab-table-${Date.now()}`,
        title: `${tableName}`,
        type: 'TABLE_VIEW',
        connectionId,
        tableTarget: {
          connectionId,
          schema,
          tableName,
          activeTab: viewTab,
        },
      };
      setTabs([...tabs, newTab]);
      setActiveTabId(newTab.id);
    }
  };

  // Helper: Open new SQL Query tab
  const handleNewQuery = (connectionId?: string, initialSql?: string) => {
    const connId = connectionId || activeConnectionId;
    const count = tabs.filter(t => t.type === 'SQL').length + 1;
    const newTab: EditorTab = {
      id: `tab-sql-${Date.now()}`,
      title: `Script-${count}.sql`,
      type: 'SQL',
      connectionId: connId,
      content: initialSql || `-- SQL Query for ${activeConnection.name}\nSELECT * FROM ${activeCatalog?.schemas[0]?.tables[0]?.schema || 'public'}.${activeCatalog?.schemas[0]?.tables[0]?.name || 'users'} LIMIT 50;`,
    };
    setTabs([...tabs, newTab]);
    setActiveTabId(newTab.id);
  };

  const handleCloseTab = (tabId: string) => {
    if (tabs.length <= 1) return;
    const nextTabs = tabs.filter(t => t.id !== tabId);
    setTabs(nextTabs);
    if (activeTabId === tabId) {
      setActiveTabId(nextTabs[nextTabs.length - 1].id);
    }
  };

  const handleUpdateTabContent = (tabId: string, content: string) => {
    setTabs(prev => prev.map(t => t.id === tabId ? { ...t, content } : t));
  };

  // Connection management
  const handleSaveConnection = (newConn: ConnectionConfig) => {
    const existingIndex = connections.findIndex(c => c.id === newConn.id);
    if (existingIndex !== -1) {
      const updated = [...connections];
      updated[existingIndex] = newConn;
      setConnections(updated);
    } else {
      setConnections([...connections, newConn]);
      // Bootstrap default catalog if new
      if (!catalogs[newConn.id]) {
        const defaultSchemaName = newConn.engine === 'mongodb' ? newConn.database : 'public';
        setCatalogs({
          ...catalogs,
          [newConn.id]: {
            name: newConn.database,
            schemas: [
              {
                id: `schema-${Date.now()}`,
                name: defaultSchemaName,
                tables: [
                  {
                    id: `tbl-sample-${Date.now()}`,
                    name: 'sample_records',
                    schema: defaultSchemaName,
                    type: newConn.engine === 'mongodb' ? 'COLLECTION' : 'TABLE',
                    engine: newConn.engine,
                    rowCount: 1,
                    sizeBytes: 4096,
                    columns: [
                      { name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false },
                      { name: 'title', type: 'VARCHAR(128)', isNullable: false },
                      { name: 'created_at', type: 'TIMESTAMP', isNullable: false, defaultValue: 'NOW()' },
                    ],
                    indexes: [
                      { name: 'pk_sample', columns: ['id'], type: 'BTREE', isUnique: true },
                    ],
                    partitions: [],
                    constraints: [
                      { name: 'pk_sample', type: 'PRIMARY KEY', columns: ['id'] },
                    ],
                    rows: [
                      { id: 1, title: 'Initial connected record', created_at: new Date().toISOString() },
                    ],
                  },
                ],
              },
            ],
          },
        });
      }
    }
    setActiveConnectionId(newConn.id);
  };

  const handleDeleteConnection = (connId: string) => {
    if (connections.length <= 1) {
      alert('At least one database connection must remain in the navigator.');
      return;
    }
    const filtered = connections.filter(c => c.id !== connId);
    setConnections(filtered);
    if (activeConnectionId === connId) {
      setActiveConnectionId(filtered[0].id);
    }
  };

  // Table row update handler
  const handleUpdateTableData = (updatedTable: TableMetadata) => {
    const currentCatalog = catalogs[activeConnectionId];
    if (!currentCatalog) return;

    const updatedSchemas = currentCatalog.schemas.map(schema => {
      if (schema.name === updatedTable.schema) {
        return {
          ...schema,
          tables: schema.tables.map(t => t.name === updatedTable.name ? updatedTable : t),
        };
      }
      return schema;
    });

    setCatalogs({
      ...catalogs,
      [activeConnectionId]: {
        ...currentCatalog,
        schemas: updatedSchemas,
      },
    });
  };

  // Find target table for active Table View tab
  const getActiveTableMetadata = (): TableMetadata | null => {
    if (!activeTab || activeTab.type !== 'TABLE_VIEW' || !activeTab.tableTarget) return null;
    const cat = catalogs[activeTab.tableTarget.connectionId];
    if (!cat) return null;
    const sch = cat.schemas.find(s => s.name === activeTab.tableTarget?.schema);
    if (!sch) return null;
    return sch.tables.find(t => t.name === activeTab.tableTarget?.tableName) || null;
  };

  const activeTableMeta = getActiveTableMetadata();
  const allCurrentTables = activeCatalog?.schemas.flatMap(s => s.tables) || [];

  return (
    <div className="h-screen w-screen flex flex-col bg-slate-950 text-slate-100 overflow-hidden font-sans">
      {/* 1. TOP HEADER & MAIN CONTROLS */}
      <TopBar
        connections={connections}
        activeConnection={activeConnection}
        drivers={drivers}
        onSelectConnection={(id) => setActiveConnectionId(id)}
        onNewConnection={() => {
          setEditingConnection(null);
          setIsConnectionModalOpen(true);
        }}
        onNewQuery={() => handleNewQuery()}
        onOpenDriverManager={() => setIsDriverManagerOpen(true)}
        onOpenHistory={() => setIsHistoryModalOpen(true)}
        onOpenExport={() => setIsExportModalOpen(true)}
        onOpenAbout={() => setIsAboutModalOpen(true)}
      />

      {/* 2. MAIN APPLICATION WORKSPACE */}
      <div className="flex-1 flex overflow-hidden">
        {/* Left Sidebar: Database Navigator */}
        <aside
          className={`${
            sidebarOpen ? 'w-72 sm:w-80' : 'w-0'
          } shrink-0 transition-all duration-200 ease-in-out relative flex flex-col z-10`}
        >
          {sidebarOpen && (
            <DatabaseNavigator
              connections={connections}
              activeConnectionId={activeConnectionId}
              catalogs={catalogs}
              drivers={drivers}
              onSelectConnection={(id) => setActiveConnectionId(id)}
              onOpenTable={handleOpenTable}
              onOpenQueryTab={handleNewQuery}
              onNewConnection={() => {
                setEditingConnection(null);
                setIsConnectionModalOpen(true);
              }}
              onEditConnection={(conn) => {
                setEditingConnection(conn);
                setIsConnectionModalOpen(true);
              }}
              onDeleteConnection={handleDeleteConnection}
            />
          )}
        </aside>

        {/* Sidebar Toggle Handle */}
        <button
          onClick={() => setSidebarOpen(!sidebarOpen)}
          className="w-4 h-8 self-center -ml-2 z-20 rounded-r bg-slate-800 hover:bg-slate-700 border border-slate-700/80 flex items-center justify-center text-slate-400 hover:text-white transition shadow-md"
          title={sidebarOpen ? 'Collapse Database Navigator' : 'Expand Database Navigator'}
        >
          {sidebarOpen ? (
            <PanelLeftClose className="w-3 h-3" />
          ) : (
            <PanelLeft className="w-3 h-3" />
          )}
        </button>

        {/* Main Content Pane */}
        <main className="flex-1 flex flex-col min-w-0 bg-slate-950 overflow-hidden">
          {/* Workspace Multi-Tab Header */}
          <div className="h-9 bg-slate-900 border-b border-slate-800 flex items-center justify-between px-2 text-xs select-none shrink-0">
            <div className="flex items-center gap-1 overflow-x-auto max-w-[85vw] no-scrollbar">
              {tabs.map(tab => {
                const isActive = tab.id === activeTabId;
                return (
                  <div
                    key={tab.id}
                    onClick={() => setActiveTabId(tab.id)}
                    className={`flex items-center gap-2 px-3 py-1.5 rounded-t-md text-xs font-mono transition cursor-pointer border-t border-x ${
                      isActive
                        ? 'bg-slate-950 border-slate-700 text-sky-400 font-semibold'
                        : 'bg-slate-900/60 border-transparent text-slate-400 hover:text-slate-200 hover:bg-slate-800/80'
                    }`}
                  >
                    {tab.type === 'SQL' ? (
                      <Code2 className="w-3 h-3 text-sky-400" />
                    ) : (
                      <Table className="w-3 h-3 text-amber-400" />
                    )}
                    <span>{tab.title}</span>

                    {tabs.length > 1 && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleCloseTab(tab.id);
                        }}
                        className="p-0.5 rounded text-slate-500 hover:text-white hover:bg-slate-700 transition"
                      >
                        <X className="w-2.5 h-2.5" />
                      </button>
                    )}
                  </div>
                );
              })}

              <button
                onClick={() => handleNewQuery()}
                className="p-1 rounded text-slate-400 hover:text-white hover:bg-slate-800 transition ml-1"
                title="New SQL Console"
              >
                <Plus className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          {/* Active Tab Workspace View */}
          <div className="flex-1 overflow-hidden">
            {activeTab?.type === 'SQL' ? (
              <SqlEditor
                tabs={tabs.filter(t => t.type === 'SQL')}
                activeTabId={activeTabId}
                onSelectTab={(id) => setActiveTabId(id)}
                onCloseTab={handleCloseTab}
                onNewTab={() => handleNewQuery()}
                onUpdateTabContent={handleUpdateTabContent}
                activeConnection={activeConnection}
                catalog={activeCatalog}
                onAddHistory={(item) => {
                  StorageService.addQueryHistory(item);
                  setHistory(StorageService.getQueryHistory());
                }}
              />
            ) : activeTableMeta ? (
              <TableInspector
                table={activeTableMeta}
                allTables={allCurrentTables}
                engine={activeConnection.engine}
                onUpdateTable={handleUpdateTableData}
                onSelectTable={(tableName) => {
                  const target = allCurrentTables.find(t => t.name === tableName);
                  if (target) {
                    handleOpenTable(activeConnectionId, target.schema, target.name);
                  }
                }}
                initialTab={activeTab.tableTarget?.activeTab || 'data'}
              />
            ) : (
              <div className="h-full flex flex-col items-center justify-center p-8 text-slate-500 gap-3">
                <Database className="w-10 h-10 text-slate-700" />
                <div className="text-center">
                  <h3 className="text-sm font-semibold text-slate-300">Object Not Available</h3>
                  <p className="text-xs text-slate-500 mt-1">Select a table or open a query editor script.</p>
                </div>
                <button
                  onClick={() => handleNewQuery()}
                  className="px-3 py-1.5 rounded-lg bg-sky-600 hover:bg-sky-500 text-white text-xs font-semibold"
                >
                  Open SQL Console
                </button>
              </div>
            )}
          </div>
        </main>
      </div>

      {/* 3. MODALS AND DRAWERS */}
      {/* Connection Modal */}
      <ConnectionModal
        isOpen={isConnectionModalOpen}
        onClose={() => {
          setIsConnectionModalOpen(false);
          setEditingConnection(null);
        }}
        drivers={drivers}
        onSaveConnection={handleSaveConnection}
        editingConnection={editingConnection}
        onOpenDriverManager={() => setIsDriverManagerOpen(true)}
      />

      {/* Driver Manager Modal */}
      <DriverManagerModal
        isOpen={isDriverManagerOpen}
        onClose={() => setIsDriverManagerOpen(false)}
        drivers={drivers}
        onUpdateDrivers={(updated) => setDrivers(updated)}
        onSelectDriverToConnect={(driver) => {
          setEditingConnection(null);
          setIsConnectionModalOpen(true);
        }}
      />

      {/* Query History Modal */}
      <QueryHistoryModal
        isOpen={isHistoryModalOpen}
        onClose={() => setIsHistoryModalOpen(false)}
        history={history}
        onSelectQuery={(sql) => {
          handleNewQuery(activeConnectionId, sql);
        }}
        onClearHistory={() => {
          StorageService.clearQueryHistory();
          setHistory([]);
        }}
      />

      {/* Standalone Export Modal */}
      {isExportModalOpen && (
        <ExportModal
          isOpen={isExportModalOpen}
          onClose={() => setIsExportModalOpen(false)}
          tableName={activeTableMeta?.name || 'database_export'}
          columns={activeTableMeta?.columns.map(c => c.name) || ['id', 'name', 'status']}
          rows={activeTableMeta?.rows || [
            { id: 101, name: 'Sample row 1', status: 'ACTIVE' },
            { id: 102, name: 'Sample row 2', status: 'PENDING' },
          ]}
        />
      )}

      {/* About Modal */}
      <AboutModal
        isOpen={isAboutModalOpen}
        onClose={() => setIsAboutModalOpen(false)}
      />

      {/* 4. OFFLINE STATUS BANNER */}
      <OfflineIndicator />
    </div>
  );
}
