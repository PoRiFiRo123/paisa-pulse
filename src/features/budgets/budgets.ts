import { and, eq, gte, inArray, isNull, lt, sql } from 'drizzle-orm';

import { type Budget, type BudgetPeriod, budgets, type Category, categories, transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { weekRange } from '@/lib/dates';
import { newId } from '@/lib/ids';
import type { DateRange } from '@/features/transactions/queries';

export class BudgetError extends Error {
  name = 'BudgetError';
}

/** Create or update the budget for a category (null = overall) and period. */
export async function setBudget(
  db: DB,
  categoryId: string | null,
  amount: number,
  now: number = Date.now(),
  period: BudgetPeriod = 'monthly',
): Promise<Budget> {
  if (!Number.isSafeInteger(amount) || amount <= 0) throw new BudgetError('Budget must be more than ₹0');
  if (categoryId) {
    const cat = await db.select().from(categories).where(eq(categories.id, categoryId)).get();
    if (!cat) throw new BudgetError('Category not found');
    if (cat.kind !== 'expense') throw new BudgetError('Budgets are for expense categories');
  }
  const where = and(categoryId ? eq(budgets.categoryId, categoryId) : isNull(budgets.categoryId), eq(budgets.period, period));
  const existing = await db.select().from(budgets).where(where).get();
  if (existing) {
    await db.update(budgets).set({ amount, updatedAt: now }).where(eq(budgets.id, existing.id));
    return { ...existing, amount, updatedAt: now };
  }
  const row = { id: newId(), categoryId, period, amount, createdAt: now, updatedAt: now };
  await db.insert(budgets).values(row);
  return row;
}

export async function deleteBudget(db: DB, id: string): Promise<void> {
  await db.delete(budgets).where(eq(budgets.id, id));
}

export type BudgetStatus = 'ok' | 'ahead' | 'warning' | 'over';

export type BudgetProgress = {
  budget: Budget;
  /** null for the overall budget. */
  category: Category | null;
  spent: number;
  remaining: number;
  /** spent / amount, can exceed 1. */
  ratio: number;
  /** How far through the period we are, 0–1. */
  elapsed: number;
  status: BudgetStatus;
};

/** Pure status rule, shared by the screen and tests. */
export function budgetStatus(ratio: number, elapsed: number): BudgetStatus {
  if (ratio > 1) return 'over';
  if (ratio >= 0.85) return 'warning';
  // Spending noticeably faster than the month is passing.
  if (elapsed > 0.1 && ratio > elapsed + 0.1) return 'ahead';
  return 'ok';
}

type Spending = { overall: number; byTop: Map<string | null, number>; bySub: Map<string | null, number> };

/** Expense totals for a range: overall, per top-level category (incl. subcategories) and per given subcategory. */
async function spendingIn(db: DB, range: DateRange, subIds: string[]): Promise<Spending> {
  const inRange = and(
    isNull(transactions.deletedAt),
    eq(transactions.type, 'expense'),
    gte(transactions.occurredAt, range.start),
    lt(transactions.occurredAt, range.end),
  );
  const perCategory = await db
    .select({
      topId: sql<string | null>`coalesce(${categories.parentId}, ${transactions.categoryId})`.as('top_id'),
      total: sql<number>`sum(${transactions.amount})`.mapWith(Number).as('total'),
    })
    .from(transactions)
    .leftJoin(categories, eq(categories.id, transactions.categoryId))
    .where(inRange)
    .groupBy(sql`top_id`);
  let bySub = new Map<string | null, number>();
  if (subIds.length) {
    const subs = await db
      .select({ id: transactions.categoryId, total: sql<number>`sum(${transactions.amount})`.mapWith(Number) })
      .from(transactions)
      .where(and(inRange, inArray(transactions.categoryId, subIds)))
      .groupBy(transactions.categoryId);
    bySub = new Map(subs.map((r) => [r.id, r.total]));
  }
  return {
    overall: perCategory.reduce((s, r) => s + r.total, 0),
    byTop: new Map(perCategory.map((r) => [r.topId, r.total])),
    bySub,
  };
}

/**
 * Progress of every budget: monthly budgets over `month`, weekly ones over `week`.
 * A category budget includes its subcategories; a subcategory budget counts only itself;
 * the overall budget counts all expenses. Transfers never count.
 */
export async function budgetProgress(
  db: DB,
  month: DateRange,
  now: number = Date.now(),
  week: DateRange = weekRange(now, 1),
): Promise<BudgetProgress[]> {
  const rows = await db.select().from(budgets).all();
  if (!rows.length) return [];
  const cats = await db.select().from(categories).all();
  const byId = new Map(cats.map((c) => [c.id, c]));
  const elapsedIn = (r: DateRange) => Math.min(Math.max((now - r.start) / (r.end - r.start), 0), 1);

  const spending: Partial<Record<BudgetPeriod, Spending>> = {};
  for (const period of ['monthly', 'weekly'] as const) {
    const these = rows.filter((b) => b.period === period);
    if (!these.length) continue;
    const subIds = these.map((b) => (b.categoryId ? byId.get(b.categoryId) : undefined)).filter((c) => c?.parentId).map((c) => c!.id);
    spending[period] = await spendingIn(db, period === 'weekly' ? week : month, subIds);
  }

  return rows
    .map((budget) => {
      const category = budget.categoryId ? (byId.get(budget.categoryId) ?? null) : null;
      const s = spending[budget.period]!;
      const spent = !category ? s.overall : category.parentId ? (s.bySub.get(category.id) ?? 0) : (s.byTop.get(category.id) ?? 0);
      const elapsed = elapsedIn(budget.period === 'weekly' ? week : month);
      const ratio = spent / budget.amount;
      return { budget, category, spent, elapsed, remaining: budget.amount - spent, ratio, status: budgetStatus(ratio, elapsed) };
    })
    .sort(
      (a, b) =>
        Number(b.budget.period === 'monthly') - Number(a.budget.period === 'monthly') ||
        Number(b.category === null) - Number(a.category === null) ||
        b.ratio - a.ratio,
    );
}

/** Categories that can still get a budget for `period` (expense, not archived, none yet). */
export async function budgetableCategories(db: DB, period: BudgetPeriod = 'monthly'): Promise<Category[]> {
  const used = (await db.select({ id: budgets.categoryId }).from(budgets).where(eq(budgets.period, period)).all()).map((b) => b.id);
  const cats = await db
    .select()
    .from(categories)
    .where(and(eq(categories.kind, 'expense'), isNull(categories.archivedAt)))
    .orderBy(categories.sortOrder);
  return cats.filter((c) => !used.includes(c.id));
}

