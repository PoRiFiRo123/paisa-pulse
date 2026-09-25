import * as Haptics from 'expo-haptics';
import { router } from 'expo-router';
import { useMemo } from 'react';
import { Share } from 'react-native';

import { appDb } from '@/db/client';
import { signedAmount } from '@/lib/format';
import { useToast } from '@/stores/toast';
import { transactionSubtitle, transactionTitle } from '@/ui/TransactionRow';

import type { TransactionItem } from './list';
import { deleteTransaction, duplicateTransaction, restoreTransaction } from './mutations';

/** Shared actions for rows, swipe actions, context menus and the detail screen. */
export function useTransactionActions() {
  const toast = useToast((s) => s.show);
  return useMemo(
    () => ({
      open: (id: string) => router.push({ pathname: '/transaction/[id]', params: { id } }),
      edit: (id: string) => router.push({ pathname: '/add', params: { id } }),
      changeCategory: (id: string) => router.push({ pathname: '/pick-category', params: { id } }),
      remove: async (id: string) => {
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => {});
        await deleteTransaction(appDb, id);
        toast({ message: 'Transaction deleted', actionLabel: 'Undo', onAction: () => restoreTransaction(appDb, id) });
      },
      duplicate: async (id: string) => {
        const copy = await duplicateTransaction(appDb, id);
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
        toast({ message: 'Duplicated for today', actionLabel: 'Undo', onAction: () => deleteTransaction(appDb, copy.id) });
      },
      share: (t: TransactionItem) =>
        Share.share({
          message: `${transactionTitle(t)}: ${signedAmount(t.amount, t.type)}\n${transactionSubtitle(t)}${t.note ? `\n${t.note}` : ''}`,
        }).catch(() => {}),
    }),
    [toast],
  );
}
