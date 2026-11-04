import React from 'react';
import { WifiOff } from 'lucide-react';
import { useOnlineStatus } from '../../hooks/useOnlineStatus';

export const OfflineIndicator: React.FC = () => {
  const isOnline = useOnlineStatus();

  if (isOnline) return null;

  return (
    <div className="fixed bottom-4 left-4 z-50 flex items-center gap-2 rounded-lg bg-amber-500/95 px-3 py-1.5 text-xs font-semibold text-slate-950 shadow-xl backdrop-blur-sm border border-amber-400">
      <WifiOff className="w-3.5 h-3.5 text-slate-950 animate-pulse" />
      <span>Offline Mode — Running with cached drivers and schemas</span>
    </div>
  );
};
