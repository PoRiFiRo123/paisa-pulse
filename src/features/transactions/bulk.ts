import { and, eq, inArray, isNull, ne, or } from 'drizzle-orm';

import { categories, transactions } from '@/db/schema';
import type { DB } from '@/db/types';

/** The fields a bulk edit can change, captured so the edit can be undone. */
export type BulkSnapshot = { id: string; accountId: string; categoryId: string | null; deletedAt: number | null }[];

async function snapshot(db: DB, ids: readonly string[]): Promise<BulkSnapshot> {
  if (!ids.length) return [];
  return db
    .select({
      id: transactions.id,
      accountId: transactions.accountId,
      categoryId: transactions.categoryId,
      deletedAt: transactions.deletedAt,
    })
    .from(transactions)
    .where(inArray(transactions.id, [...ids]));
}

/** Put rows back exactly as they were before a bulk edit. */
export async function restoreSnapshot(db: DB, rows: BulkSnapshot, now: number = Date.now()): Promise<void> {
  for (const r of rows) {
    await db
      .update(transactions)
      .set({ accountId: r.accountId, categoryId: r.categoryId, deletedAt: r.deletedAt, updatedAt: now })
      .where(eq(transactions.id, r.id));
  }
}

/**
 * Set the category on many transactions. Transfers are skipped, and so are rows whose
 * type doesn't match the category's kind (an income can't get an expense category).
 * Returns the snapshot to undo and how many rows changed.
 */
export async function bulkSetCategory(db: DB, ids: readonly string[], categoryId: string | null, now: number = Date.now()) {
  const before = await snapshot(db, ids);
  let kindFilter = ne(transactions.type, 'transfer');
  if (categoryId) {
    const cat = await db.select({ kind: categories.kind }).from(categories).where(eq(categories.id, categoryId)).get();
    if (!cat) throw new Error(`Category ${categoryId} not found`);
    kindFilter = eq(transactions.type, cat.kind);
  }
  const target = and(inArray(transactions.id, [...ids]), kindFilter);
  const changed = await db.select({ id: transactions.id }).from(transactions).where(target);
  if (changed.length) await db.update(transactions).set({ categoryId, updatedAt: now }).where(target);
  const changedIds = new Set(changed.map((c) => c.id));
  return { undo: before.filter((r) => changedIds.has(r.id)), count: changed.length };
}

/**
 * Move many transactions to another account. For transfers this changes the "from"
 * side, and is skipped where it would make a transfer into the same account.
 */
export async function bulkSetAccount(db: DB, ids: readonly string[], accountId: string, now: number = Date.now()) {
  const before = await snapshot(db, ids);
  const target = and(
    inArray(transactions.id, [...ids]),
    or(isNull(transactions.toAccountId), ne(transactions.toAccountId, accountId)),
  );
  const changed = await db.select({ id: transactions.id }).from(transactions).where(target);
  if (changed.length) await db.update(transactions).set({ accountId, updatedAt: now }).where(target);
  const changedIds = new Set(changed.map((c) => c.id));
  return { undo: before.filter((r) => changedIds.has(r.id)), count: changed.length };
}

/** Soft delete many transactions at once. */
export async function bulkDelete(db: DB, ids: readonly string[], now: number = Date.now()) {
  const before = await snapshot(db, ids);
  if (ids.length) await db.update(transactions).set({ deletedAt: now, updatedAt: now }).where(inArray(transactions.id, [...ids]));
  return { undo: before, count: before.length };
}
