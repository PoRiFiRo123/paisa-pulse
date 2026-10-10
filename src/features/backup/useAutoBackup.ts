import { useEffect } from 'react';
import { AppState } from 'react-native';

import { appDb } from '@/db/client';

import { runAutoBackupIfDue } from './auto';
import { preferredStore } from './stores';

/** Runs a scheduled backup shortly after launch, on foreground and when the app is backgrounded. */
export function useAutoBackup() {
  useEffect(() => {
    const run = () => preferredStore().then((store) => runAutoBackupIfDue(appDb, store)).catch(() => {});
    // Let launch work (recurring, widgets) settle first.
    const t = setTimeout(run, 4000);
    const sub = AppState.addEventListener('change', (s) => (s === 'background' || s === 'active') && run());
    return () => {
      clearTimeout(t);
      sub.remove();
    };
  }, []);
}
