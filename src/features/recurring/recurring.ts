import { addDays, addMonths, addWeeks, addYears } from 'date-fns';
import { and, asc, eq, isNull, lte } from 'drizzle-orm';

import { type RecurringFrequency, type RecurringRule, recurringRules, transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { newId } from '@/lib/ids';
import { createTransaction } from '@/features/transactions/mutations';
import { assertValidTransaction, type TransactionInput } from '@/features/transactions/validation';

export type RecurringInput = Omit<TransactionInput, 'occurredAt'> & {
  frequency: RecurringFrequency;
  interval?: number;
  startAt: number;
  endAt?: number | null;
};

/** Stop catching up after this many occurrences per rule per run (e.g. a daily rule after a long break). */
export const MAX_CATCH_UP = 60;

/**
 * The n-th occurrence (0 = start). Always computed from the start date so monthly rules
 * keep their day: a rule on the 31st falls on 28 Feb, then back on 31 Mar.
 */
export function occurrenceAt(rule: Pick<RecurringRule, 'startAt' | 'frequency' | 'interval'>, n: number): number {
  const step = n * rule.interval;
  const start = new Date(rule.startAt);
  switch (rule.frequency) {
    case 'daily':
      return addDays(start, step).getTime();
    case 'weekly':
      return addWeeks(start, step).getTime();
    case 'monthly':
      return addMonths(start, step).getTime();
    case 'yearly':
      return addYears(start, step).getTime();
  }
}

/** First occurrence strictly after `after`. */
export function occurrenceAfter(rule: Pick<RecurringRule, 'startAt' | 'frequency' | 'interval'>, after: number): number {
  if (after < rule.startAt) return rule.startAt;
  const approxDays = { daily: 1, weekly: 7, monthly: 28, yearly: 365 }[rule.frequency] * rule.interval;
  let n = Math.max(0, Math.floor((after - rule.startAt) / (approxDays * 86_400_000)) - 1);
  while (occurrenceAt(rule, n) <= after) n++;
  return occurrenceAt(rule, n);
}

function validate(input: RecurringInput) {
  assertValidTransaction({ ...input, occurredAt: undefined });
  if (!Number.isInteger(input.interval ?? 1) || (input.interval ?? 1) < 1) throw new Error('Repeat interval must be 1 or more');
  if (input.endAt != null && input.endAt < input.startAt) throw new Error('End date is before the start date');
}

function toRow(input: RecurringInput) {
  const transfer = input.type === 'transfer';
  return {
    type: input.type,
    amount: input.amount,
    accountId: input.accountId,
    toAccountId: transfer ? (input.toAccountId ?? null) : null,
    categoryId: transfer ? null : (input.categoryId ?? null),
    payee: input.payee?.trim() || null,
    note: input.note?.trim() || null,
    frequency: input.frequency,
    interval: input.interval ?? 1,
    startAt: input.startAt,
    endAt: input.endAt ?? null,
  };
}

/**
 * Create a rule. `firstAlreadyAdded` is for "Repeat…" on an existing transaction: that
 * transaction is the first occurrence, so scheduling starts at the next one.
 */
export async function createRecurring(db: DB, input: RecurringInput, { firstAlreadyAdded = false, now = Date.now() } = {}) {
  validate(input);
  const base = toRow(input);
  const row: RecurringRule = {
    id: newId(),
    ...base,
    nextAt: firstAlreadyAdded ? occurrenceAfter(base, base.startAt) : base.startAt,
    pausedAt: null,
    createdAt: now,
    updatedAt: now,
  };
  await db.insert(recurringRules).values(row);
  return row;
}

/** Edit a rule. Scheduling continues from the first occurrence after the last one added. */
export async function updateRecurring(db: DB, id: string, input: RecurringInput, now: number = Date.now()) {
  validate(input);
  const existing = await db.select().from(recurringRules).where(eq(recurringRules.id, id)).get();
  if (!existing) throw new Error('Recurring rule not found');
  const base = toRow(input);
  const last = await db
    .select({ at: transactions.occurredAt })
    .from(transactions)
    .where(eq(transactions.recurringId, id))
    .orderBy(asc(transactions.occurredAt))
    .all();
  const lastAt = last.length ? last[last.length - 1].at : null;
  const nextAt = lastAt === null ? base.startAt : occurrenceAfter(base, lastAt);
  await db.update(recurringRules).set({ ...base, nextAt, updatedAt: now }).where(eq(recurringRules.id, id));
}

export async function setRecurringPaused(db: DB, id: string, paused: boolean, now: number = Date.now()) {
  const rule = await db.select().from(recurringRules).where(eq(recurringRules.id, id)).get();
  if (!rule) return;
  // Resuming skips what was missed while paused instead of back-filling it.
  const nextAt = paused ? rule.nextAt : Math.max(rule.nextAt, occurrenceAfter(rule, now - 1));
  await db.update(recurringRules).set({ pausedAt: paused ? now : null, nextAt, updatedAt: now }).where(eq(recurringRules.id, id));
}

/** Delete a rule. Transactions it already added stay, just unlinked. */
export async function deleteRecurring(db: DB, id: string) {
  await db.update(transactions).set({ recurringId: null }).where(eq(transactions.recurringId, id));
  await db.delete(recurringRules).where(eq(recurringRules.id, id));
}

/**
 * Add every occurrence that is due (on or before `now`) as a real transaction.
 * Safe to call often: each occurrence is added once because `nextAt` moves forward.
 * Returns how many transactions were added.
 */
export async function processDueRecurring(db: DB, now: number = Date.now()): Promise<number> {
  const due = await db
    .select()
    .from(recurringRules)
    .where(and(isNull(recurringRules.pausedAt), lte(recurringRules.nextAt, now)))
    .all();
  let added = 0;
  for (const rule of due) {
    let nextAt = rule.nextAt;
    let count = 0;
    while (nextAt <= now && (rule.endAt === null || nextAt <= rule.endAt) && count < MAX_CATCH_UP) {
      await createTransaction(
        db,
        {
          type: rule.type,
          amount: rule.amount,
          accountId: rule.accountId,
          toAccountId: rule.toAccountId,
          categoryId: rule.categoryId,
          payee: rule.payee,
          note: rule.note,
          occurredAt: nextAt,
        },
        now,
        { source: 'recurring', recurringId: rule.id },
      );
      nextAt = occurrenceAfter(rule, nextAt);
      count++;
      added++;
    }
    // Skip anything beyond the catch-up cap rather than adding it later.
    if (count === MAX_CATCH_UP && nextAt <= now) nextAt = occurrenceAfter(rule, now);
    await db.update(recurringRules).set({ nextAt, updatedAt: now }).where(eq(recurringRules.id, rule.id));
  }
  return added;
}

/** Next occurrences of active rules within `days`, soonest first (for Home "Upcoming"). */
export async function upcomingRecurring(db: DB, now: number = Date.now(), days = 14) {
  const rules = await db.select().from(recurringRules).where(isNull(recurringRules.pausedAt)).orderBy(asc(recurringRules.nextAt)).all();
  const until = now + days * 86_400_000;
  return rules.filter((r) => r.nextAt <= until && (r.endAt === null || r.nextAt <= r.endAt));
}

export function describeFrequency(rule: Pick<RecurringRule, 'frequency' | 'interval'>): string {
  const unit = { daily: 'day', weekly: 'week', monthly: 'month', yearly: 'year' }[rule.frequency];
  if (rule.interval === 1) return { daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly', yearly: 'Yearly' }[rule.frequency];
  return `Every ${rule.interval} ${unit}s`;
}
