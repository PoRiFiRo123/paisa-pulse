import { addDays, addMonths, format, startOfDay, startOfMonth, startOfWeek } from 'date-fns';
import { and, gte, isNull, lt } from 'drizzle-orm';

import { transactions } from '@/db/schema';
import type { DB } from '@/db/types';

export type DayTotals = { spent: number; received: number; count: number };

export const dayKey = (ms: number) => format(ms, 'yyyy-MM-dd');

/** Spent / received per local day for [start, end). Transfers don't count, but are included in `count`. */
export async function dailyTotals(db: DB, range: { start: number; end: number }): Promise<Map<string, DayTotals>> {
  const rows = await db
    .select({ type: transactions.type, amount: transactions.amount, occurredAt: transactions.occurredAt })
    .from(transactions)
    .where(and(isNull(transactions.deletedAt), gte(transactions.occurredAt, range.start), lt(transactions.occurredAt, range.end)));
  const out = new Map<string, DayTotals>();
  for (const r of rows) {
    const key = dayKey(r.occurredAt);
    const d = out.get(key) ?? { spent: 0, received: 0, count: 0 };
    if (r.type === 'expense') d.spent += r.amount;
    else if (r.type === 'income') d.received += r.amount;
    d.count++;
    out.set(key, d);
  }
  return out;
}

export type CalendarCell = { key: string; date: number; inMonth: boolean };

/** A month grid of whole weeks (5 or 6 rows), starting on `weekStartDay`. */
export function monthGrid(month: number, weekStartDay: 0 | 1): { start: number; end: number; cells: CalendarCell[] } {
  const first = startOfMonth(month);
  const next = addMonths(first, 1);
  let day = startOfWeek(first, { weekStartsOn: weekStartDay });
  const cells: CalendarCell[] = [];
  while (day < next || cells.length % 7 !== 0) {
    const date = startOfDay(day).getTime();
    cells.push({ key: dayKey(date), date, inMonth: day >= first && day < next });
    day = addDays(day, 1);
  }
  return { start: first.getTime(), end: next.getTime(), cells };
}

/** 0–1 heat for a day's spending relative to the month's busiest day (square-root scale so small days still show). */
export function heat(spent: number, max: number): number {
  if (spent <= 0 || max <= 0) return 0;
  return Math.sqrt(spent / max);
}
