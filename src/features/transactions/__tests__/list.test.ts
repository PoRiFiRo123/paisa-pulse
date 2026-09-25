/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { createCategory } from '@/features/categories/mutations';

import { createTransaction } from '../mutations';
import { listTransactions, recentCategoryIds, topCategories } from '../list';

const NOW = Date.UTC(2026, 8, 25, 6);
const SEPT = { start: Date.UTC(2026, 8, 1), end: Date.UTC(2026, 9, 1) };

async function setup() {
  const { db, raw } = createTestDb();
  const axis = await createAccount(db, { name: 'Axis Bank', type: 'bank', last4: '4521', color: '#AE275F', icon: 'building.columns.fill' }, NOW);
  const card = await createAccount(db, { name: 'Axis MyZone', type: 'card', color: '#5E5CE6', icon: 'creditcard.fill' }, NOW);
  const food = await createCategory(db, { kind: 'expense', name: 'Food', icon: 'fork.knife', color: '#FF9500' }, NOW);
  const cafe = await createCategory(db, { kind: 'expense', name: 'Cafés', icon: 'cup.and.saucer.fill', color: '#FF9500', parentId: food.id }, NOW);
  const rent = await createCategory(db, { kind: 'expense', name: 'Rent', icon: 'house.fill', color: '#AF52DE' }, NOW);
  await createTransaction(db, { type: 'expense', amount: 420_00, accountId: axis.id, categoryId: food.id, payee: 'Swiggy', note: 'Lunch with team' }, NOW);
  await createTransaction(db, { type: 'expense', amount: 180_00, accountId: card.id, categoryId: cafe.id, payee: 'Third Wave' }, NOW - 1);
  await createTransaction(db, { type: 'expense', amount: 15_000_00, accountId: axis.id, categoryId: rent.id }, NOW - 2);
  await createTransaction(db, { type: 'expense', amount: 50_00, accountId: axis.id }, NOW - 3);
  await createTransaction(db, { type: 'transfer', amount: 5_000_00, accountId: axis.id, toAccountId: card.id }, NOW - 4);
  return { db, raw, axis, card, food, cafe, rent };
}

describe('listTransactions', () => {
  it('joins account, category and parent names', async () => {
    const { db, raw, axis } = await setup();
    const [first] = await listTransactions(db, { limit: 1 });
    expect(first).toMatchObject({ payee: 'Swiggy', accountName: 'Axis Bank', accountLast4: '4521', categoryName: 'Food', parentCategoryName: null });
    const transfer = (await listTransactions(db, { types: ['transfer'] }))[0];
    expect(transfer).toMatchObject({ accountId: axis.id, toAccountName: 'Axis MyZone', categoryName: null });
    raw.close();
  });

  it('filters by account (both sides of transfers), category tree, search and uncategorised', async () => {
    const { db, raw, card, food } = await setup();
    expect((await listTransactions(db, { accountIds: [card.id] })).map((t) => t.amount)).toEqual([180_00, 5_000_00]);
    expect((await listTransactions(db, { categoryIds: [food.id] })).map((t) => t.payee)).toEqual(['Swiggy', 'Third Wave']);
    expect((await listTransactions(db, { categoryIds: [null] })).map((t) => t.amount)).toEqual([50_00]);
    expect((await listTransactions(db, { search: 'team' })).map((t) => t.payee)).toEqual(['Swiggy']);
    expect((await listTransactions(db, { search: 'cafés' })).map((t) => t.payee)).toEqual(['Third Wave']);
    expect(await listTransactions(db, { range: { start: 0, end: 1 } })).toEqual([]);
    raw.close();
  });
});

describe('topCategories', () => {
  it('rolls subcategories into their parent and ranks by spend', async () => {
    const { db, raw, food, rent } = await setup();
    const top = await topCategories(db, SEPT);
    expect(top.map((t) => [t.categoryId, t.total])).toEqual([
      [rent.id, 15_000_00],
      [food.id, 600_00],
      [null, 50_00],
    ]);
    expect(top[1].category?.name).toBe('Food');
    raw.close();
  });
});

describe('recentCategoryIds', () => {
  it('orders by last use', async () => {
    const { db, raw, food, cafe, rent } = await setup();
    expect(await recentCategoryIds(db, 'expense')).toEqual([food.id, cafe.id, rent.id]);
    raw.close();
  });
});
