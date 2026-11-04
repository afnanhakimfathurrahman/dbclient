import React from 'react';
import { 
  Database, 
  Plus, 
  Code2, 
  Layers, 
  History, 
  Download, 
  Sparkles, 
  ChevronDown, 
  HardDriveDownload,
  Info
} from 'lucide-react';
import { ConnectionConfig, DriverInfo } from '../../types/db';
import { PWAInstallButton } from '../common/PWAInstallButton';
import { useOnlineStatus } from '../../hooks/useOnlineStatus';

interface TopBarProps {
  connections: ConnectionConfig[];
  activeConnection: ConnectionConfig;
  drivers: DriverInfo[];
  onSelectConnection: (id: string) => void;
  onNewConnection: () => void;
  onNewQuery: () => void;
  onOpenDriverManager: () => void;
  onOpenHistory: () => void;
  onOpenExport: () => void;
  onOpenAbout: () => void;
}

export const TopBar: React.FC<TopBarProps> = ({
  connections,
  activeConnection,
  drivers,
  onSelectConnection,
  onNewConnection,
  onNewQuery,
  onOpenDriverManager,
  onOpenHistory,
  onOpenExport,
  onOpenAbout,
}) => {
  const isOnline = useOnlineStatus();
  const installedCount = drivers.filter(d => d.isInstalled).length;

  return (
    <header className="h-12 bg-slate-950 border-b border-slate-800 px-3 flex items-center justify-between text-xs select-none shrink-0 z-20">
      {/* Brand & Connection Dropdown */}
      <div className="flex items-center gap-3">
        {/* App Logo */}
        <div className="flex items-center gap-2 cursor-pointer hover:opacity-90 transition">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-tr from-sky-600 via-sky-500 to-amber-400 flex items-center justify-center shadow-xs">
            <Database className="w-4 h-4 text-slate-950 stroke-[2.5]" />
          </div>
          <div className="hidden sm:flex flex-col">
            <span className="font-bold text-white tracking-wide text-xs flex items-center gap-1.5">
              <span>DBeaver Web</span>
              <span className="text-[10px] font-mono px-1 py-0.2 rounded bg-sky-950 text-sky-400 border border-sky-800">
                PRO
              </span>
            </span>
            <span className="text-[9px] text-slate-400 font-mono -mt-0.5">
              Multi-DB Client IDE
            </span>
          </div>
        </div>

        <div className="h-4 w-px bg-slate-800 mx-1" />

        {/* Connection Switcher */}
        <div className="relative flex items-center">
          <select
            value={activeConnection.id}
            onChange={(e) => onSelectConnection(e.target.value)}
            className="bg-slate-900 border border-slate-700/80 rounded-lg pl-3 pr-8 py-1 text-xs text-white font-medium focus:outline-none focus:border-sky-500 cursor-pointer max-w-[200px] sm:max-w-[280px] truncate"
          >
            {connections.map(conn => (
              <option key={conn.id} value={conn.id}>
                {conn.name} ({conn.database})
              </option>
            ))}
          </select>
          <ChevronDown className="w-3.5 h-3.5 text-slate-400 absolute right-2 pointer-events-none" />
        </div>

        {/* Quick New Connection Button */}
        <button
          onClick={onNewConnection}
          className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition"
          title="New Database Connection"
        >
          <Plus className="w-4 h-4 text-emerald-400" />
        </button>
      </div>

      {/* Main Action Buttons */}
      <div className="flex items-center gap-2">
        {/* New SQL Query */}
        <button
          onClick={onNewQuery}
          className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-900 hover:bg-slate-800 text-slate-200 border border-slate-700/80 font-medium transition active:scale-95"
          title="Open New SQL Editor Script"
        >
          <Code2 className="w-3.5 h-3.5 text-sky-400" />
          <span className="hidden md:inline">SQL Editor</span>
        </button>

        {/* Driver Manager */}
        <button
          onClick={onOpenDriverManager}
          className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-900 hover:bg-slate-800 text-slate-200 border border-slate-700/80 font-medium transition"
          title="Manage & Download Database Drivers"
        >
          <Layers className="w-3.5 h-3.5 text-amber-400" />
          <span className="hidden md:inline">Drivers</span>
          <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-slate-800 text-slate-300 font-mono">
            {installedCount}
          </span>
        </button>

        {/* Query History */}
        <button
          onClick={onOpenHistory}
          className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-900 hover:bg-slate-800 text-slate-200 border border-slate-700/80 font-medium transition"
          title="View Query History"
        >
          <History className="w-3.5 h-3.5 text-purple-400" />
          <span className="hidden lg:inline">History</span>
        </button>

        {/* Export Data */}
        <button
          onClick={onOpenExport}
          className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-900 hover:bg-slate-800 text-slate-200 border border-slate-700/80 font-medium transition"
          title="Export Data Wizard"
        >
          <Download className="w-3.5 h-3.5 text-teal-400" />
          <span className="hidden lg:inline">Export</span>
        </button>

        <div className="h-4 w-px bg-slate-800 mx-1 hidden sm:block" />

        {/* Online / Offline status badge */}
        <div className="hidden sm:flex items-center gap-1.5 px-2 py-0.5 rounded text-[10px] font-mono border border-slate-800 bg-slate-900">
          <span className={`w-1.5 h-1.5 rounded-full ${isOnline ? 'bg-emerald-400' : 'bg-amber-400 animate-pulse'}`} />
          <span className="text-slate-400">{isOnline ? 'Online' : 'Offline Mode'}</span>
        </div>

        {/* PWA In-App Install Button */}
        <PWAInstallButton />

        {/* About Dialog */}
        <button
          onClick={onOpenAbout}
          className="p-1.5 rounded text-slate-400 hover:text-white hover:bg-slate-800 transition"
          title="About DBeaver Web"
        >
          <Info className="w-4 h-4" />
        </button>
      </div>
    </header>
  );
};
