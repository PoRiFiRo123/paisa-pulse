import { and, inArray, isNotNull } from 'drizzle-orm';

import { transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { createTransaction } from '@/features/transactions/mutations';

import { type CaptureContext, displayName, findAccount, guessCategory } from './drafts';

/** Mirrors `PendingEntry` in targets/intents/Shared.swift. */
export type PendingEntry = {
  id: string;
  kind: 'expense' | 'income';
  /** Rupees. */
  amount: number;
  payee: string | null;
  note: string | null;
  account: string | null;
  category: string | null;
  /** Epoch seconds. */
  at: number;
  source: 'siri' | 'wallet';
};

export const PENDING_KEY = 'pendingCaptures';

export function parsePending(json: string | null): PendingEntry[] {
  if (!json) return [];
  try {
    const list = JSON.parse(json) as unknown;
    return Array.isArray(list) ? list.filter((e): e is PendingEntry => typeof e?.id === 'string' && typeof e?.amount === 'number') : [];
  } catch {
    return [];
  }
}

/**
 * Add entries logged from Siri, Shortcuts or a Wallet automation. Each is added once (its id is
 * kept in `external_id`), so a crash between adding and clearing the queue can't double-add.
 * Returns the ids of new transactions and of every entry handled (to remove from the queue).
 */
export async function ingestPending(db: DB, entries: PendingEntry[], ctx: CaptureContext): Promise<{ added: string[]; handled: string[] }> {
  if (!entries.length) return { added: [], handled: [] };
  const keys = entries.map((e) => `shortcut:${e.id}`);
  const seen = new Set(
    (await db.select({ k: transactions.externalId }).from(transactions).where(and(isNotNull(transactions.externalId), inArray(transactions.externalId, keys)))).map(
      (r) => r.k,
    ),
  );
  const added: string[] = [];
  const handled: string[] = [];
  for (const e of entries) {
    handled.push(e.id);
    const paise = Math.round(e.amount * 100);
    if (seen.has(`shortcut:${e.id}`) || !Number.isSafeInteger(paise) || paise <= 0) continue;
    const account = (e.account ? findAccount(e.account, ctx.accounts)?.account : undefined) ?? ctx.accounts.find((a) => a.id === ctx.defaultAccountId) ?? ctx.accounts[0];
    if (!account) continue;
    const payee = e.payee?.trim() ? displayName(e.payee.trim()) : null;
    const named = e.category ? ctx.categories.find((c) => c.kind === e.kind && c.name.toLowerCase() === e.category!.toLowerCase())?.id : undefined;
    const t = await createTransaction(
      db,
      {
        type: e.kind === 'income' ? 'income' : 'expense',
        amount: paise,
        accountId: account.id,
        categoryId: named ?? guessCategory(e.payee ?? '', payee, e.kind, ctx),
        payee,
        note: e.note,
        occurredAt: Math.min(Math.round(e.at * 1000), ctx.now),
      },
      ctx.now,
      { source: 'shortcut', externalId: `shortcut:${e.id}` },
    );
    added.push(t.id);
  }
  return { added, handled };
}
