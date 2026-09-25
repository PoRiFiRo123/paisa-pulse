import { and, desc, eq, gte, inArray, isNull, lte, or, sql } from 'drizzle-orm';

import { type Account, accounts, categories, type Category, importBatches, type TransactionType, transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { newId } from '@/lib/ids';
import { createTransaction } from '@/features/transactions/mutations';

import { type Narration, parseNarration, suggestCategoryName } from './narration';
import type { StatementRow } from './parse';

export type RowStatus = 'new' | 'duplicate' | 'possible-duplicate';

/** One statement row with everything the review screen shows and the user can change. */
export type PlannedRow = {
  key: string;
  row: StatementRow;
  narration: Narration;
  type: TransactionType;
  /** The other side of a transfer (null for expense/income). */
  otherAccountId: string | null;
  categoryId: string | null;
  payee: string | null;
  note: string | null;
  status: RowStatus;
  duplicateOf: string | null;
  include: boolean;
  /** Short explanation shown under the row, e.g. "Paid your Axis MyZone card". */
  hint: string | null;
};

/** 64-bit FNV-1a as hex: a stable fingerprint for a statement row (sync, no crypto needed). */
export function fingerprint(text: string): string {
  let h1 = 0x811c9dc5;
  let h2 = 0xcbf29ce4;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 0x01000193) >>> 0;
    h2 = Math.imul(h2 ^ c, 0x01000193 ^ 0x5bd1e995) >>> 0;
  }
  return h1.toString(16).padStart(8, '0') + h2.toString(16).padStart(8, '0');
}

const ymd = (ms: number) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
};
const dayIndex = (ms: number) => Math.floor(new Date(ms).setHours(12, 0, 0, 0) / 86_400_000);

/** Stable ids for rows; identical rows in one file get #2, #3… so both import. */
export function rowKeys(accountId: string, rows: StatementRow[]): string[] {
  const seen = new Map<string, number>();
  return rows.map((r) => {
    const base = fingerprint(
      [accountId, ymd(r.date), r.direction, r.amount, r.description.toLowerCase().replace(/\s+/g, ' '), r.reference, r.balance ?? ''].join('|'),
    );
    const n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    return n === 1 ? base : `${base}#${n}`;
  });
}

/** Another of your accounts mentioned in the narration (by last 4 digits or name). */
function mentionedAccount(text: string, account: Account, all: Account[]): Account | undefined {
  const t = text.toLowerCase();
  return all.find(
    (a) =>
      a.id !== account.id &&
      ((a.last4 && new RegExp(`(x|\\*|\\b)${a.last4}\\b`, 'i').test(text)) || (a.name.length > 5 && t.includes(a.name.toLowerCase()))),
  );
}

async function historyCategories(db: DB, payees: string[]): Promise<Map<string, string>> {
  const unique = [...new Set(payees.map((p) => p.toLowerCase()))];
  if (!unique.length) return new Map();
  const rows = await db
    .select({
      payee: sql<string>`lower(${transactions.payee})`.as('p'),
      categoryId: transactions.categoryId,
      n: sql<number>`count(*)`.mapWith(Number).as('n'),
    })
    .from(transactions)
    .where(and(isNull(transactions.deletedAt), sql`lower(${transactions.payee}) in ${unique}`, sql`${transactions.categoryId} is not null`))
    .groupBy(sql`p`, transactions.categoryId)
    .orderBy(desc(sql`n`));
  const out = new Map<string, string>();
  for (const r of rows) if (!out.has(r.payee) && r.categoryId) out.set(r.payee, r.categoryId);
  return out;
}

/**
 * Turn statement rows into reviewable transactions for `accountId`: types, transfers,
 * payees, categories and duplicate status. Nothing is written.
 */
