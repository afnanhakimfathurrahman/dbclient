import React, { useState } from 'react';
import { 
  Download, 
  Copy, 
  Check, 
  FileSpreadsheet, 
  FileCode, 
  FileText, 
  Eye, 
  Settings2 
} from 'lucide-react';
import { Modal } from '../common/Modal';
import { ExportFormat, ExportOptions } from '../../types/db';
import { QueryEngine } from '../../services/queryEngine';

interface ExportModalProps {
  isOpen: boolean;
  onClose: () => void;
  tableName: string;
  columns: string[];
  rows: Record<string, any>[];
}

export const ExportModal: React.FC<ExportModalProps> = ({
  isOpen,
  onClose,
  tableName,
  columns,
  rows,
}) => {
  const [format, setFormat] = useState<ExportFormat>('CSV');
  const [delimiter, setDelimiter] = useState<string>(',');
  const [includeHeaders, setIncludeHeaders] = useState<boolean>(true);
  const [quoteStrings, setQuoteStrings] = useState<boolean>(true);
  const [copied, setCopied] = useState<boolean>(false);

  const options: ExportOptions = {
    format,
    includeHeaders,
    delimiter,
    tableName: tableName || 'exported_data',
    selectedOnly: false,
    quoteStrings,
  };

  // Preview snippet (first 4 rows)
  const previewRows = rows.slice(0, 4);
  const previewText = QueryEngine.formatExport(columns, previewRows, options);

  const handleDownload = () => {
    const fullText = QueryEngine.formatExport(columns, rows, options);
    let ext = 'csv';
    let mime = 'text/csv';

    if (format === 'JSON') {
      ext = 'json';
      mime = 'application/json';
    } else if (format === 'SQL') {
      ext = 'sql';
      mime = 'application/sql';
    } else if (format === 'MARKDOWN') {
      ext = 'md';
      mime = 'text/markdown';
    } else if (format === 'TSV') {
      ext = 'tsv';
      mime = 'text/tab-separated-values';
    } else if (format === 'HTML') {
      ext = 'html';
      mime = 'text/html';
    }

    const filename = `${tableName || 'export'}_${new Date().toISOString().slice(0, 10)}.${ext}`;
    QueryEngine.downloadFile(fullText, filename, mime);
    onClose();
  };

  const handleCopy = () => {
    const fullText = QueryEngine.formatExport(columns, rows, options);
    navigator.clipboard.writeText(fullText).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  const formats: { id: ExportFormat; label: string; icon: React.ReactNode; desc: string }[] = [
    { id: 'CSV', label: 'CSV File', icon: <FileSpreadsheet className="w-4 h-4 text-emerald-400" />, desc: 'Standard comma-separated format' },
    { id: 'JSON', label: 'JSON Document', icon: <FileCode className="w-4 h-4 text-amber-400" />, desc: 'Structured JSON objects array' },
    { id: 'SQL', label: 'SQL INSERT Statements', icon: <FileCode className="w-4 h-4 text-sky-400" />, desc: 'Ready-to-execute INSERT queries' },
    { id: 'MARKDOWN', label: 'Markdown Table', icon: <FileText className="w-4 h-4 text-purple-400" />, desc: 'GitHub-flavored markdown tables' },
    { id: 'TSV', label: 'TSV / Excel', icon: <FileSpreadsheet className="w-4 h-4 text-teal-400" />, desc: 'Tab-separated for spreadsheet paste' },
    { id: 'HTML', label: 'HTML Table', icon: <FileText className="w-4 h-4 text-rose-400" />, desc: 'Self-contained <table> markup' },
  ];

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      maxWidth="max-w-2xl"
      title={
        <div className="flex items-center gap-2">
          <Download className="w-4 h-4 text-sky-400" />
          <span>Export Data Wizard — {tableName || 'Query Results'}</span>
          <span className="text-[11px] px-2 py-0.5 rounded bg-slate-800 text-slate-300">
            {rows.length} records • {columns.length} columns
          </span>
        </div>
      }
      footer={
        <div className="flex items-center justify-between w-full">
          <button
            type="button"
            onClick={handleCopy}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-medium border border-slate-700 transition"
          >
            {copied ? (
              <>
                <Check className="w-3.5 h-3.5 text-emerald-400" />
                <span className="text-emerald-400">Copied to Clipboard!</span>
              </>
            ) : (
              <>
                <Copy className="w-3.5 h-3.5" />
                <span>Copy to Clipboard</span>
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
              onClick={handleDownload}
              className="flex items-center gap-1.5 px-4 py-1.5 rounded-lg bg-sky-600 hover:bg-sky-500 text-white text-xs font-semibold shadow-xs transition"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Download File ({format})</span>
            </button>
          </div>
        </div>
      }
    >
      <div className="space-y-4">
        {/* Format Selector */}
        <div>
          <label className="block text-slate-300 font-medium text-xs mb-2">Target Export Format</label>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
            {formats.map(fmt => (
              <button
                key={fmt.id}
                type="button"
                onClick={() => setFormat(fmt.id)}
                className={`flex flex-col p-2.5 rounded-xl border text-left transition ${
                  format === fmt.id
                    ? 'bg-sky-950/80 border-sky-500 ring-1 ring-sky-500/50 text-white'
                    : 'bg-slate-950 border-slate-800 text-slate-300 hover:border-slate-700'
                }`}
              >
                <div className="flex items-center gap-2 font-medium text-xs">
                  {fmt.icon}
                  <span>{fmt.label}</span>
                </div>
                <span className="text-[10px] text-slate-400 mt-1 truncate">{fmt.desc}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Options based on format */}
        {(format === 'CSV' || format === 'TSV' || format === 'SQL') && (
          <div className="p-3 rounded-xl bg-slate-950 border border-slate-800 space-y-2.5">
            <div className="flex items-center gap-2 text-xs font-semibold text-slate-300">
              <Settings2 className="w-3.5 h-3.5 text-sky-400" />
              <span>Format Settings</span>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 text-xs">
              {format === 'CSV' && (
                <div>
                  <label className="block text-slate-400 mb-1 text-[11px]">Delimiter</label>
                  <select
                    value={delimiter}
                    onChange={(e) => setDelimiter(e.target.value)}
                    className="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-slate-200"
                  >
                    <option value=",">Comma (,)</option>
                    <option value=";">Semicolon (;)</option>
                    <option value="|">Pipe (|)</option>
                    <option value="&#9;">Tab (\t)</option>
                  </select>
                </div>
              )}

              <div className="flex items-center gap-2 pt-4">
                <input
                  type="checkbox"
                  id="include-headers"
                  checked={includeHeaders}
                  onChange={(e) => setIncludeHeaders(e.target.checked)}
                  className="rounded border-slate-700 text-sky-500 focus:ring-sky-500 h-4 w-4 bg-slate-900"
                />
                <label htmlFor="include-headers" className="text-slate-300 cursor-pointer text-xs">
                  Include Headers Row
                </label>
              </div>

              {format === 'CSV' && (
                <div className="flex items-center gap-2 pt-4">
                  <input
                    type="checkbox"
                    id="quote-strings"
                    checked={quoteStrings}
                    onChange={(e) => setQuoteStrings(e.target.checked)}
                    className="rounded border-slate-700 text-sky-500 focus:ring-sky-500 h-4 w-4 bg-slate-900"
                  />
                  <label htmlFor="quote-strings" className="text-slate-300 cursor-pointer text-xs">
                    Quote All Strings
                  </label>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Live Preview */}
        <div>
          <div className="flex items-center justify-between mb-1.5">
            <span className="text-slate-400 text-xs flex items-center gap-1">
              <Eye className="w-3 h-3 text-slate-400" />
              <span>Preview (First {previewRows.length} Rows)</span>
            </span>
            <span className="text-[10px] text-slate-400 font-mono">
              Total export: {rows.length} items
            </span>
          </div>
          <pre className="p-3 rounded-xl bg-slate-950 border border-slate-800 text-[11px] font-mono text-slate-300 overflow-x-auto max-h-40 leading-relaxed">
            {previewText || '// No data to preview'}
          </pre>
        </div>
      </div>
    </Modal>
  );
};
