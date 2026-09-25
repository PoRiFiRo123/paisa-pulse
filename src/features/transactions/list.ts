import { and, desc, eq, gte, inArray, isNull, like, lt, or, type SQL, sql } from 'drizzle-orm';
import { alias } from 'drizzle-orm/sqlite-core';

import { accounts, categories, type TransactionType, transactions } from '@/db/schema';
import type { DB } from '@/db/types';

import type { DateRange } from './queries';

const toAccounts = alias(accounts, 'to_accounts');
const parents = alias(categories, 'parent_categories');

export type TransactionFilters = {
  range?: DateRange;
  /** Matches either side of a transfer. */
  accountIds?: string[];
  /** A parent id also matches its subcategories. `null` in the list matches Uncategorised. */
  categoryIds?: (string | null)[];
  types?: TransactionType[];
  /** Free text on payee and note. */
  search?: string;
  id?: string;
  limit?: number;
};

/** A transaction with everything a row or the detail view shows. */
export async function listTransactions(db: DB, f: TransactionFilters = {}) {
  const where: (SQL | undefined)[] = [isNull(transactions.deletedAt)];
  if (f.id) where.push(eq(transactions.id, f.id));
  if (f.range) where.push(gte(transactions.occurredAt, f.range.start), lt(transactions.occurredAt, f.range.end));
  if (f.types?.length) where.push(inArray(transactions.type, f.types));
  if (f.accountIds?.length)
    where.push(or(inArray(transactions.accountId, f.accountIds), inArray(transactions.toAccountId, f.accountIds)));
  if (f.categoryIds?.length) {
    const ids = f.categoryIds.filter((c): c is string => c !== null);
    const parts: (SQL | undefined)[] = [];
    if (ids.length) parts.push(inArray(transactions.categoryId, ids), inArray(categories.parentId, ids));
    if (f.categoryIds.includes(null)) parts.push(and(isNull(transactions.categoryId), sql`${transactions.type} <> 'transfer'`));
    where.push(or(...parts));
  }
  const q = f.search?.trim();
  if (q) {
    const pattern = `%${q}%`;
    where.push(
      or(
        like(transactions.payee, pattern),
        like(transactions.note, pattern),
        like(categories.name, pattern),
      ),
    );
  }

  const query = db
    .select({
      id: transactions.id,
      type: transactions.type,
      amount: transactions.amount,
      payee: transactions.payee,
      note: transactions.note,
      occurredAt: transactions.occurredAt,
      createdAt: transactions.createdAt,
      updatedAt: transactions.updatedAt,
      source: transactions.source,
      recurringRuleId: transactions.recurringId,
      accountId: transactions.accountId,
      toAccountId: transactions.toAccountId,
      categoryId: transactions.categoryId,
      accountName: accounts.name,
      accountLast4: accounts.last4,
      accountColor: accounts.color,
      toAccountName: toAccounts.name,
      toAccountLast4: toAccounts.last4,
      categoryName: categories.name,
      categoryIcon: categories.icon,
      categoryColor: categories.color,
      parentCategoryName: parents.name,
    })
    .from(transactions)
    .innerJoin(accounts, eq(accounts.id, transactions.accountId))
    .leftJoin(toAccounts, eq(toAccounts.id, transactions.toAccountId))
    .leftJoin(categories, eq(categories.id, transactions.categoryId))
    .leftJoin(parents, eq(parents.id, categories.parentId))
    .where(and(...where))
    .orderBy(desc(transactions.occurredAt), desc(transactions.id));
  return f.limit ? query.limit(f.limit) : query;
}

export type TransactionItem = Awaited<ReturnType<typeof listTransactions>>[number];

/** Expense totals for a period rolled up to top-level categories, largest first. */
export async function topCategories(db: DB, range: DateRange, limit = 8) {
  const topId = sql<string | null>`coalesce(${categories.parentId}, ${categories.id})`;
  const rows = await db
    .select({
      categoryId: topId.as('top_id'),
      total: sql<number>`sum(${transactions.amount})`.mapWith(Number).as('total'),
    })
    .from(transactions)
    .leftJoin(categories, eq(categories.id, transactions.categoryId))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.type, 'expense'),
        gte(transactions.occurredAt, range.start),
        lt(transactions.occurredAt, range.end),
      ),
    )
    .groupBy(sql`top_id`)
    .orderBy(desc(sql`total`))
    .limit(limit);

  const ids = rows.map((r) => r.categoryId).filter((id): id is string => id !== null);
  const cats = ids.length ? await db.select().from(categories).where(inArray(categories.id, ids)) : [];
  const byId = new Map(cats.map((c) => [c.id, c]));
  return rows.map((r) => ({ ...r, category: r.categoryId ? (byId.get(r.categoryId) ?? null) : null }));
}

/** Categories most recently used for a kind, for the Quick Add chips. */
export async function recentCategoryIds(db: DB, kind: 'expense' | 'income', limit = 6): Promise<string[]> {
  const rows = await db
    .select({ id: transactions.categoryId, last: sql<number>`max(${transactions.occurredAt})`.as('last') })
    .from(transactions)
    .where(and(eq(transactions.type, kind), isNull(transactions.deletedAt), sql`${transactions.categoryId} is not null`))
    .groupBy(transactions.categoryId)
    .orderBy(desc(sql`last`))
    .limit(limit);
  return rows.map((r) => r.id!).filter(Boolean);
}
