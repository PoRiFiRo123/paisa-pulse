import { eq, or, sql } from 'drizzle-orm';

import { type Account, type AccountType, accounts, importBatches, transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { newId } from '@/lib/ids';

export type AccountInput = {
  name: string;
  type: AccountType;
  institution?: string | null;
  last4?: string | null;
  /** Paise, signed (negative for a card with an outstanding amount). */
  openingBalance?: number;
  color: string;
  icon: string;
  creditLimit?: number | null;
  statementDay?: number | null;
  dueDay?: number | null;
  excludeFromTotals?: boolean;
};

export class AccountValidationError extends Error {
  name = 'AccountValidationError';
}

function toRow(input: AccountInput) {
  const name = input.name.trim();
  if (!name) throw new AccountValidationError('Account name is required');
  const last4 = input.last4?.trim() || null;
  if (last4 !== null && !/^\d{4}$/.test(last4)) throw new AccountValidationError('Last 4 digits must be 4 digits');
  const openingBalance = input.openingBalance ?? 0;
  if (!Number.isSafeInteger(openingBalance)) throw new AccountValidationError('Opening balance must be in paise');
  for (const day of [input.statementDay, input.dueDay]) {
    if (day != null && (!Number.isInteger(day) || day < 1 || day > 31))
      throw new AccountValidationError('Statement and due days must be 1–31');
  }
  const isCard = input.type === 'card';
  return {
    name,
    type: input.type,
    institution: input.institution?.trim() || null,
    last4,
    openingBalance,
    color: input.color,
    icon: input.icon,
    creditLimit: isCard ? (input.creditLimit ?? null) : null,
    statementDay: isCard ? (input.statementDay ?? null) : null,
    dueDay: isCard ? (input.dueDay ?? null) : null,
    excludeFromTotals: input.excludeFromTotals ?? false,
  };
}

export async function createAccount(db: DB, input: AccountInput, now: number = Date.now()): Promise<Account> {
  const last = await db
    .select({ max: sql<number | null>`max(${accounts.sortOrder})` })
    .from(accounts)
    .get();
  const row = {
    id: newId(),
    ...toRow(input),
    currency: 'INR',
    sortOrder: (last?.max ?? -1) + 1,
    archivedAt: null,
    createdAt: now,
    updatedAt: now,
  };
  await db.insert(accounts).values(row);
  return row;
}

export async function updateAccount(db: DB, id: string, input: AccountInput, now: number = Date.now()): Promise<void> {
  await db
    .update(accounts)
    .set({ ...toRow(input), updatedAt: now })
    .where(eq(accounts.id, id));
}

/** Persist a drag-to-reorder: `ids` in their new order. */
export async function reorderAccounts(db: DB, ids: readonly string[], now: number = Date.now()): Promise<void> {
  for (const [sortOrder, id] of ids.entries()) {
    await db.update(accounts).set({ sortOrder, updatedAt: now }).where(eq(accounts.id, id));
  }
}

export async function setAccountArchived(db: DB, id: string, archived: boolean, now: number = Date.now()) {
  await db
    .update(accounts)
    .set({ archivedAt: archived ? now : null, updatedAt: now })
    .where(eq(accounts.id, id));
}

/**
 * Delete an account, or archive it if any transaction (including soft-deleted ones
 * still inside the undo/purge window) references it. Returns what happened.
 */
export async function removeAccount(db: DB, id: string, now: number = Date.now()): Promise<'deleted' | 'archived'> {
  const used = await db
    .select({ id: transactions.id })
    .from(transactions)
    .where(or(eq(transactions.accountId, id), eq(transactions.toAccountId, id)))
    .limit(1)
    .get();
  if (used) {
    await setAccountArchived(db, id, true, now);
    return 'archived';
  }
  await db.delete(importBatches).where(eq(importBatches.accountId, id));
  await db.delete(accounts).where(eq(accounts.id, id));
  return 'deleted';
}
