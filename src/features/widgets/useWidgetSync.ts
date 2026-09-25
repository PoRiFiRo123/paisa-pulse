import { addDatabaseChangeListener } from 'expo-sqlite';
import { useEffect } from 'react';
import { AppState } from 'react-native';

import { appDb } from '@/db/client';
import { HAS_CUSTOM_NATIVE } from '@/lib/native';
import { usePrefs } from '@/stores/prefs';

import { publishWidgets } from './publish';
import { buildWidgetSnapshot } from './snapshot';

/** Keep widgets fresh: after data changes (debounced), when privacy/month settings change, and on backgrounding. */
export function useWidgetSync() {
  const hideAmounts = usePrefs((s) => s.hideAmounts);
  const monthStartDay = usePrefs((s) => s.monthStartDay);

  useEffect(() => {
    // Widgets need native extensions, which exist only in development/store builds.
    if (!HAS_CUSTOM_NATIVE) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const sync = () =>
      buildWidgetSnapshot(appDb, { hideAmounts, monthStartDay })
        .then(publishWidgets)
        .catch((e) => console.warn('widget sync failed', e));
    const schedule = () => {
      clearTimeout(timer);
      timer = setTimeout(sync, 1500);
    };
    sync();
    const db = addDatabaseChangeListener(schedule);
    const app = AppState.addEventListener('change', (s) => s === 'background' && sync());
    return () => {
      clearTimeout(timer);
      db.remove();
      app.remove();
    };
  }, [hideAmounts, monthStartDay]);
}