export async function planImport(db: DB, accountId: string, rows: StatementRow[]): Promise<PlannedRow[]> {
  const all = await db.select().from(accounts).where(isNull(accounts.archivedAt));
  const account = all.find((a) => a.id === accountId) ?? (await db.select().from(accounts).where(eq(accounts.id, accountId)).get());
  if (!account) throw new Error('Account not found');
  const cats: Category[] = await db.select().from(categories).where(isNull(categories.archivedAt));
  const byName = (name: string, kind: 'expense' | 'income') => cats.find((c) => c.kind === kind && c.name === name)?.id ?? null;
  const cards = all.filter((a) => a.type === 'card' && a.id !== account.id);
  const banks = all.filter((a) => a.type === 'bank' && a.id !== account.id);
  const cash = all.find((a) => a.type === 'cash' && a.id !== account.id);

  const narrations = rows.map((r) => parseNarration(r.description));
  const learned = await historyCategories(db, narrations.map((n) => n.payee).filter((p): p is string => Boolean(p)));
  const keys = rowKeys(account.id, rows);

  const planned: PlannedRow[] = rows.map((row, i) => {
    const n = narrations[i];
    let type: TransactionType = row.direction === 'out' ? 'expense' : 'income';
    let other: Account | undefined;
    let hint: string | null = null;
    let include = true;

    const mentioned = mentionedAccount(row.description, account, all);
    if (n.channel === 'CARD_PAYMENT') {
      if (account.type === 'card' && row.direction === 'in') {
        other = mentioned ?? banks[0];
        hint = other ? `Card bill paid from ${other.name}` : 'Card bill payment: add your bank account to pair it';
        if (!other) include = false;
      } else if (row.direction === 'out') {
        other = cards.find((c) => c.last4 && row.description.includes(c.last4)) ?? mentioned ?? (cards.length === 1 ? cards[0] : cards[0]);
        hint = other ? `Paid your ${other.name} bill` : null;
      }
    } else if (n.channel === 'ATM' && row.direction === 'out' && cash) {
      other = cash;
      hint = 'Cash withdrawal → Cash';
    } else if (mentioned && account.type !== 'card') {
      other = mentioned;
      hint = row.direction === 'out' ? `Moved to ${mentioned.name}` : `Moved from ${mentioned.name}`;
    }
    if (other) type = 'transfer';

    let categoryId: string | null = null;
    if (type !== 'transfer') {
      const kind = type === 'income' ? 'income' : 'expense';
      const fromHistory = n.payee ? learned.get(n.payee.toLowerCase()) : undefined;
      const historyCat = fromHistory ? cats.find((c) => c.id === fromHistory && c.kind === kind)?.id : undefined;
      const ruleName = suggestCategoryName(row.description, n.payee, row.direction);
      categoryId = historyCat ?? (ruleName ? byName(ruleName, kind) : null);
    }
    return {
      key: keys[i],
      row,
      narration: n,
      type,
      otherAccountId: other?.id ?? null,
      categoryId,
      payee: n.payee,
      note: n.note,
      status: 'new',
      duplicateOf: null,
      include,
      hint,
    };
  });

  // Exact re-import: same fingerprint already stored.
  const existingKeys = new Set(
    (
      await db
        .select({ key: transactions.externalId })
        .from(transactions)
        .where(and(isNull(transactions.deletedAt), inArray(transactions.externalId, keys)))
    ).map((r) => r.key),
  );
  for (const p of planned) {
    if (existingKeys.has(p.key)) {
      p.status = 'duplicate';
      p.include = false;
      p.hint = 'Already imported';
    }
  }

  // Likely duplicates of entries you added by hand (or from the other side of a transfer):
  // same account, amount and direction within a day. Each existing entry matches once.
  if (rows.length) {
    const dates = rows.map((r) => r.date);
    const from = Math.min(...dates) - 2 * 86_400_000;
    const to = Math.max(...dates) + 2 * 86_400_000;
    const candidates = await db
      .select()
      .from(transactions)
      .where(
        and(
          isNull(transactions.deletedAt),
          gte(transactions.occurredAt, from),
          lte(transactions.occurredAt, to),
          or(eq(transactions.accountId, account.id), eq(transactions.toAccountId, account.id)),
        ),
      );
    const used = new Set<string>();
    for (const p of planned) {
      if (p.status !== 'new') continue;
      let best: { id: string; d: number } | null = null;
      for (const t of candidates) {
        if (used.has(t.id) || t.amount !== p.row.amount) continue;
        const outOfThis = t.accountId === account.id && t.type !== 'income';
        const direction = outOfThis ? 'out' : 'in';
        if (direction !== p.row.direction) continue;
        const d = Math.abs(dayIndex(t.occurredAt) - dayIndex(p.row.date));
        if (d <= 1 && (!best || d < best.d)) best = { id: t.id, d };
      }
      if (best) {
        used.add(best.id);
        p.status = 'possible-duplicate';
        p.duplicateOf = best.id;
        p.include = false;
        p.hint = 'Looks like one you already added';
      }
    }
  }
  return planned;
}

/** Write the included rows as one import batch. Returns the batch id and count. */
export async function commitImport(
  db: DB,
  { accountId, fileName, template, rows }: { accountId: string; fileName: string; template: string | null; rows: PlannedRow[] },
  now: number = Date.now(),
): Promise<{ batchId: string; count: number }> {
  const chosen = rows.filter((r) => r.include);
  const batchId = newId();
  await db.insert(importBatches).values({ id: batchId, accountId, fileName, template, count: chosen.length, createdAt: now, undoneAt: null });
  for (const r of chosen) {
    const transfer = r.type === 'transfer' && r.otherAccountId;
    const intoThis = r.row.direction === 'in';
    await createTransaction(
      db,
      {
        type: transfer ? 'transfer' : r.type === 'transfer' ? (intoThis ? 'income' : 'expense') : r.type,
        amount: r.row.amount,
        accountId: transfer && intoThis ? r.otherAccountId! : accountId,
        toAccountId: transfer ? (intoThis ? accountId : r.otherAccountId) : null,
        categoryId: transfer ? null : r.categoryId,
        payee: r.payee,
        note: r.note,
        occurredAt: r.row.date,
      },
      now,
      { source: 'import', importBatchId: batchId, externalId: r.key },
    );
  }
  return { batchId, count: chosen.length };
}

/** Undo a whole import (soft delete, so it can be restored). */
export async function undoImport(db: DB, batchId: string, now: number = Date.now()) {
  await db
    .update(transactions)
    .set({ deletedAt: now, updatedAt: now })
    .where(and(eq(transactions.importBatchId, batchId), isNull(transactions.deletedAt)));
  await db.update(importBatches).set({ undoneAt: now }).where(eq(importBatches.id, batchId));
}

export async function restoreImport(db: DB, batchId: string, now: number = Date.now()) {
  const batch = await db.select().from(importBatches).where(eq(importBatches.id, batchId)).get();
  if (!batch?.undoneAt) return;
  await db
    .update(transactions)
    .set({ deletedAt: null, updatedAt: now })
    .where(and(eq(transactions.importBatchId, batchId), eq(transactions.deletedAt, batch.undoneAt)));
  await db.update(importBatches).set({ undoneAt: null }).where(eq(importBatches.id, batchId));
}

export function listImportBatches(db: DB) {
  return db
    .select({ batch: importBatches, accountName: accounts.name })
    .from(importBatches)
    .innerJoin(accounts, eq(accounts.id, importBatches.accountId))
    .orderBy(desc(importBatches.createdAt))
    .limit(20);
}
