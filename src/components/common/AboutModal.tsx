import React from 'react';
import { Database, Split, Layers, Download, ShieldCheck, CheckCircle2 } from 'lucide-react';
import { Modal } from './Modal';

interface AboutModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const AboutModal: React.FC<AboutModalProps> = ({ isOpen, onClose }) => {
  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      maxWidth="max-w-2xl"
      title={
        <div className="flex items-center gap-2">
          <Database className="w-4 h-4 text-sky-400" />
          <span>About DBeaver Web — Desktop-Grade Database Client</span>
        </div>
      }
    >
      <div className="space-y-4 text-xs text-slate-300 leading-relaxed">
        <div className="p-4 rounded-xl bg-gradient-to-r from-sky-950/60 to-slate-900 border border-sky-800/60 flex items-start gap-3">
          <div className="w-10 h-10 rounded-xl bg-sky-500/20 border border-sky-500/40 flex items-center justify-center shrink-0">
            <Database className="w-5 h-5 text-sky-400" />
          </div>
          <div>
            <h4 className="font-semibold text-white text-sm">DBeaver Web Multi-Database IDE</h4>
            <p className="text-slate-400 mt-1">
              Cross-platform progressive web application (PWA) with full offline support designed for developers, DBAs, and data engineers.
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-2">
          <div className="p-3 rounded-xl bg-slate-950 border border-slate-800 space-y-1.5">
            <div className="font-semibold text-slate-100 flex items-center gap-1.5">
              <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
              <span>Default Core Capabilities</span>
            </div>
            <ul className="space-y-1 text-slate-400 text-[11px]">
              <li>• <strong>PostgreSQL</strong>: Schemas, Heap tables, B-Tree/GIN, Range partitions, FKs.</li>
              <li>• <strong>MongoDB</strong>: Replica sets, Collections, TTL/Text indexes, BSON queries.</li>
              <li>• <strong>ClickHouse</strong>: MergeTree, Codecs (ZSTD), Monthly partition keys.</li>
            </ul>
          </div>

          <div className="p-3 rounded-xl bg-slate-950 border border-slate-800 space-y-1.5">
            <div className="font-semibold text-slate-100 flex items-center gap-1.5">
              <Layers className="w-3.5 h-3.5 text-sky-400" />
              <span>Extensible Driver Marketplace</span>
            </div>
            <p className="text-slate-400 text-[11px]">
              Extend client capabilities by downloading drivers for MySQL, SQLite, Redis, Snowflake, DuckDB, Cassandra, SQL Server, Oracle, or registering custom JDBC drivers.
            </p>
          </div>

          <div className="p-3 rounded-xl bg-slate-950 border border-slate-800 space-y-1.5">
            <div className="font-semibold text-slate-100 flex items-center gap-1.5">
              <Split className="w-3.5 h-3.5 text-amber-400" />
              <span>Deep Object Inspector</span>
            </div>
            <p className="text-slate-400 text-[11px]">
              View tables, schemas, indexes, partitions, constraints, live DDL generation, and interactive Entity-Relationship (ER) schema diagrams.
            </p>
          </div>

          <div className="p-3 rounded-xl bg-slate-950 border border-slate-800 space-y-1.5">
            <div className="font-semibold text-slate-100 flex items-center gap-1.5">
              <Download className="w-3.5 h-3.5 text-purple-400" />
              <span>Data Export & Offline PWA</span>
            </div>
            <p className="text-slate-400 text-[11px]">
              Export data directly to CSV, JSON, SQL INSERT statements, Markdown, Excel/TSV, and HTML. Install on desktop or mobile for 100% offline workflow.
            </p>
          </div>
        </div>

        <div className="p-3 rounded-xl bg-slate-950 border border-slate-800 text-[11px] text-slate-400 font-mono">
          <span>Shortcuts: </span>
          <kbd className="px-1.5 py-0.5 rounded bg-slate-800 text-slate-200">Ctrl + Enter</kbd> Run Query •{' '}
          <kbd className="px-1.5 py-0.5 rounded bg-slate-800 text-slate-200">Esc</kbd> Close Dialogs •{' '}
          <kbd className="px-1.5 py-0.5 rounded bg-slate-800 text-slate-200">Double Click</kbd> Inspect Table Cell
        </div>
      </div>
    </Modal>
  );
};
