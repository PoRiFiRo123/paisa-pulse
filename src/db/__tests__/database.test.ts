/**
 * @jest-environment node
 */
import { eq } from 'drizzle-orm';

import { computeBalance } from '@/features/accounts/balance';
import { createAccount, removeAccount } from '@/features/accounts/mutations';
import { accountsWithBalance } from '@/features/accounts/queries';
import { createCategory, mergeCategory, setCategoryArchived } from '@/features/categories/mutations';
import { categoriesByKind } from '@/features/categories/queries';
import {
  PURGE_AFTER_MS,
  createTransaction,
  deleteTransaction,
  duplicateTransaction,
  purgeDeletedTransactions,
  restoreTransaction,
  updateTransaction,
} from '@/features/transactions/mutations';
import { periodSummary, spendingByCategory, transactionsInRange } from '@/features/transactions/queries';
import { TransactionValidationError } from '@/features/transactions/validation';

import { categories, transactions } from '../schema';
import { STARTER_CATEGORIES, seedStarterCategories } from '../seed';
import { getSetting } from '../settings';
import type { DB } from '../types';
import { createTestDb } from './testDb';

const NOW = Date.UTC(2026, 8, 25, 6);
const SEPT = { start: Date.UTC(2026, 8, 1), end: Date.UTC(2026, 9, 1) };

let db: DB;
let raw: ReturnType<typeof createTestDb>['raw'];

async function setupAccounts() {
  const axis = await createAccount(db, { name: 'Axis Salary', type: 'bank', institution: 'Axis Bank', openingBalance: 20_000_00, color: '#AE275F', icon: 'building.columns.fill' });
  const bob = await createAccount(db, { name: 'Bank of Baroda', type: 'bank', color: '#F26522', icon: 'building.columns.fill' });
  const card = await createAccount(db, { name: 'Axis MyZone', type: 'card', last4: '4321', creditLimit: 1_00_000_00, statementDay: 12, dueDay: 2, color: '#5E5CE6', icon: 'creditcard.fill' });
  return { axis, bob, card };
}

beforeEach(() => {
  ({ db, raw } = createTestDb());
});

afterEach(() => raw.close());

describe('seed', () => {
  it('inserts the India starter pack once', async () => {
    expect(await seedStarterCategories(db, NOW)).toBe(true);
    expect(await seedStarterCategories(db, NOW)).toBe(false);

    const expense = await categoriesByKind(db, 'expense');
    const income = await categoriesByKind(db, 'income');
    const expectedExpense = STARTER_CATEGORIES.expense.reduce((n, c) => n + 1 + (c.children?.length ?? 0), 0);
    expect(expense).toHaveLength(expectedExpense);
    expect(income.map((c) => c.name)).toEqual(['Salary', 'Freelance', 'Interest', 'Refund', 'Cashback', 'Other']);
    expect(await getSetting(db, 'seed.categories')).toBe(1);

    const transport = expense.find((c) => c.name === 'Transport')!;
    const fuel = expense.find((c) => c.name === 'Fuel')!;
    expect(fuel.parentId).toBe(transport.id);
    expect(fuel.color).toBe(transport.color);
  });
});

