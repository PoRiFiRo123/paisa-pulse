import { and, desc, eq, gte, isNull, lt, sql } from 'drizzle-orm';

import { transactions } from '@/db/schema';
import type { DB } from '@/db/types';

export type DateRange = { start: number; end: number };

const notDeleted = isNull(transactions.deletedAt);

/** Live transactions in [start, end), newest first. Usable with Drizzle's `useLiveQuery`. */
export function transactionsInRange(db: DB, range: DateRange) {
  return db
    .select()
    .from(transactions)
    .where(and(notDeleted, gte(transactions.occurredAt, range.start), lt(transactions.occurredAt, range.end)))
    .orderBy(desc(transactions.occurredAt), desc(transactions.id));
}

export function recentTransactions(db: DB, limit = 5) {
  return db
    .select()
    .from(transactions)
    .where(notDeleted)
    .orderBy(desc(transactions.occurredAt), desc(transactions.id))
    .limit(limit);
}

export function transactionById(db: DB, id: string) {
  return db.select().from(transactions).where(eq(transactions.id, id));
}

export type MonthSummary = { spent: number; received: number; net: number };

/**
 * Spent / received / net for a period, in paise. Transfers (including credit card
 * bill payments) move money between your own accounts, so they are excluded.
 */
export async function periodSummary(db: DB, range: DateRange): Promise<MonthSummary> {
  const row = await db
    .select({
      spent: sql<number>`coalesce(sum(case when ${transactions.type} = 'expense' then ${transactions.amount} end), 0)`,
      received: sql<number>`coalesce(sum(case when ${transactions.type} = 'income' then ${transactions.amount} end), 0)`,
    })
    .from(transactions)
    .where(and(notDeleted, gte(transactions.occurredAt, range.start), lt(transactions.occurredAt, range.end)))
    .get();
  const spent = Number(row?.spent ?? 0);
  const received = Number(row?.received ?? 0);
  return { spent, received, net: received - spent };
}

/** Expense totals per category for a period, largest first. `categoryId` null = Uncategorised. */
export function spendingByCategory(db: DB, range: DateRange) {
  return db
    .select({
      categoryId: transactions.categoryId,
      total: sql<number>`sum(${transactions.amount})`.as('total'),
    })
    .from(transactions)
    .where(
      and(
        notDeleted,
        eq(transactions.type, 'expense'),
        gte(transactions.occurredAt, range.start),
        lt(transactions.occurredAt, range.end),
      ),
    )
    .groupBy(transactions.categoryId)
    .orderBy(desc(sql`total`));
}
