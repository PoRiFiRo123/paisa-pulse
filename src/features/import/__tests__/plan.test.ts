/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { importBatches } from '@/db/schema';
import { seedStarterCategories } from '@/db/seed';
import { createAccount } from '@/features/accounts/mutations';
import { accountsWithBalance } from '@/features/accounts/queries';
import { exportBackup, parseBackup, restoreBackup } from '@/features/backup/backup';
import { categoriesByKind } from '@/features/categories/queries';
import { listTransactions } from '@/features/transactions/list';
import { createTransaction } from '@/features/transactions/mutations';

import { detectMapping, detectTemplate, extractRows } from '../parse';
import { commitImport, listImportBatches, planImport, restoreImport, rowKeys, undoImport } from '../plan';
import { parseCsv } from '../readers/csv';
import { AXIS_CARD_CSV, AXIS_CSV } from './fixtures/statements';

const rowsOf = (csv: string, kind: 'bank' | 'card') => {
  const sheet = parseCsv(csv);
  return extractRows(sheet, detectMapping(sheet, detectTemplate(sheet), kind)!);
};

async function setup() {
  const { db, raw } = createTestDb();
  const now = new Date(2026, 9, 1).getTime();
  await seedStarterCategories(db, now);
  const axis = await createAccount(db, { name: 'Axis Bank', type: 'bank', last4: '5678', openingBalance: 10_000_00, color: '#000', icon: 'x' }, now);
  const card = await createAccount(db, { name: 'Axis MyZone', type: 'card', last4: '3307', color: '#000', icon: 'x' }, now);
  const cash = await createAccount(db, { name: 'Cash', type: 'cash', color: '#000', icon: 'x' }, now);
  const cats = [...(await categoriesByKind(db, 'expense')), ...(await categoriesByKind(db, 'income'))];
  const cat = (name: string) => cats.find((c) => c.name === name)!.id;
  // Entered by hand before importing: the Swiggy order.
  const manual = await createTransaction(
    db,
    { type: 'expense', amount: 420_00, accountId: axis.id, categoryId: cat('Food & Dining'), payee: 'Swiggy', occurredAt: new Date(2026, 8, 1, 20).getTime() },
    now,
  );
  return { db, raw, now, axis, card, cash, cat, manual };
}

describe('planImport', () => {
  it('suggests types, transfers, payees and categories, and flags a manual duplicate', async () => {
    const { db, raw, axis, card, cash, cat, manual } = await setup();
    const plan = await planImport(db, axis.id, rowsOf(AXIS_CSV, 'bank'));
    const view = plan.map((p) => [p.payee, p.type, p.otherAccountId, p.categoryId, p.status, p.include]);
    expect(view).toEqual([
      ['Swiggy', 'expense', null, cat('Food & Dining'), 'possible-duplicate', false],
      ['Acme Technologies', 'income', null, cat('Salary'), 'new', true],
      ['ATM withdrawal', 'transfer', cash.id, null, 'new', true],
      ['Credit card payment', 'transfer', card.id, null, 'new', true],
      ['Rahul Sharma', 'expense', null, cat('Rent'), 'new', true],
      ['Interest', 'income', null, cat('Interest'), 'new', true],
    ]);
    expect(plan[0].duplicateOf).toBe(manual.id);
    expect(plan[4].note).toBe('rent share');
    raw.close();
  });

  it('learns categories from past transactions for the same payee', async () => {
    const { db, raw, axis, cat } = await setup();
    await createTransaction(db, { type: 'expense', amount: 100, accountId: axis.id, payee: 'Rahul Sharma', categoryId: cat('Family') });
    const plan = await planImport(db, axis.id, rowsOf(AXIS_CSV, 'bank'));
    expect(plan.find((p) => p.payee === 'Rahul Sharma')!.categoryId).toBe(cat('Family'));
    raw.close();
  });
});

describe('commitImport', () => {
  it('imports, gets balances right, detects a re-import, and undoes/restores the batch', async () => {
    const { db, raw, axis, card, cash } = await setup();
    const rows = rowsOf(AXIS_CSV, 'bank');
    const plan = await planImport(db, axis.id, rows);
    const { batchId, count } = await commitImport(db, { accountId: axis.id, fileName: 'axis.csv', template: 'axis-bank', rows: plan });
    expect(count).toBe(5);

    const balances = Object.fromEntries((await accountsWithBalance(db)).map((a) => [a.id, a.balance]));
    // Opening 10,000 − 420 (manual Swiggy) + 90,000 − 2,000 − 8,360 − 7,500 + 245
    expect(balances[axis.id]).toBe(81_965_00);
    expect(balances[cash.id]).toBe(2_000_00);
    expect(balances[card.id]).toBe(8_360_00);
    const imported = (await listTransactions(db)).filter((t) => t.source === 'import');
    expect(imported).toHaveLength(5);

    // Same file again: everything is already there.
    const again = await planImport(db, axis.id, rows);
    expect(again.map((p) => p.status)).toEqual(['possible-duplicate', 'duplicate', 'duplicate', 'duplicate', 'duplicate', 'duplicate']);

    // Then the card statement: the bill payment matches the transfer from the bank import.
    const cardPlan = await planImport(db, card.id, rowsOf(AXIS_CARD_CSV, 'card'));
    expect(cardPlan.map((p) => [p.payee, p.type, p.status])).toEqual([
      ['Swiggy', 'expense', 'new'],
      ['Netflix', 'expense', 'new'],
      ['Credit card payment', 'transfer', 'possible-duplicate'],
      ['Amazon', 'expense', 'new'],
      ['Amazon', 'income', 'new'],
    ]);
    expect(cardPlan[4].categoryId).not.toBeNull(); // Refund

    await undoImport(db, batchId);
    expect((await listTransactions(db)).filter((t) => t.source === 'import')).toHaveLength(0);
    expect((await listImportBatches(db))[0].batch.undoneAt).not.toBeNull();
    await restoreImport(db, batchId);
    expect((await listTransactions(db)).filter((t) => t.source === 'import')).toHaveLength(5);

    // Import batches survive backups.
    const other = createTestDb();
    await restoreBackup(other.db, parseBackup(JSON.stringify(await exportBackup(db))));
    expect(await other.db.select().from(importBatches).all()).toHaveLength(1);
    other.raw.close();
    raw.close();
  });

  it('gives identical rows in one file different keys', () => {
    const row = { line: 1, date: 1, description: 'CHAI', reference: '', amount: 2000, direction: 'out' as const, balance: null };
    const [a, b] = rowKeys('acc', [row, { ...row, line: 2 }]);
    expect(a).not.toBe(b);
    expect(b).toBe(`${a}#2`);
  });
});