describe('transactions', () => {
  it('creates expense, income and transfer with the right shape', async () => {
    const { axis, card } = await setupAccounts();
    const t = await createTransaction(db, { type: 'expense', amount: 250_00, accountId: card.id, payee: '  Swiggy ', note: '' }, NOW);
    expect(t).toMatchObject({ payee: 'Swiggy', note: null, categoryId: null, occurredAt: NOW, source: 'manual' });
    await createTransaction(db, { type: 'income', amount: 80_000_00, accountId: axis.id }, NOW);
    await createTransaction(db, { type: 'transfer', amount: 250_00, accountId: axis.id, toAccountId: card.id }, NOW);
    expect(await transactionsInRange(db, SEPT)).toHaveLength(3);
  });

  it('rejects invalid input before touching the database', async () => {
    const { axis } = await setupAccounts();
    await expect(createTransaction(db, { type: 'transfer', amount: 100, accountId: axis.id, toAccountId: axis.id }, NOW)).rejects.toBeInstanceOf(TransactionValidationError);
    await expect(createTransaction(db, { type: 'expense', amount: 0, accountId: axis.id }, NOW)).rejects.toBeInstanceOf(TransactionValidationError);
  });

  it('is protected by database constraints too', async () => {
    const { axis } = await setupAccounts();
    const insert = (row: Partial<typeof transactions.$inferInsert>) =>
      db.insert(transactions).values({ id: String(Math.random()), type: 'expense', amount: 100, accountId: axis.id, occurredAt: NOW, createdAt: NOW, updatedAt: NOW, ...row });
    await expect(insert({ amount: 0 })).rejects.toThrow();
    await expect(insert({ type: 'transfer' })).rejects.toThrow();
    await expect(insert({ type: 'transfer', toAccountId: axis.id })).rejects.toThrow();
    await expect(insert({ accountId: 'missing' })).rejects.toThrow();
    await expect(insert({})).resolves.toBeDefined();
  });

  it('switches type on edit and clears fields that no longer apply', async () => {
    const { axis, card } = await setupAccounts();
    await seedStarterCategories(db, NOW);
    const [food] = await categoriesByKind(db, 'expense');
    const t = await createTransaction(db, { type: 'expense', amount: 5_000_00, accountId: axis.id, categoryId: food.id }, NOW);
    // The edit sheet must clear the category when switching to a transfer; validation refuses rather than guessing.
    await expect(
      updateTransaction(db, t.id, { type: 'transfer', amount: 5_000_00, accountId: axis.id, toAccountId: card.id, categoryId: food.id }, NOW + 1),
    ).rejects.toBeInstanceOf(TransactionValidationError);
    let row = await db.select().from(transactions).where(eq(transactions.id, t.id)).get();
    expect(row?.type).toBe('expense');

    await updateTransaction(db, t.id, { type: 'transfer', amount: 5_000_00, accountId: axis.id, toAccountId: card.id }, NOW + 1);
    row = await db.select().from(transactions).where(eq(transactions.id, t.id)).get();
    expect(row).toMatchObject({ type: 'transfer', toAccountId: card.id, categoryId: null, updatedAt: NOW + 1, createdAt: NOW });
  });

  it('soft deletes, undoes, duplicates and purges', async () => {
    const { axis } = await setupAccounts();
    const coffee = await createTransaction(db, { type: 'expense', amount: 180_00, accountId: axis.id, payee: 'Third Wave' }, NOW - 86_400_000);

    await deleteTransaction(db, coffee.id, NOW);
    expect(await transactionsInRange(db, SEPT)).toHaveLength(0);
    await restoreTransaction(db, coffee.id, NOW);
    expect(await transactionsInRange(db, SEPT)).toHaveLength(1);

    const copy = await duplicateTransaction(db, coffee.id, NOW);
    expect(copy).toMatchObject({ amount: 180_00, payee: 'Third Wave', occurredAt: NOW });
    expect(copy.id).not.toBe(coffee.id);

    await deleteTransaction(db, coffee.id, NOW);
    expect(await purgeDeletedTransactions(db, NOW + PURGE_AFTER_MS)).toBe(0);
    expect(await purgeDeletedTransactions(db, NOW + PURGE_AFTER_MS + 1)).toBe(1);
    expect(await db.select().from(transactions).all()).toHaveLength(1);
  });
});

describe('balances', () => {
  it('computes balances in SQL that match the pure calculation, transfers included', async () => {
    const { axis, bob, card } = await setupAccounts();
    await createTransaction(db, { type: 'income', amount: 80_000_00, accountId: axis.id }, NOW);
    await createTransaction(db, { type: 'expense', amount: 1_234_56, accountId: axis.id }, NOW);
    await createTransaction(db, { type: 'expense', amount: 4_500_00, accountId: card.id }, NOW);
    await createTransaction(db, { type: 'expense', amount: 999_00, accountId: card.id }, NOW);
    await createTransaction(db, { type: 'transfer', amount: 4_500_00, accountId: axis.id, toAccountId: card.id }, NOW);
    await createTransaction(db, { type: 'transfer', amount: 10_000_00, accountId: axis.id, toAccountId: bob.id }, NOW);
    const gone = await createTransaction(db, { type: 'expense', amount: 50_000_00, accountId: bob.id }, NOW);
    await deleteTransaction(db, gone.id, NOW);

    const rows = await accountsWithBalance(db);
    const byId = Object.fromEntries(rows.map((r) => [r.id, r.balance]));
    expect(byId[axis.id]).toBe(20_000_00 + 80_000_00 - 1_234_56 - 4_500_00 - 10_000_00);
    expect(byId[bob.id]).toBe(10_000_00);
    expect(byId[card.id]).toBe(-999_00);

    const all = await db.select().from(transactions).all();
    for (const account of rows) expect(account.balance).toBe(computeBalance(account, all));
  });

  it('excludes transfers from the monthly summary', async () => {
    const { axis, card } = await setupAccounts();
    await createTransaction(db, { type: 'income', amount: 80_000_00, accountId: axis.id }, NOW);
    await createTransaction(db, { type: 'expense', amount: 2_000_00, accountId: card.id }, NOW);
    await createTransaction(db, { type: 'transfer', amount: 2_000_00, accountId: axis.id, toAccountId: card.id }, NOW);
    await createTransaction(db, { type: 'expense', amount: 7_00, accountId: axis.id, occurredAt: Date.UTC(2026, 7, 31) }, NOW);

    expect(await periodSummary(db, SEPT)).toEqual({ spent: 2_000_00, received: 80_000_00, net: 78_000_00 });
    expect(await periodSummary(db, { start: 0, end: 1 })).toEqual({ spent: 0, received: 0, net: 0 });
  });
});

