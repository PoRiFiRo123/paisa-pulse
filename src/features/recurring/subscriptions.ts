import { and, asc, eq, inArray, isNotNull, isNull, sql } from 'drizzle-orm';

import { type Account, accounts, type Category, categories, type RecurringFrequency, type RecurringRule, recurringRules, transactions } from '@/db/schema';
import type { DB } from '@/db/types';

import { createRecurring, occurrenceAfter } from './recurring';

const DAY = 86_400_000;

/** Average cost per month of a rule, in paise (a yearly ₹1,499 plan is ₹125/month). */
export function monthlyEquivalent(rule: Pick<RecurringRule, 'amount' | 'frequency' | 'interval'>): number {
  const perYear = { daily: 365, weekly: 52, monthly: 12, yearly: 1 }[rule.frequency] / rule.interval;
  return Math.round((rule.amount * perYear) / 12);
}

export type Subscription = {
  rule: RecurringRule;
  account: Account;
  category: Category | null;
  monthly: number;
  yearly: number;
  /** Total of the payments this rule has added (and past ones linked to it). */
  paid: number;
  payments: number;
  firstPaidAt: number | null;
  active: boolean;
};

/** Every recurring expense with its monthly/yearly cost and what it has cost so far. */
export async function listSubscriptions(db: DB, now: number = Date.now()): Promise<Subscription[]> {
  const rows = await db
    .select({ rule: recurringRules, account: accounts, category: categories })
    .from(recurringRules)
    .innerJoin(accounts, eq(accounts.id, recurringRules.accountId))
    .leftJoin(categories, eq(categories.id, recurringRules.categoryId))
    .where(eq(recurringRules.type, 'expense'))
    .orderBy(asc(recurringRules.nextAt));
  if (!rows.length) return [];
  const totals = await db
    .select({
      id: transactions.recurringId,
      paid: sql<number>`sum(${transactions.amount})`.mapWith(Number),
      payments: sql<number>`count(*)`.mapWith(Number),
      first: sql<number>`min(${transactions.occurredAt})`.mapWith(Number),
    })
    .from(transactions)
    .where(and(isNull(transactions.deletedAt), inArray(transactions.recurringId, rows.map((r) => r.rule.id))))
    .groupBy(transactions.recurringId);
  const byRule = new Map(totals.map((t) => [t.id, t]));
  return rows
    .map(({ rule, account, category }) => {
      const t = byRule.get(rule.id);
      const monthly = monthlyEquivalent(rule);
      const ended = rule.endAt !== null && rule.nextAt > rule.endAt;
      return {
        rule,
        account,
        category,
        monthly,
        yearly: monthly * 12,
        paid: t?.paid ?? 0,
        payments: t?.payments ?? 0,
        firstPaidAt: t?.first ?? null,
        active: rule.pausedAt === null && !ended && (rule.endAt === null || rule.endAt >= now),
      };
    })
    .sort((a, b) => Number(b.active) - Number(a.active) || a.rule.nextAt - b.rule.nextAt);
}

export type DetectedSubscription = {
  payee: string;
  amount: number;
  frequency: RecurringFrequency;
  accountId: string;
  categoryId: string | null;
  lastAt: number;
  nextAt: number;
  transactionIds: string[];
};

const CADENCES: { frequency: RecurringFrequency; days: number; min: number; max: number }[] = [
  { frequency: 'weekly', days: 7, min: 6, max: 8 },
  { frequency: 'monthly', days: 30.4, min: 26, max: 35 },
  { frequency: 'yearly', days: 365, min: 350, max: 380 },
];

const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

/**
 * Payees you pay a steady amount on a steady cadence (Netflix every month, a weekly maid)
 * that aren't tracked as recurring yet. Needs 3 payments (2 for yearly), amounts within 10%,
 * and the latest payment recent enough that it's probably still running.
 */
