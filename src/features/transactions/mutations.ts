import { and, eq, isNotNull, lt, ne } from 'drizzle-orm';

import { type Transaction, type TransactionSource, transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { DAY_MS } from '@/lib/dates';
import { newId } from '@/lib/ids';

import { assertValidTransaction, type TransactionInput } from './validation';

/** Soft-deleted rows are purged after this long (SPEC §4.1). */
export const PURGE_AFTER_MS = 30 * DAY_MS;

function clean(text: string | null | undefined): string | null {
  const trimmed = text?.trim();
  return trimmed ? trimmed : null;
}

function toRow(input: TransactionInput, now: number) {
  const isTransfer = input.type === 'transfer';
  return {
    type: input.type,
    amount: input.amount,
    accountId: input.accountId,
    toAccountId: isTransfer ? (input.toAccountId ?? null) : null,
    categoryId: isTransfer ? null : (input.categoryId ?? null),
    payee: clean(input.payee),
    note: clean(input.note),
    occurredAt: input.occurredAt ?? now,
  };
}

export async function createTransaction(
  db: DB,
  input: TransactionInput,
  now: number = Date.now(),
  origin: { source?: TransactionSource; recurringId?: string | null } = {},
): Promise<Transaction> {
  assertValidTransaction(input, now);
  const row = {
    id: newId(),
    ...toRow(input, now),
    source: origin.source ?? 'manual',
    recurringId: origin.recurringId ?? null,
    createdAt: now,
    updatedAt: now,
  };
  await db.insert(transactions).values(row);
  return { ...row, deletedAt: null };
}

/** Replace the editable fields of a transaction (the edit sheet always sends the full form). */
export async function updateTransaction(
  db: DB,
  id: string,
  input: TransactionInput,
  now: number = Date.now(),
): Promise<void> {
  assertValidTransaction(input, now);
  await db
    .update(transactions)
    .set({ ...toRow(input, now), updatedAt: now })
    .where(eq(transactions.id, id));
}

/** Soft delete. Pair with `restoreTransaction` for the Undo toast. */
export async function deleteTransaction(db: DB, id: string, now: number = Date.now()): Promise<void> {
  await db.update(transactions).set({ deletedAt: now, updatedAt: now }).where(eq(transactions.id, id));
}

export async function restoreTransaction(db: DB, id: string, now: number = Date.now()): Promise<void> {
  await db.update(transactions).set({ deletedAt: null, updatedAt: now }).where(eq(transactions.id, id));
}

/** Copy a transaction as a new manual entry dated now (e.g. today's coffee). */
export async function duplicateTransaction(db: DB, id: string, now: number = Date.now()): Promise<Transaction> {
  const original = await db.select().from(transactions).where(eq(transactions.id, id)).get();
  if (!original) throw new Error(`Transaction ${id} not found`);
  return createTransaction(db, { ...original, occurredAt: now }, now);
}

/** Permanently remove transactions soft-deleted more than 30 days ago. Returns how many. */
export async function purgeDeletedTransactions(db: DB, now: number = Date.now()): Promise<number> {
  const cutoff = now - PURGE_AFTER_MS;
  const where = and(isNotNull(transactions.deletedAt), lt(transactions.deletedAt, cutoff));
  const doomed = await db.select({ id: transactions.id }).from(transactions).where(where).all();
  if (doomed.length) await db.delete(transactions).where(where);
  return doomed.length;
}

/** Quick recategorise from a context menu. Transfers never have a category. */
export async function setTransactionCategory(db: DB, id: string, categoryId: string | null, now: number = Date.now()) {
  await db
    .update(transactions)
    .set({ categoryId, updatedAt: now })
    .where(and(eq(transactions.id, id), ne(transactions.type, 'transfer')));
}
