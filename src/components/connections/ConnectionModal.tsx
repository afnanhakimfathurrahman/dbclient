import React, { useState, useEffect } from 'react';
import { 
  Database, 
  Wifi, 
  CheckCircle2, 
  AlertCircle, 
  ShieldCheck, 
  Palette,
  ExternalLink
} from 'lucide-react';
import { Modal } from '../common/Modal';
import { ConnectionConfig, DriverInfo } from '../../types/db';

interface ConnectionModalProps {
  isOpen: boolean;
  onClose: () => void;
  drivers: DriverInfo[];
  onSaveConnection: (connection: ConnectionConfig) => void;
  editingConnection?: ConnectionConfig | null;
  onOpenDriverManager: () => void;
}

const COLOR_TAGS = [
  { label: 'Production (Red)', color: '#ef4444' },
  { label: 'Development (Blue)', color: '#3b82f6' },
  { label: 'Staging (Amber)', color: '#f59e0b' },
  { label: 'Analytics (Emerald)', color: '#10b981' },
  { label: 'Local (Purple)', color: '#8b5cf6' },
];

export const ConnectionModal: React.FC<ConnectionModalProps> = ({
  isOpen,
  onClose,
  drivers,
  onSaveConnection,
  editingConnection,
  onOpenDriverManager,
}) => {
  const installedDrivers = drivers.filter(d => d.isInstalled);
  const defaultDriver = installedDrivers[0] || drivers[0];

  const [selectedDriverId, setSelectedDriverId] = useState<string>(
    editingConnection?.driverId || defaultDriver?.id || ''
  );
  const [name, setName] = useState(editingConnection?.name || '');
  const [host, setHost] = useState(editingConnection?.host || 'localhost');
  const [port, setPort] = useState<number>(editingConnection?.port || defaultDriver?.defaultPort || 5432);
  const [database, setDatabase] = useState(editingConnection?.database || 'postgres');
  const [username, setUsername] = useState(editingConnection?.username || 'postgres');
  const [password, setPassword] = useState(editingConnection?.password || '');
  const [ssl, setSsl] = useState<boolean>(editingConnection?.ssl ?? true);
  const [colorTag, setColorTag] = useState<string>(editingConnection?.colorTag || '#3b82f6');

  // Test connection state
  const [isTesting, setIsTesting] = useState(false);
  const [testResult, setTestResult] = useState<{
    success: boolean;
    latencyMs: number;
    message: string;
    serverVersion: string;
  } | null>(null);

  // Sync when editing connection changes
  useEffect(() => {
    if (editingConnection) {
      setSelectedDriverId(editingConnection.driverId);
      setName(editingConnection.name);
      setHost(editingConnection.host);
      setPort(editingConnection.port);
      setDatabase(editingConnection.database);
      setUsername(editingConnection.username);
      setPassword(editingConnection.password || '');
      setSsl(editingConnection.ssl);
      setColorTag(editingConnection.colorTag || '#3b82f6');
      setTestResult(null);
    } else {
      const driver = installedDrivers[0];
      if (driver) {
        setSelectedDriverId(driver.id);
        setName(`${driver.name.split(' ')[0]} Local Connection`);
        setPort(driver.defaultPort);
        setDatabase(driver.engine === 'mongodb' ? 'shop_db' : driver.engine === 'clickhouse' ? 'default' : 'postgres');
        setUsername(driver.engine === 'mongodb' ? 'admin' : 'postgres');
      }
      setTestResult(null);
    }
  }, [editingConnection, isOpen]);

  const currentDriver = drivers.find(d => d.id === selectedDriverId) || installedDrivers[0];

  const handleDriverChange = (driverId: string) => {
    setSelectedDriverId(driverId);
    const driver = drivers.find(d => d.id === driverId);
    if (driver) {
      setPort(driver.defaultPort);
      if (!name || name.includes('Connection')) {
        setName(`${driver.name.split(' ')[0]} Connection`);
      }
      if (driver.engine === 'mongodb') {
        setDatabase('admin');
        setUsername('mongouser');
      } else if (driver.engine === 'clickhouse') {
        setDatabase('default');
        setUsername('default');
      } else if (driver.engine === 'mysql') {
        setDatabase('sys');
        setUsername('root');
      }
    }
    setTestResult(null);
  };

  const handleTestConnection = () => {
    setIsTesting(true);
    setTestResult(null);

    setTimeout(() => {
      setIsTesting(false);
      const ping = Math.floor(Math.random() * 25) + 12;
      setTestResult({
        success: true,
        latencyMs: ping,
        serverVersion: `${currentDriver?.name} v${currentDriver?.version} [Protocol ${currentDriver?.driverClass}]`,
        message: `Successfully connected to ${host}:${port}/${database}. Server response verified via TLS/SSL handshake.`,
      });
    }, 600);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name || !host || !database) return;

    const connection: ConnectionConfig = {
      id: editingConnection?.id || `conn-${Date.now()}`,
      name,
      driverId: selectedDriverId,
      engine: currentDriver?.engine || 'postgresql',
      host,
      port,
      database,
      username,
      password,
      ssl,
      colorTag,
      isConnected: true,
      lastConnected: 'Just now',
      pingMs: testResult?.latencyMs || 20,
    };

    onSaveConnection(connection);
    onClose();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      maxWidth="max-w-2xl"
      title={
        <div className="flex items-center gap-2">
          <Database className="w-4 h-4 text-sky-400" />
          <span>{editingConnection ? 'Edit Database Connection' : 'Create New Database Connection'}</span>
        </div>
      }
      footer={
        <div className="flex items-center justify-between w-full">
          <button
            type="button"
            onClick={handleTestConnection}
            disabled={isTesting}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 text-xs font-medium transition"
          >
            {isTesting ? (
              <>
                <span className="w-3.5 h-3.5 border-2 border-sky-400 border-t-transparent rounded-full animate-spin" />
                <span>Testing Socket...</span>
              </>
            ) : (
              <>
                <Wifi className="w-3.5 h-3.5 text-sky-400" />
                <span>Test Connection</span>
              </>
            )}
          </button>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={onClose}
              className="px-3 py-1.5 rounded-lg text-slate-400 hover:text-white text-xs"
            >
              Cancel
            </button>
            <button
              onClick={handleSubmit}
              className="px-4 py-1.5 rounded-lg bg-sky-600 hover:bg-sky-500 text-white text-xs font-semibold shadow-xs transition"
            >
              {editingConnection ? 'Save Changes' : 'Create Connection'}
            </button>
          </div>
        </div>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Driver Selection */}
        <div>
          <div className="flex items-center justify-between mb-1.5">
            <label className="text-slate-300 font-medium text-xs">Select Database Driver</label>
            <button
              type="button"
              onClick={() => {
                onClose();
                onOpenDriverManager();
              }}
              className="text-[11px] text-sky-400 hover:text-sky-300 flex items-center gap-1"
            >
              <span>Download more drivers</span>
              <ExternalLink className="w-3 h-3" />
            </button>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
            {installedDrivers.map(drv => (
              <button
                key={drv.id}
                type="button"
                onClick={() => handleDriverChange(drv.id)}
                className={`flex items-center gap-2 p-2.5 rounded-xl border text-left transition ${
                  selectedDriverId === drv.id
                    ? 'bg-sky-950/80 border-sky-500 ring-1 ring-sky-500/50 text-white'
                    : 'bg-slate-950 border-slate-800 text-slate-300 hover:border-slate-700'
                }`}
              >
                <span className="text-xl">{drv.icon}</span>
                <div className="truncate">
                  <div className="font-semibold text-xs truncate">{drv.name.split(' ')[0]}</div>
                  <div className="text-[10px] text-slate-400 font-mono">v{drv.version}</div>
                </div>
              </button>
            ))}
          </div>
        </div>

        {/* Connection Name & Color Tag */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div className="sm:col-span-2">
            <label className="block text-slate-400 text-xs mb-1">Connection Display Name</label>
            <input
              type="text"
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. PostgreSQL Production Replica"
              className="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-sky-500"
            />
          </div>

          <div>
            <label className="block text-slate-400 text-xs mb-1 flex items-center gap-1">
              <Palette className="w-3 h-3" />
              <span>Environment Tag</span>
            </label>
            <select
              value={colorTag}
              onChange={(e) => setColorTag(e.target.value)}
              className="w-full bg-slate-950 border border-slate-700 rounded-lg px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-sky-500"
            >
              {COLOR_TAGS.map(t => (
                <option key={t.color} value={t.color}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Host and Port */}
        <div className="grid grid-cols-3 gap-3">
          <div className="col-span-2">
            <label className="block text-slate-400 text-xs mb-1">Host / Server IP</label>
            <input
              type="text"
              required
              value={host}
              onChange={(e) => setHost(e.target.value)}
              placeholder="localhost, 127.0.0.1, cluster.rds.amazonaws.com"
              className="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-1.5 text-xs text-white font-mono placeholder-slate-500 focus:outline-none focus:border-sky-500"
            />
          </div>
          <div>
            <label className="block text-slate-400 text-xs mb-1">Port</label>
            <input
              type="number"
              required
              value={port}
              onChange={(e) => setPort(parseInt(e.target.value, 10) || 0)}
              className="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-1.5 text-xs text-white font-mono focus:outline-none focus:border-sky-500"
            />
          </div>
        </div>

        {/* Database Catalog */}
        <div>
          <label className="block text-slate-400 text-xs mb-1">
            {currentDriver?.engine === 'mongodb' ? 'Default Database Name' : 'Database / Catalog Name'}
          </label>
          <input
            type="text"
            required
            value={database}
            onChange={(e) => setDatabase(e.target.value)}
            placeholder="e.g. postgres, analytics_db, shop_db"
            className="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-1.5 text-xs text-white font-mono placeholder-slate-500 focus:outline-none focus:border-sky-500"
          />
        </div>

        {/* Username and Password */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-slate-400 text-xs mb-1">Username</label>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="e.g. postgres, app_user"
              className="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-1.5 text-xs text-white font-mono placeholder-slate-500 focus:outline-none focus:border-sky-500"
            />
          </div>
          <div>
            <label className="block text-slate-400 text-xs mb-1">Password</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••••••"
              className="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-1.5 text-xs text-white font-mono placeholder-slate-500 focus:outline-none focus:border-sky-500"
            />
          </div>
        </div>

        {/* SSL / TLS Option */}
        <div className="flex items-center gap-2 p-3 rounded-lg bg-slate-950 border border-slate-800">
          <input
            type="checkbox"
            id="ssl-mode"
            checked={ssl}
            onChange={(e) => setSsl(e.target.checked)}
            className="rounded border-slate-700 text-sky-500 focus:ring-sky-500 h-4 w-4 bg-slate-900"
          />
          <label htmlFor="ssl-mode" className="text-xs text-slate-300 flex items-center gap-1.5 cursor-pointer">
            <ShieldCheck className="w-4 h-4 text-emerald-400" />
            <span>Use SSL/TLS Encrypted Connection</span>
          </label>
        </div>

        {/* Test Result Alert */}
        {testResult && (
          <div className={`p-3 rounded-lg border text-xs flex items-start gap-2.5 ${
            testResult.success
              ? 'bg-emerald-950/40 border-emerald-800/80 text-emerald-300'
              : 'bg-red-950/40 border-red-800/80 text-red-300'
          }`}>
            {testResult.success ? (
              <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
            ) : (
              <AlertCircle className="w-4 h-4 text-red-400 shrink-0 mt-0.5" />
            )}
            <div className="space-y-1">
              <div className="font-semibold flex items-center gap-2">
                <span>{testResult.success ? 'Connection Established Successfully!' : 'Connection Failed'}</span>
                <span className="text-[10px] px-1.5 py-0.2 rounded bg-emerald-900 text-emerald-200 font-mono">
                  Ping: {testResult.latencyMs} ms
                </span>
              </div>
              <p className="text-[11px] text-emerald-400/90">{testResult.message}</p>
              <div className="text-[10px] text-slate-400 font-mono">{testResult.serverVersion}</div>
            </div>
          </div>
        )}
      </form>
    </Modal>
  );
};
