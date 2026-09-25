/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { accountsWithBalance } from '@/features/accounts/queries';
import { createCategory } from '@/features/categories/mutations';

import { bulkDelete, bulkSetAccount, bulkSetCategory, restoreSnapshot } from '../bulk';
import { listTransactions } from '../list';
import { createTransaction } from '../mutations';

const NOW = Date.UTC(2026, 8, 25, 6);

async function setup() {
  const { db, raw } = createTestDb();
  const axis = await createAccount(db, { name: 'Axis Bank', type: 'bank', color: '#AE275F', icon: 'building.columns.fill' }, NOW);
  const bob = await createAccount(db, { name: 'Bank of Baroda', type: 'bank', color: '#F26522', icon: 'building.columns.fill' }, NOW);
  const card = await createAccount(db, { name: 'Axis MyZone', type: 'card', color: '#5E5CE6', icon: 'creditcard.fill' }, NOW);
  const food = await createCategory(db, { kind: 'expense', name: 'Food', icon: 'fork.knife', color: '#FF9500' }, NOW);
  const salary = await createCategory(db, { kind: 'income', name: 'Salary', icon: 'banknote.fill', color: '#30B0C7' }, NOW);
  const e1 = await createTransaction(db, { type: 'expense', amount: 100_00, accountId: axis.id }, NOW);
  const e2 = await createTransaction(db, { type: 'expense', amount: 200_00, accountId: card.id }, NOW);
  const inc = await createTransaction(db, { type: 'income', amount: 1_000_00, accountId: axis.id, categoryId: salary.id }, NOW);
  const tr = await createTransaction(db, { type: 'transfer', amount: 50_00, accountId: axis.id, toAccountId: card.id }, NOW);
  return { db, raw, axis, bob, card, food, salary, ids: [e1.id, e2.id, inc.id, tr.id], e1, e2, inc, tr };
}

const byId = async (db: ReturnType<typeof createTestDb>['db']) =>
  Object.fromEntries((await listTransactions(db)).map((t) => [t.id, t]));

describe('bulk edit', () => {
  it('sets a category only on matching types and undoes exactly', async () => {
    const { db, raw, food, ids, e1, e2, inc, tr, salary } = await setup();
    const { undo, count } = await bulkSetCategory(db, ids, food.id, NOW + 1);
    expect(count).toBe(2);
    let rows = await byId(db);
    expect([rows[e1.id].categoryId, rows[e2.id].categoryId]).toEqual([food.id, food.id]);
    expect(rows[inc.id].categoryId).toBe(salary.id);
    expect(rows[tr.id].categoryId).toBeNull();

    await restoreSnapshot(db, undo, NOW + 2);
    rows = await byId(db);
    expect([rows[e1.id].categoryId, rows[e2.id].categoryId, rows[inc.id].categoryId]).toEqual([null, null, salary.id]);
    raw.close();
  });

  it('clears categories to Uncategorised without touching transfers', async () => {
    const { db, raw, ids, inc } = await setup();
    const { count } = await bulkSetCategory(db, ids, null, NOW);
    expect(count).toBe(3);
    expect((await byId(db))[inc.id].categoryId).toBeNull();
    raw.close();
  });

  it('moves accounts but never makes a transfer into itself', async () => {
    const { db, raw, card, bob, ids, tr } = await setup();
    expect((await bulkSetAccount(db, ids, card.id, NOW)).count).toBe(3);
    expect((await byId(db))[tr.id].accountId).not.toBe(card.id);
    const { undo } = await bulkSetAccount(db, ids, bob.id, NOW);
    expect(Object.values(await byId(db)).every((t) => t.accountId === bob.id)).toBe(true);
    await restoreSnapshot(db, undo, NOW);
    expect((await byId(db))[tr.id].accountId).not.toBe(bob.id);
    raw.close();
  });

  it('deletes and restores many, keeping balances right', async () => {
    const { db, raw, ids } = await setup();
    const before = await accountsWithBalance(db);
    const { undo, count } = await bulkDelete(db, ids, NOW);
    expect(count).toBe(4);
    expect(await listTransactions(db)).toHaveLength(0);
    await restoreSnapshot(db, undo, NOW);
    expect(await accountsWithBalance(db)).toEqual(before);
    raw.close();
  });
});
