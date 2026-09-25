import { useCallback } from 'react';

import type { TransactionType } from '@/db/schema';
import { balance, signedAmount } from '@/lib/format';
import { formatINR } from '@/lib/money';
import { usePrefs } from '@/stores/prefs';

const MASK = '₹••••';

/** Amount formatters that respect the "Hide amounts" privacy setting. */
export function useMoney() {
  const hidden = usePrefs((s) => s.hideAmounts);
  return {
    hidden,
    amount: useCallback((p: number) => (hidden ? MASK : formatINR(p, { decimals: 'auto' })), [hidden]),
    signed: useCallback((p: number, kind: TransactionType) => (hidden ? MASK : signedAmount(p, kind)), [hidden]),
    balance: useCallback((p: number, compact?: boolean) => (hidden ? MASK : balance(p, compact)), [hidden]),
  };
}
