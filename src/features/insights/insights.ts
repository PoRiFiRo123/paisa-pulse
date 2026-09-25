import { and, desc, eq, gte, isNull, lt } from 'drizzle-orm';

import { transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { topCategories } from '@/features/transactions/list';
import { periodSummary, type DateRange } from '@/features/transactions/queries';

export type MonthPoint = DateRange & { label: string; short: string; spent: number; received: number; net: number };

/** Spent / received per month, oldest first. */
export async function monthlyTotals(db: DB, months: (DateRange & { label: string; short: string })[]): Promise<MonthPoint[]> {
  const sums = await Promise.all(months.map((m) => periodSummary(db, m)));
  return months.map((m, i) => ({ ...m, ...sums[i] }));
}

/** Days of the period that have passed (at least 1), for a per-day average. */
export function daysElapsed(range: DateRange, now: number): number {
  const end = Math.min(now, range.end);
  return Math.max(1, Math.ceil((end - range.start) / 86_400_000));
}

/** Percentage change, or null when there's nothing to compare against. */
export function percentChange(current: number, previous: number): number | null {
  if (previous <= 0) return null;
  return Math.round(((current - previous) / previous) * 100);
}

export async function categoryBreakdown(db: DB, range: DateRange) {
  const rows = await topCategories(db, range, 50);
  const total = rows.reduce((s, r) => s + r.total, 0);
  return rows.map((r) => ({ ...r, share: total ? r.total / total : 0 }));
}

export async function biggestExpenses(db: DB, range: DateRange, limit = 5) {
  return db
    .select({ id: transactions.id, amount: transactions.amount, payee: transactions.payee, note: transactions.note, occurredAt: transactions.occurredAt, categoryId: transactions.categoryId })
    .from(transactions)
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.type, 'expense'),
        gte(transactions.occurredAt, range.start),
        lt(transactions.occurredAt, range.end),
      ),
    )
    .orderBy(desc(transactions.amount))
    .limit(limit);
}
