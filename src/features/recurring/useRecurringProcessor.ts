import { useEffect } from 'react';
import { AppState } from 'react-native';

import { appDb } from '@/db/client';
import { useToast } from '@/stores/toast';

import { processDueRecurring } from './recurring';

/** Adds due recurring transactions at launch and whenever the app comes back to the foreground. */
export function useRecurringProcessor() {
  useEffect(() => {
    const run = () =>
      processDueRecurring(appDb)
        .then((n) => {
          if (n) useToast.getState().show({ message: `Added ${n} recurring transaction${n === 1 ? '' : 's'}` });
        })
        .catch((e) => console.warn('recurring failed', e));
    run();
    const sub = AppState.addEventListener('change', (s) => s === 'active' && run());
    return () => sub.remove();
  }, []);
}
