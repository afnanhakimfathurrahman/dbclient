import React, { useState } from 'react';
import { 
  HardDriveDownload, 
  CheckCircle2, 
  Search, 
  Layers, 
  Plus, 
  ExternalLink, 
  Terminal, 
  Database,
  Trash2
} from 'lucide-react';
import { Modal } from '../common/Modal';
import { DriverInfo, DatabaseEngine } from '../../types/db';

interface DriverManagerModalProps {
  isOpen: boolean;
  onClose: () => void;
  drivers: DriverInfo[];
  onUpdateDrivers: (drivers: DriverInfo[]) => void;
  onSelectDriverToConnect?: (driver: DriverInfo) => void;
}

export const DriverManagerModal: React.FC<DriverManagerModalProps> = ({
  isOpen,
  onClose,
  drivers,
  onUpdateDrivers,
  onSelectDriverToConnect,
}) => {
  const [search, setSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string>('ALL');
  const [downloadingId, setDownloadingId] = useState<string | null>(null);
  const [downloadProgress, setDownloadProgress] = useState<number>(0);
  const [isAddingCustom, setIsAddingCustom] = useState(false);

  // Form for custom driver
  const [customName, setCustomName] = useState('');
  const [customEngine, setCustomEngine] = useState<DatabaseEngine>('custom');
  const [customClass, setCustomClass] = useState('');
  const [customPort, setCustomPort] = useState('5000');
  const [customCategory, setCustomCategory] = useState<'SQL' | 'NoSQL' | 'Analytical'>('SQL');
  const [customDesc, setCustomDesc] = useState('');
  const [customSampleUrl, setCustomSampleUrl] = useState('jdbc:custom://localhost:5000/db');

  const categories = ['ALL', 'SQL', 'NoSQL', 'Analytical', 'Key-Value'];

  const filtered = drivers.filter(d => {
    const matchesSearch = d.name.toLowerCase().includes(search.toLowerCase()) || 
                          d.engine.toLowerCase().includes(search.toLowerCase()) ||
                          d.driverClass.toLowerCase().includes(search.toLowerCase());
    const matchesCategory = selectedCategory === 'ALL' || d.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  const handleDownload = (driverId: string) => {
    setDownloadingId(driverId);
    setDownloadProgress(15);

    const interval = setInterval(() => {
      setDownloadProgress(prev => {
        if (prev >= 90) {
          clearInterval(interval);
          setTimeout(() => {
            const updated = drivers.map(d => 
              d.id === driverId ? { ...d, isInstalled: true } : d
            );
            onUpdateDrivers(updated);
            setDownloadingId(null);
            setDownloadProgress(0);
          }, 300);
          return 100;
        }
        return prev + 25;
      });
    }, 180);
  };

  const handleUninstall = (driverId: string) => {
    const target = drivers.find(d => d.id === driverId);
    if (target?.isBuiltIn) {
      alert('Built-in default drivers (PostgreSQL, MongoDB, ClickHouse) cannot be removed.');
      return;
    }
    const updated = drivers.map(d => 
      d.id === driverId ? { ...d, isInstalled: false } : d
    );
    onUpdateDrivers(updated);
  };

  const handleAddCustomDriver = (e: React.FormEvent) => {
    e.preventDefault();
    if (!customName || !customClass) return;

    const newDriver: DriverInfo = {
      id: `driver-custom-${Date.now()}`,
      name: customName,
      engine: customEngine,
      version: '1.0.0',
      category: customCategory,
      defaultPort: parseInt(customPort, 10) || 5000,
      driverClass: customClass,
      fileSize: '5.2 MB',
      isInstalled: true,
      isBuiltIn: false,
      description: customDesc || 'User configured custom JDBC/network database driver.',
      icon: '🔧',
      sampleUrl: customSampleUrl,
      docUrl: 'https://dbeaver.io/docs/wiki/Database-drivers/',
    };

    onUpdateDrivers([...drivers, newDriver]);
    setIsAddingCustom(false);
    setCustomName('');
    setCustomClass('');
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      maxWidth="max-w-4xl"
      title={
        <div className="flex items-center gap-2">
          <Layers className="w-4 h-4 text-sky-400" />
          <span>Database Driver Manager & Extensions</span>
          <span className="text-xs px-2 py-0.5 rounded-full bg-sky-950 text-sky-400 border border-sky-800">
            {drivers.filter(d => d.isInstalled).length} Installed
          </span>
        </div>
      }
    >
      <div className="space-y-4">
        {/* Controls bar */}
        <div className="flex flex-col sm:flex-row gap-3 items-stretch sm:items-center justify-between">
          {/* Search */}
          <div className="relative flex-1">
            <Search className="w-3.5 h-3.5 absolute left-3 top-2.5 text-slate-400" />
            <input
              type="text"
              placeholder="Search drivers (PostgreSQL, MySQL, Redis, Snowflake...)"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full bg-slate-950 border border-slate-700 rounded-lg pl-9 pr-3 py-1.5 text-xs text-slate-200 placeholder-slate-500 focus:outline-none focus:border-sky-500"
            />
          </div>

          {/* Categories */}
          <div className="flex items-center gap-1 bg-slate-950 p-1 rounded-lg border border-slate-800 text-[11px]">
            {categories.map(cat => (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                className={`px-2.5 py-1 rounded transition ${
                  selectedCategory === cat 
                    ? 'bg-sky-600 text-white font-medium shadow-xs' 
                    : 'text-slate-400 hover:text-slate-200'
                }`}
              >
                {cat}
              </button>
            ))}
          </div>

          {/* Add custom driver button */}
          <button
            onClick={() => setIsAddingCustom(true)}
            className="flex items-center justify-center gap-1.5 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg border border-slate-700 text-xs font-medium transition"
          >
            <Plus className="w-3.5 h-3.5 text-emerald-400" />
            <span>Add Driver</span>
          </button>
        </div>

        {/* Custom Driver Form Drawer */}
        {isAddingCustom && (
          <form onSubmit={handleAddCustomDriver} className="p-4 rounded-xl bg-slate-950 border border-sky-700/50 space-y-3">
            <div className="flex items-center justify-between pb-2 border-b border-slate-800">
              <span className="font-semibold text-sky-400 text-xs flex items-center gap-1.5">
                <Database className="w-3.5 h-3.5" />
                Register New Custom JDBC Driver
              </span>
              <button 
                type="button" 
                onClick={() => setIsAddingCustom(false)}
                className="text-slate-400 hover:text-white text-xs"
              >
                Cancel
              </button>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
              <div>
                <label className="block text-slate-400 mb-1">Driver Name</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. MariaDB Connector / Presto"
                  value={customName}
                  onChange={(e) => setCustomName(e.target.value)}
                  className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200"
                />
              </div>

              <div>
                <label className="block text-slate-400 mb-1">Driver Java Class</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. org.mariadb.jdbc.Driver"
                  value={customClass}
                  onChange={(e) => setCustomClass(e.target.value)}
                  className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200 font-mono text-[11px]"
                />
              </div>

              <div>
                <label className="block text-slate-400 mb-1">Default Port</label>
                <input
                  type="number"
                  placeholder="3306"
                  value={customPort}
                  onChange={(e) => setCustomPort(e.target.value)}
                  className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200"
                />
              </div>

              <div>
                <label className="block text-slate-400 mb-1">Category</label>
                <select
                  value={customCategory}
                  onChange={(e) => setCustomCategory(e.target.value as any)}
                  className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200"
                >
                  <option value="SQL">SQL Relational</option>
                  <option value="NoSQL">NoSQL Document</option>
                  <option value="Analytical">Analytical OLAP</option>
                </select>
              </div>

              <div className="sm:col-span-2">
                <label className="block text-slate-400 mb-1">Sample URL Template</label>
                <input
                  type="text"
                  value={customSampleUrl}
                  onChange={(e) => setCustomSampleUrl(e.target.value)}
                  className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200 font-mono text-[11px]"
                />
              </div>
            </div>

            <div className="flex justify-end gap-2 pt-2">
              <button
                type="submit"
                className="px-4 py-1.5 bg-sky-600 hover:bg-sky-500 text-white rounded text-xs font-semibold"
              >
                Save & Install Driver
              </button>
            </div>
          </form>
        )}

        {/* Drivers Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3 max-h-[55vh] overflow-y-auto pr-1">
          {filtered.map(driver => (
            <div
              key={driver.id}
              className={`p-3.5 rounded-xl border transition flex flex-col justify-between ${
                driver.isInstalled 
                  ? 'bg-slate-950/70 border-slate-800 hover:border-slate-700' 
                  : 'bg-slate-950/30 border-slate-800/60 opacity-90 hover:opacity-100 hover:border-slate-700'
              }`}
            >
              <div>
                {/* Driver Card Header */}
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-center gap-2.5">
                    <span className="text-2xl p-1.5 rounded-lg bg-slate-900 border border-slate-800">
                      {driver.icon}
                    </span>
                    <div>
                      <div className="flex items-center gap-1.5">
                        <span className="font-semibold text-slate-100 text-xs">{driver.name}</span>
                        {driver.isBuiltIn && (
                          <span className="text-[10px] px-1.5 py-0.2 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30 font-medium">
                            Core Default
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-2 text-[11px] text-slate-400 mt-0.5">
                        <span className="font-mono text-slate-400">v{driver.version}</span>
                        <span>•</span>
                        <span className="text-sky-400">{driver.category}</span>
                        <span>•</span>
                        <span>{driver.fileSize}</span>
                      </div>
                    </div>
                  </div>

                  {driver.isInstalled ? (
                    <span className="flex items-center gap-1 text-[11px] text-emerald-400 font-medium bg-emerald-950/60 px-2 py-0.5 rounded border border-emerald-800/60">
                      <CheckCircle2 className="w-3 h-3 text-emerald-400" />
                      Installed
                    </span>
                  ) : (
                    <span className="text-[11px] text-slate-400 bg-slate-800/80 px-2 py-0.5 rounded">
                      Available
                    </span>
                  )}
                </div>

                {/* Description */}
                <p className="mt-2.5 text-[11px] text-slate-300 line-clamp-2 leading-relaxed">
                  {driver.description}
                </p>

                {/* Details */}
                <div className="mt-3 p-2 rounded bg-slate-900/80 border border-slate-800/80 space-y-1 font-mono text-[10px] text-slate-400">
                  <div className="flex items-center gap-1 truncate">
                    <Terminal className="w-3 h-3 text-slate-400 shrink-0" />
                    <span className="text-slate-400 select-all">{driver.driverClass}</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Default Port: <strong className="text-slate-300 font-sans">{driver.defaultPort || 'N/A (Embedded)'}</strong></span>
                    {driver.docUrl && (
                      <a
                        href={driver.docUrl}
                        target="_blank"
                        rel="noreferrer"
                        className="text-sky-400 hover:text-sky-300 flex items-center gap-1"
                      >
                        Docs <ExternalLink className="w-2.5 h-2.5" />
                      </a>
                    )}
                  </div>
                </div>
              </div>

              {/* Action buttons */}
              <div className="mt-3 pt-2.5 border-t border-slate-900 flex items-center justify-between gap-2">
                {driver.isInstalled ? (
                  <>
                    <button
                      onClick={() => {
                        onClose();
                        if (onSelectDriverToConnect) onSelectDriverToConnect(driver);
                      }}
                      className="flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg bg-sky-600/90 hover:bg-sky-500 text-white font-medium text-xs transition"
                    >
                      <Plus className="w-3.5 h-3.5" />
                      Create Connection
                    </button>

                    {!driver.isBuiltIn && (
                      <button
                        onClick={() => handleUninstall(driver.id)}
                        className="p-1.5 text-slate-400 hover:text-red-400 hover:bg-red-950/30 rounded border border-transparent hover:border-red-900/50 transition"
                        title="Uninstall Driver"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </>
                ) : (
                  <button
                    onClick={() => handleDownload(driver.id)}
                    disabled={downloadingId === driver.id}
                    className="w-full flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-sky-300 font-medium text-xs border border-slate-700 hover:border-sky-500/50 transition"
                  >
                    {downloadingId === driver.id ? (
                      <div className="flex items-center gap-2">
                        <span className="w-3.5 h-3.5 border-2 border-sky-400 border-t-transparent rounded-full animate-spin" />
                        <span>Downloading driver ({downloadProgress}%)...</span>
                      </div>
                    ) : (
                      <>
                        <HardDriveDownload className="w-3.5 h-3.5 text-sky-400" />
                        <span>Download & Install Driver</span>
                      </>
                    )}
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </Modal>
  );
};
