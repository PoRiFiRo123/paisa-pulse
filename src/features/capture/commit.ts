import { and, desc, eq, isNotNull, isNull, sql } from 'drizzle-orm';

import { type TransactionSource, transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { createTransaction, deleteTransaction } from '@/features/transactions/mutations';

import type { CaptureDraft } from './drafts';

/** Add the ticked drafts. Returns the new ids (for one Undo that removes them all). */
export async function commitDrafts(db: DB, drafts: CaptureDraft[], source: TransactionSource, now: number = Date.now()): Promise<string[]> {
  const ids: string[] = [];
  for (const d of drafts.filter((x) => x.include)) {
    if (!d.accountId) continue;
    const t = await createTransaction(
      db,
      {
        type: d.type,
        amount: d.amount,
        accountId: d.accountId,
        toAccountId: d.type === 'transfer' ? d.toAccountId : null,
        categoryId: d.type === 'transfer' ? null : d.categoryId,
        payee: d.payee,
        note: d.note,
        occurredAt: d.occurredAt,
      },
      now,
      { source },
    );
    ids.push(t.id);
  }
  return ids;
}

export async function undoCommit(db: DB, ids: string[], now: number = Date.now()) {
  for (const id of ids) await deleteTransaction(db, id, now);
}

/** Lower-cased payee → its most used category, for guessing categories of new captures. */
export async function learnedCategories(db: DB): Promise<Map<string, string>> {
  const rows = await db
    .select({
      payee: sql<string>`lower(${transactions.payee})`.as('p'),
      categoryId: transactions.categoryId,
      n: sql<number>`count(*)`.mapWith(Number).as('n'),
    })
    .from(transactions)
    .where(and(isNull(transactions.deletedAt), isNotNull(transactions.payee), isNotNull(transactions.categoryId)))
    .groupBy(sql`p`, transactions.categoryId)
    .orderBy(desc(sql`n`))
    .limit(2000);
  const out = new Map<string, string>();
  for (const r of rows) if (!out.has(r.payee) && r.categoryId) out.set(r.payee, r.categoryId);
  return out;
}

/** True if a transaction with this amount already exists within a day of `at` (screenshot of something already logged). */
export async function looksLogged(db: DB, amount: number, at: number): Promise<boolean> {
  const rows = await db
    .select({ id: transactions.id })
    .from(transactions)
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.amount, amount),
        sql`abs(${transactions.occurredAt} - ${at}) <= ${86_400_000}`,
      ),
    )
    .limit(1);
  return rows.length > 0;
}