describe('accounts', () => {
  it('deletes unused accounts and archives used ones', async () => {
    const { axis, bob } = await setupAccounts();
    await createTransaction(db, { type: 'expense', amount: 100, accountId: axis.id }, NOW);
    expect(await removeAccount(db, axis.id, NOW)).toBe('archived');
    expect(await removeAccount(db, bob.id, NOW)).toBe('deleted');
    expect((await accountsWithBalance(db)).map((a) => a.name)).toEqual(['Axis MyZone']);
    expect(await accountsWithBalance(db, { includeArchived: true })).toHaveLength(2);
  });
});

describe('categories', () => {
  it('limits nesting to two levels and matching kinds', async () => {
    const food = await createCategory(db, { kind: 'expense', name: 'Food', icon: 'fork.knife', color: '#FF9500' }, NOW);
    const cafe = await createCategory(db, { kind: 'expense', name: 'Cafés', icon: 'cup.and.saucer.fill', color: '#FF9500', parentId: food.id }, NOW);
    await expect(createCategory(db, { kind: 'expense', name: 'Too deep', icon: 'x', color: '#000', parentId: cafe.id })).rejects.toThrow('two levels');
    await expect(createCategory(db, { kind: 'income', name: 'Wrong kind', icon: 'x', color: '#000', parentId: food.id })).rejects.toThrow('same kind');
  });

  it('merges transactions and subcategories into the target', async () => {
    const { axis } = await setupAccounts();
    const food = await createCategory(db, { kind: 'expense', name: 'Food', icon: 'fork.knife', color: '#FF9500' }, NOW);
    const eatingOut = await createCategory(db, { kind: 'expense', name: 'Eating out', icon: 'fork.knife', color: '#FF9500' }, NOW);
    const cafe = await createCategory(db, { kind: 'expense', name: 'Cafés', icon: 'cup.and.saucer.fill', color: '#FF9500', parentId: eatingOut.id }, NOW);
    await createTransaction(db, { type: 'expense', amount: 300_00, accountId: axis.id, categoryId: eatingOut.id }, NOW);
    await createTransaction(db, { type: 'expense', amount: 200_00, accountId: axis.id, categoryId: food.id }, NOW);

    await mergeCategory(db, eatingOut.id, food.id, NOW);

    expect(await spendingByCategory(db, SEPT)).toEqual([{ categoryId: food.id, total: 500_00 }]);
    const rows = await db.select().from(categories).all();
    expect(rows.find((c) => c.id === eatingOut.id)?.archivedAt).toBe(NOW);
    expect(rows.find((c) => c.id === cafe.id)?.parentId).toBe(food.id);
  });

  it('archives subcategories with their parent', async () => {
    const food = await createCategory(db, { kind: 'expense', name: 'Food', icon: 'fork.knife', color: '#FF9500' }, NOW);
    await createCategory(db, { kind: 'expense', name: 'Cafés', icon: 'cup.and.saucer.fill', color: '#FF9500', parentId: food.id }, NOW);
    await setCategoryArchived(db, food.id, true, NOW);
    expect(await categoriesByKind(db, 'expense')).toHaveLength(0);
    expect(await categoriesByKind(db, 'expense', { includeArchived: true })).toHaveLength(2);
  });
});
