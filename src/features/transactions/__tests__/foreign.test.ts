/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { exportBackup, exportCsv, parseBackup, restoreBackup } from '@/features/backup/backup';

import { listTransactions } from '../list';
import { createTransaction, duplicateTransaction, updateTransaction } from '../mutations';
import { TransactionValidationError } from '../validation';

describe('foreign-currency transactions', () => {
  it('store the original amount next to the INR amount', async () => {
    const { db, raw } = createTestDb();
    const now = Date.now();
    const card = await createAccount(db, { name: 'MyZone', type: 'card', color: '#000', icon: 'x' }, now);
    const t = await createTransaction(db, { type: 'expense', amount: 1027_31, accountId: card.id, payee: 'Starbucks', currency: 'usd', originalAmount: 1234 }, now);
    expect(t).toMatchObject({ currency: 'USD', originalAmount: 1234 });
    const [row] = await listTransactions(db, { id: t.id });
    expect(row).toMatchObject({ amount: 1027_31, currency: 'USD', originalAmount: 1234 });
    expect((await duplicateTransaction(db, t.id, now)).currency).toBe('USD');
    expect(await exportCsv(db)).toContain(',$12.34,');

    // INR clears the foreign fields.
    await updateTransaction(db, t.id, { type: 'expense', amount: 1000_00, accountId: card.id, currency: 'INR', originalAmount: 1234 }, now);
    expect((await listTransactions(db, { id: t.id }))[0]).toMatchObject({ currency: null, originalAmount: null });

    await expect(createTransaction(db, { type: 'expense', amount: 100, accountId: card.id, currency: 'EUR', originalAmount: 0 }, now)).rejects.toBeInstanceOf(
      TransactionValidationError,
    );

    const other = createTestDb();
    await restoreBackup(other.db, parseBackup(JSON.stringify(await exportBackup(db))));
    expect((await listTransactions(other.db)).filter((x) => x.currency === 'USD')).toHaveLength(1);
    raw.close();
    other.raw.close();
  });

  it('restores older backups without currency fields', () => {
    const old = { format: 'paisa-pulse-backup', version: 3, exportedAt: 0, accounts: [], categories: [], settings: [], budgets: [{ id: 'b', categoryId: null, amount: 1, createdAt: 0, updatedAt: 0 }], transactions: [{ id: 't', amount: 100 }] };
    const parsed = parseBackup(JSON.stringify(old));
    expect(parsed.transactions[0]).toMatchObject({ currency: null, originalAmount: null });
    expect(parsed.budgets[0].period).toBe('monthly');
  });
});
