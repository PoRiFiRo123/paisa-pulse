import { format, isSameDay, isSameYear, subDays } from 'date-fns';

import type { TransactionType } from '@/db/schema';

import { formatINR, formatINRCompact } from './money';

/** Typographic minus, as in the designs ("−₹420"). */
export const MINUS = '−';

export function signedAmount(paise: number, kind: TransactionType): string {
  // No signs (user decision, Nov 2026): colour carries the direction (soft red expense, green income).
  void kind;
  return formatINR(paise, { decimals: 'auto', sign: 'never' });
}

/** Balance/net without a minus sign: "₹8,360" (callers colour it or add "due"). */
export function balance(paise: number, compact = false): string {
  return compact ? formatINRCompact(Math.abs(paise)) : formatINR(Math.abs(paise), { decimals: 'auto' });
}

/** Account balance: a card or account below zero reads "₹8,360 due". */
export function accountBalance(paise: number, compact = false): string {
  return balance(paise, compact) + (paise < 0 ? ' due' : '');
}

export function accountLabel(name: string | null | undefined, last4: string | null | undefined): string {
  if (!name) return '';
  return last4 ? `${name} ••${last4}` : name;
}

/** Row subtitle time: "1:24 PM" today, "Yesterday", "1 Sep", "1 Sep 2025". */
export function relativeWhen(ms: number, now: number = Date.now()): string {
  if (isSameDay(ms, now)) return format(ms, 'h:mm a');
  if (isSameDay(ms, subDays(now, 1))) return 'Yesterday';
  return isSameYear(ms, now) ? format(ms, 'd MMM') : format(ms, 'd MMM yyyy');
}

/** Activity day header: "TODAY", "YESTERDAY", "SAT, 20 SEP". */
export function dayHeader(ms: number, now: number = Date.now()): string {
  if (isSameDay(ms, now)) return 'Today';
  if (isSameDay(ms, subDays(now, 1))) return 'Yesterday';
  return isSameYear(ms, now) ? format(ms, 'EEE, d MMM') : format(ms, 'EEE, d MMM yyyy');
}

export function dateTimeLabel(ms: number, now: number = Date.now()): string {
  if (isSameDay(ms, now)) return `Today, ${format(ms, 'h:mm a')}`;
  if (isSameDay(ms, subDays(now, 1))) return `Yesterday, ${format(ms, 'h:mm a')}`;
  return format(ms, 'd MMM, h:mm a');
}
