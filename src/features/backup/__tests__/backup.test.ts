/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { seedStarterCategories } from '@/db/seed';
import { setSetting } from '@/db/settings';
import { createAccount } from '@/features/accounts/mutations';
import { accountsWithBalance } from '@/features/accounts/queries';
import { categoriesByKind } from '@/features/categories/queries';
import { createCategory } from '@/features/categories/mutations';
import { createTransaction, deleteTransaction } from '@/features/transactions/mutations';

import { BackupError, exportBackup, exportCsv, parseBackup, restoreBackup } from '../backup';

const NOW = new Date(2026, 8, 25, 13, 24).getTime();

async function populate(db: ReturnType<typeof createTestDb>['db']) {
  await seedStarterCategories(db, NOW);
  const food = (await categoriesByKind(db, 'expense')).find((c) => c.name === 'Food & Dining')!;
  const cafe = await createCategory(db, { kind: 'expense', name: 'Cafés', icon: 'cup.and.saucer.fill', color: '#FF9500', parentId: food.id }, NOW);
  const axis = await createAccount(db, { name: 'Axis Bank', type: 'bank', openingBalance: 1_000_00, color: '#AE275F', icon: 'building.columns.fill' }, NOW);
  const card = await createAccount(db, { name: 'Axis MyZone', type: 'card', color: '#5E5CE6', icon: 'creditcard.fill' }, NOW);
  await createTransaction(db, { type: 'expense', amount: 420_00, accountId: axis.id, categoryId: cafe.id, payee: 'Swiggy, "Koramangala"', note: 'Lunch\nwith team' }, NOW);
  await createTransaction(db, { type: 'transfer', amount: 5_000_00, accountId: axis.id, toAccountId: card.id }, NOW - 1000);
  const gone = await createTransaction(db, { type: 'expense', amount: 1_00, accountId: card.id }, NOW - 2000);
  await deleteTransaction(db, gone.id, NOW);
  await setSetting(db, 'theme', 'dark');
}

describe('backup', () => {
  it('round-trips everything through JSON', async () => {
    const a = createTestDb();
    await populate(a.db);
    const backup = await exportBackup(a.db, NOW);
    const json = JSON.stringify(backup);

    const b = createTestDb();
    await seedStarterCategories(b.db, NOW); // restoring replaces existing data
    await restoreBackup(b.db, parseBackup(json));
    const again = await exportBackup(b.db, NOW);

    const sortById = <T extends { id: string }>(rows: T[]) => [...rows].sort((x, y) => x.id.localeCompare(y.id));
    expect(sortById(again.accounts)).toEqual(sortById(backup.accounts));
    expect(sortById(again.categories)).toEqual(sortById(backup.categories));
    expect(sortById(again.transactions)).toEqual(sortById(backup.transactions));
    expect(again.settings).toEqual(expect.arrayContaining(backup.settings));
    expect(await accountsWithBalance(b.db)).toEqual(await accountsWithBalance(a.db));
    a.raw.close();
    b.raw.close();
  });

  it('rejects files that are not backups', () => {
    expect(() => parseBackup('nope')).toThrow(BackupError);
    expect(() => parseBackup('{"format":"other"}')).toThrow(BackupError);
    expect(() => parseBackup(JSON.stringify({ format: 'paisa-pulse-backup', version: 99 }))).toThrow('newer version');
  });

  it('exports live transactions to CSV with quoting', async () => {
    const { db, raw } = createTestDb();
    await populate(db);
    const lines = (await exportCsv(db)).trimEnd().split('\n');
    expect(lines[0]).toBe('Date,Type,Amount,Account,To account,Category,Subcategory,Payee,Note,ID');
    expect(lines[1]).toMatch(/^2026-09-25 13:24,expense,420\.00,Axis Bank,,Food & Dining,Cafés,"Swiggy, ""Koramangala""","Lunch$/);
    expect(lines.some((l) => l.includes(',transfer,5000.00,Axis Bank,Axis MyZone,,,'))).toBe(true);
    expect(lines.filter((l) => l.includes(',expense,1.00,'))).toHaveLength(0);
    raw.close();
  });
});
