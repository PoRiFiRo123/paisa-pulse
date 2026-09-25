import { startOfDay } from 'date-fns';

import type { DB } from '@/db/types';
import { budgetProgress } from '@/features/budgets/budgets';
import { topCategories } from '@/features/transactions/list';
import { periodSummary } from '@/features/transactions/queries';
import { formatINR, formatINRCompact } from '@/lib/money';
import { monthAt } from '@/lib/months';

/** Everything a home/lock screen widget shows, pre-formatted (widgets can't run our formatters). */
export type WidgetSnapshot = {
  version: 1;
  month: string;
  spent: string;
  spentCompact: string;
  today: string;
  income: string;
  /** Overall budget, if set. */
  budget: { label: string; ratio: number; over: boolean } | null;
  top: { name: string; amount: string; color: string; icon: string }[];
  hidden: boolean;
  updatedAt: number;
};

const MASK = '₹••••';

export async function buildWidgetSnapshot(
  db: DB,
  { now = Date.now(), monthStartDay = 1, hideAmounts = false } = {},
): Promise<WidgetSnapshot> {
  const month = monthAt(0, monthStartDay, now);
  const todayStart = startOfDay(now).getTime();
  const [summary, today, budgets, top] = await Promise.all([
    periodSummary(db, month),
    periodSummary(db, { start: todayStart, end: todayStart + 86_400_000 }),
    budgetProgress(db, month, now),
    topCategories(db, month, 3),
  ]);
  const fmt = (p: number) => (hideAmounts ? MASK : formatINR(p, { decimals: 'auto' }));
  const overall = budgets.find((b) => b.category === null);
  return {
    version: 1,
    month: month.name,
    spent: fmt(summary.spent),
    spentCompact: hideAmounts ? MASK : formatINRCompact(summary.spent),
    today: fmt(today.spent),
    income: fmt(summary.received),
    budget: overall
      ? {
          label: hideAmounts
            ? 'Budget'
            : overall.remaining >= 0
              ? `${formatINR(overall.remaining, { decimals: 'auto' })} left`
              : `${formatINR(-overall.remaining, { decimals: 'auto' })} over`,
          ratio: Math.min(overall.ratio, 1),
          over: overall.ratio > 1,
        }
      : null,
    top: top.map((t) => ({
      name: t.category?.name ?? 'Uncategorised',
      amount: fmt(t.total),
      color: t.category?.color ?? '#8E8E93',
      icon: t.category?.icon ?? 'questionmark',
    })),
    hidden: hideAmounts,
    updatedAt: now,
  };
}
