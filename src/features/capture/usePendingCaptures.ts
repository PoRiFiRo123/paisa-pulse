import { useEffect } from 'react';
import { AppState, Platform } from 'react-native';

import { appDb } from '@/db/client';
import { accountsWithBalance } from '@/features/accounts/queries';
import { categoriesByKind } from '@/features/categories/queries';
import { APP_GROUP } from '@/features/widgets/publish';
import { HAS_CUSTOM_NATIVE } from '@/lib/native';
import { usePrefs } from '@/stores/prefs';
import { useToast } from '@/stores/toast';

import { learnedCategories, undoCommit } from './commit';
import { ingestPending, parsePending, PENDING_KEY } from './pending';

/** Adds expenses logged through Siri, Shortcuts or Wallet automations (iOS) at launch and on foreground. */
export function usePendingCaptures() {
  useEffect(() => {
    if (Platform.OS !== 'ios' || !HAS_CUSTOM_NATIVE) return;
    // eslint-disable-next-line @typescript-eslint/no-require-imports -- lazy: absent in Expo Go
    const { ExtensionStorage } = require('@bacons/apple-targets') as typeof import('@bacons/apple-targets');
    const storage = new ExtensionStorage(APP_GROUP);
    let running = false;

    const run = async () => {
      if (running) return;
      const entries = parsePending(storage.get(PENDING_KEY));
      if (!entries.length) return;
      running = true;
      try {
        const [accounts, expense, income, learned] = await Promise.all([
          accountsWithBalance(appDb),
          categoriesByKind(appDb, 'expense'),
          categoriesByKind(appDb, 'income'),
          learnedCategories(appDb),
        ]);
        const lastAccountId = usePrefs.getState().lastAccountId;
        const { added, handled } = await ingestPending(appDb, entries, {
          accounts,
          categories: [...expense, ...income],
          learned,
          defaultAccountId: accounts.find((a) => a.id === lastAccountId)?.id ?? accounts[0]?.id ?? null,
          now: Date.now(),
        });
        // The extension may have queued more meanwhile: remove only what was handled.
        const rest = parsePending(storage.get(PENDING_KEY)).filter((e) => !handled.includes(e.id));
        if (rest.length) storage.set(PENDING_KEY, JSON.stringify(rest));
        else storage.remove(PENDING_KEY);
        if (added.length) {
          useToast.getState().show({
            message: added.length === 1 ? 'Added 1 transaction from Siri' : `Added ${added.length} transactions from Siri & Shortcuts`,
            actionLabel: 'Undo',
            onAction: () => undoCommit(appDb, added),
          });
        }
      } catch (e) {
        console.warn('pending captures failed', e);
      } finally {
        running = false;
      }
    };

    run();
    const sub = AppState.addEventListener('change', (s) => s === 'active' && run());
    return () => sub.remove();
  }, []);
}
