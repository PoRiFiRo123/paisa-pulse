import type { AccountType } from '@/db/schema';

export const ACCOUNT_TYPE_LABEL: Record<AccountType, string> = {
  bank: 'Savings',
  card: 'Credit Card',
  cash: 'Cash',
  wallet: 'Wallet',
};

export function accountIcon(type: AccountType): string {
  return { bank: 'building.columns.fill', card: 'creditcard.fill', cash: 'banknote.fill', wallet: 'wallet.bifold.fill' }[type];
}

/** Days until the next `day`-of-month, from `now` (0 = today). */
export function daysUntilDay(day: number, now: Date = new Date()): { days: number; date: Date } {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const clamp = (y: number, m: number) => Math.min(day, new Date(y, m + 1, 0).getDate());
  let target = new Date(today.getFullYear(), today.getMonth(), clamp(today.getFullYear(), today.getMonth()));
  if (target < today) {
    const y = today.getMonth() === 11 ? today.getFullYear() + 1 : today.getFullYear();
    const m = (today.getMonth() + 1) % 12;
    target = new Date(y, m, clamp(y, m));
  }
  return { days: Math.round((target.getTime() - today.getTime()) / 86_400_000), date: target };
}
