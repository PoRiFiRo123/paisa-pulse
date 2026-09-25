/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { exportBackup, parseBackup, restoreBackup } from '@/features/backup/backup';
import { createCategory } from '@/features/categories/mutations';
import { createTransaction, deleteTransaction } from '@/features/transactions/mutations';

import { BudgetError, budgetableCategories, budgetProgress, budgetStatus, deleteBudget, setBudget } from '../budgets';

const SEPT = { start: Date.UTC(2026, 8, 1), end: Date.UTC(2026, 9, 1) };
const MID = Date.UTC(2026, 8, 16);

async function setup() {
  const { db, raw } = createTestDb();
  const axis = await createAccount(db, { name: 'Axis', type: 'bank', color: '#000', icon: 'x' }, MID);
  const card = await createAccount(db, { name: 'Card', type: 'card', color: '#000', icon: 'x' }, MID);
  const food = await createCategory(db, { kind: 'expense', name: 'Food', icon: 'x', color: '#FF9500' }, MID);
  const cafe = await createCategory(db, { kind: 'expense', name: 'Cafés', icon: 'x', color: '#FF9500', parentId: food.id }, MID);
  const rent = await createCategory(db, { kind: 'expense', name: 'Rent', icon: 'x', color: '#AF52DE' }, MID);
  const salary = await createCategory(db, { kind: 'income', name: 'Salary', icon: 'x', color: '#30B0C7' }, MID);
  const spend = (amount: number, categoryId: string | null) =>
    createTransaction(db, { type: 'expense', amount, accountId: axis.id, categoryId }, MID);
  await spend(4_000_00, food.id);
  await spend(1_000_00, cafe.id);
  await spend(15_000_00, rent.id);
  await spend(500_00, null);
  const gone = await spend(9_999_00, food.id);
  await deleteTransaction(db, gone.id, MID);
  await createTransaction(db, { type: 'income', amount: 90_000_00, accountId: axis.id, categoryId: salary.id }, MID);
  await createTransaction(db, { type: 'transfer', amount: 10_000_00, accountId: axis.id, toAccountId: card.id }, MID);
  await createTransaction(db, { type: 'expense', amount: 7_00, accountId: axis.id, categoryId: food.id, occurredAt: Date.UTC(2026, 7, 31) }, MID);
  return { db, raw, food, cafe, rent, salary };
}

describe('budgets', () => {
  it('tracks overall, category (with subcategories) and subcategory budgets', async () => {
    const { db, raw, food, cafe, rent } = await setup();
    await setBudget(db, null, 30_000_00, MID);
    await setBudget(db, food.id, 6_000_00, MID);
    await setBudget(db, cafe.id, 800_00, MID);
    await setBudget(db, rent.id, 15_000_00, MID);
    const p = await budgetProgress(db, SEPT, MID);
    const by = (id: string | null) => p.find((x) => (x.category?.id ?? null) === id)!;
    expect(p[0].category).toBeNull(); // overall first
    expect(by(null)).toMatchObject({ spent: 20_500_00, remaining: 9_500_00 });
    expect(by(food.id)).toMatchObject({ spent: 5_000_00, remaining: 1_000_00, status: 'ahead' });
    expect(by(cafe.id)).toMatchObject({ spent: 1_000_00, status: 'over' });
    expect(by(rent.id)).toMatchObject({ spent: 15_000_00, status: 'warning' });
    expect(by(null).elapsed).toBeCloseTo(0.5, 1);
    raw.close();
  });

  it('upserts one budget per category and validates input', async () => {
    const { db, raw, food, salary } = await setup();
    const a = await setBudget(db, food.id, 100, MID);
    const b = await setBudget(db, food.id, 200, MID);
    expect(b.id).toBe(a.id);
    await setBudget(db, null, 100, MID);
    await setBudget(db, null, 300, MID);
    expect(await budgetProgress(db, SEPT, MID)).toHaveLength(2);
    await expect(setBudget(db, salary.id, 100)).rejects.toBeInstanceOf(BudgetError);
    await expect(setBudget(db, null, 0)).rejects.toBeInstanceOf(BudgetError);
    expect((await budgetableCategories(db)).map((c) => c.name)).toEqual(['Cafés', 'Rent']);
    await deleteBudget(db, b.id);
    expect(await budgetProgress(db, SEPT, MID)).toHaveLength(1);
    raw.close();
  });

  it('survives a backup round trip', async () => {
    const { db, raw, food } = await setup();
    await setBudget(db, food.id, 6_000_00, MID);
    const json = JSON.stringify(await exportBackup(db, MID));
    const other = createTestDb();
    await restoreBackup(other.db, parseBackup(json));
    expect((await budgetProgress(other.db, SEPT, MID))[0]).toMatchObject({ spent: 5_000_00 });
    raw.close();
    other.raw.close();
  });
});

describe('budgetStatus', () => {
  it('flags over, warning and spending ahead of pace', () => {
    expect(budgetStatus(1.2, 0.5)).toBe('over');
    expect(budgetStatus(0.9, 0.95)).toBe('warning');
    expect(budgetStatus(0.7, 0.4)).toBe('ahead');
    expect(budgetStatus(0.4, 0.4)).toBe('ok');
    expect(budgetStatus(0.15, 0.05)).toBe('ok');
  });
});