export async function detectSubscriptions(db: DB, now: number = Date.now()): Promise<DetectedSubscription[]> {
  const since = now - 800 * DAY;
  const rows = await db
    .select({
      id: transactions.id,
      payee: transactions.payee,
      amount: transactions.amount,
      accountId: transactions.accountId,
      categoryId: transactions.categoryId,
      occurredAt: transactions.occurredAt,
      recurringId: transactions.recurringId,
    })
    .from(transactions)
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.type, 'expense'),
        isNotNull(transactions.payee),
        sql`${transactions.occurredAt} >= ${since}`,
      ),
    )
    .orderBy(asc(transactions.occurredAt));
  const tracked = new Set(
    (await db.select({ payee: recurringRules.payee }).from(recurringRules).where(isNotNull(recurringRules.payee))).map((r) => r.payee!.toLowerCase()),
  );

  const groups = new Map<string, typeof rows>();
  for (const r of rows) {
    if (r.recurringId) continue;
    const key = r.payee!.trim().toLowerCase();
    if (!key || tracked.has(key)) continue;
    groups.set(key, [...(groups.get(key) ?? []), r]);
  }

  const found: DetectedSubscription[] = [];
  for (const list of groups.values()) {
    if (list.length < 2) continue;
    // Look at the recent run of similar amounts (a price rise starts a new run).
    const last = list[list.length - 1];
    const run = [] as typeof list;
    for (let i = list.length - 1; i >= 0; i--) {
      if (Math.abs(list[i].amount - last.amount) > last.amount * 0.1) break;
      run.unshift(list[i]);
    }
    if (run.length < 2) continue;
    const gaps = run.slice(1).map((r, i) => (r.occurredAt - run[i].occurredAt) / DAY);
    const gap = median(gaps);
    const cadence = CADENCES.find((c) => gap >= c.min && gap <= c.max);
    if (!cadence) continue;
    if (run.length < (cadence.frequency === 'yearly' ? 2 : 3)) continue;
    // Every gap must fit the cadence loosely (one skipped month is fine).
    if (gaps.some((g) => g < cadence.min * 0.7 || g > cadence.max * 2.1)) continue;
    // Stale: no payment for more than 1.6 cycles.
    if (now - last.occurredAt > cadence.days * 1.6 * DAY) continue;
    const nextAt = nextOccurrence(last.occurredAt, cadence.frequency);
    found.push({
      payee: last.payee!.trim(),
      amount: last.amount,
      frequency: cadence.frequency,
      accountId: last.accountId,
      categoryId: last.categoryId,
      lastAt: last.occurredAt,
      nextAt,
      transactionIds: run.map((r) => r.id),
    });
  }
  return found.sort((a, b) => monthlyEquivalent({ ...b, interval: 1 }) - monthlyEquivalent({ ...a, interval: 1 }));
}

function nextOccurrence(from: number, frequency: RecurringFrequency): number {
  const d = new Date(from);
  if (frequency === 'weekly') d.setDate(d.getDate() + 7);
  else if (frequency === 'monthly') d.setMonth(d.getMonth() + 1);
  else d.setFullYear(d.getFullYear() + 1);
  return d.getTime();
}

/**
 * Start tracking a detected subscription: a recurring rule anchored on the latest payment
 * (so the next one is added on time), with the past payments linked to it for "Total paid".
 */
export async function trackSubscription(db: DB, s: DetectedSubscription, now: number = Date.now()) {
  const rule = await createRecurring(
    db,
    { type: 'expense', amount: s.amount, accountId: s.accountId, categoryId: s.categoryId, payee: s.payee, frequency: s.frequency, startAt: s.lastAt },
    { firstAlreadyAdded: true, now },
  );
  await db.update(transactions).set({ recurringId: rule.id }).where(inArray(transactions.id, s.transactionIds));
  // A payment that's already overdue isn't invented: tracking starts with the next one from now.
  if (rule.nextAt <= now) {
    const nextAt = occurrenceAfter(rule, now);
    await db.update(recurringRules).set({ nextAt }).where(eq(recurringRules.id, rule.id));
    return { ...rule, nextAt };
  }
  return rule;
}
