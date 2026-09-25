import { and, eq, gte, inArray, isNull, lt, sql } from 'drizzle-orm';

import { type Budget, budgets, type Category, categories, transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { newId } from '@/lib/ids';
import type { DateRange } from '@/features/transactions/queries';

export class BudgetError extends Error {
  name = 'BudgetError';
}

/** Create or update the budget for a category (null = overall monthly budget). */
export async function setBudget(db: DB, categoryId: string | null, amount: number, now: number = Date.now()): Promise<Budget> {
  if (!Number.isSafeInteger(amount) || amount <= 0) throw new BudgetError('Budget must be more than ₹0');
  if (categoryId) {
    const cat = await db.select().from(categories).where(eq(categories.id, categoryId)).get();
    if (!cat) throw new BudgetError('Category not found');
    if (cat.kind !== 'expense') throw new BudgetError('Budgets are for expense categories');
  }
  const where = categoryId ? eq(budgets.categoryId, categoryId) : isNull(budgets.categoryId);
  const existing = await db.select().from(budgets).where(where).get();
  if (existing) {
    await db.update(budgets).set({ amount, updatedAt: now }).where(eq(budgets.id, existing.id));
    return { ...existing, amount, updatedAt: now };
  }
  const row = { id: newId(), categoryId, amount, createdAt: now, updatedAt: now };
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

/**
 * Progress of every budget for a period. A category budget includes its subcategories;
 * the overall budget counts all expenses. Transfers never count.
 */
export async function budgetProgress(db: DB, range: DateRange, now: number = Date.now()): Promise<BudgetProgress[]> {
  const rows = await db.select().from(budgets).all();
  if (!rows.length) return [];
  const cats = await db.select().from(categories).all();
  const byId = new Map(cats.map((c) => [c.id, c]));
  const elapsed = Math.min(Math.max((now - range.start) / (range.end - range.start), 0), 1);

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
  const spentByTop = new Map(perCategory.map((r) => [r.topId, r.total]));
  const overall = perCategory.reduce((s, r) => s + r.total, 0);

  const progress = rows.map((budget) => {
    const category = budget.categoryId ? (byId.get(budget.categoryId) ?? null) : null;
    // A budget on a subcategory counts only that subcategory.
    let spent = overall;
    if (category) {
      spent = category.parentId ? 0 : (spentByTop.get(category.id) ?? 0);
    }
    return { budget, category, spent, elapsed };
  });

  // Budgets set on subcategories need their own totals.
  const subIds = progress.filter((p) => p.category?.parentId).map((p) => p.category!.id);
  if (subIds.length) {
    const subs = await db
      .select({ id: transactions.categoryId, total: sql<number>`sum(${transactions.amount})`.mapWith(Number) })
      .from(transactions)
      .where(and(inRange, inArray(transactions.categoryId, subIds)))
      .groupBy(transactions.categoryId);
    const bySub = new Map(subs.map((r) => [r.id, r.total]));
    for (const p of progress) if (p.category?.parentId) p.spent = bySub.get(p.category.id) ?? 0;
  }

  return progress
    .map((p) => {
      const ratio = p.spent / p.budget.amount;
      return { ...p, remaining: p.budget.amount - p.spent, ratio, status: budgetStatus(ratio, elapsed) };
    })
    .sort((a, b) => Number(b.category === null) - Number(a.category === null) || b.ratio - a.ratio);
}

/** Categories that can still get a budget (expense, not archived, none yet). */
export async function budgetableCategories(db: DB): Promise<Category[]> {
  const used = (await db.select({ id: budgets.categoryId }).from(budgets).all()).map((b) => b.id);
  const cats = await db
    .select()
    .from(categories)
    .where(and(eq(categories.kind, 'expense'), isNull(categories.archivedAt)))
    .orderBy(categories.sortOrder);
  return cats.filter((c) => !used.includes(c.id));
}

