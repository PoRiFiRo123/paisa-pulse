import { format, isSameDay, isSameYear, subDays } from 'date-fns';

import type { TransactionType } from '@/db/schema';

import { formatINR, formatINRCompact } from './money';

/** Typographic minus, as in the designs ("−₹420"). */
export const MINUS = '−';

export function signedAmount(paise: number, kind: TransactionType): string {
  const body = formatINR(paise, { decimals: 'auto', sign: 'never' });
  if (kind === 'expense') return MINUS + body;
  if (kind === 'income') return '+' + body;
  return body;
}

/** Signed balance/net: "−₹8,360" / "₹1,82,450". */
export function balance(paise: number, compact = false): string {
  const body = compact ? formatINRCompact(Math.abs(paise)) : formatINR(Math.abs(paise), { decimals: 'auto' });
  return paise < 0 ? MINUS + body : body;
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
