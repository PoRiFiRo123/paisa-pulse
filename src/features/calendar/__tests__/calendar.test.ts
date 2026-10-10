/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { createAccount } from '@/features/accounts/mutations';
import { createTransaction } from '@/features/transactions/mutations';
import { formatINRTiny } from '@/lib/money';

import { dailyTotals, heat, monthGrid } from '../calendar';

describe('calendar', () => {
  it('groups totals by local day and skips transfers', async () => {
    const { db, raw } = createTestDb();
    const now = new Date(2026, 9, 20).getTime();
    const a = await createAccount(db, { name: 'Axis', type: 'bank', color: '#000', icon: 'x' }, now);
    const b = await createAccount(db, { name: 'Card', type: 'card', color: '#000', icon: 'x' }, now);
    await createTransaction(db, { type: 'expense', amount: 250_00, accountId: a.id, occurredAt: new Date(2026, 9, 5, 9).getTime() }, now);
    await createTransaction(db, { type: 'expense', amount: 50_00, accountId: a.id, occurredAt: new Date(2026, 9, 5, 23, 30).getTime() }, now);
    await createTransaction(db, { type: 'income', amount: 1000_00, accountId: a.id, occurredAt: new Date(2026, 9, 6, 0, 10).getTime() }, now);
    await createTransaction(db, { type: 'transfer', amount: 5000_00, accountId: a.id, toAccountId: b.id, occurredAt: new Date(2026, 9, 6).getTime() }, now);
    const totals = await dailyTotals(db, { start: new Date(2026, 9, 1).getTime(), end: new Date(2026, 10, 1).getTime() });
    expect(totals.get('2026-10-05')).toEqual({ spent: 300_00, received: 0, count: 2 });
    expect(totals.get('2026-10-06')).toEqual({ spent: 0, received: 1000_00, count: 2 });
    raw.close();
  });

  it('lays out whole weeks', () => {
    const g = monthGrid(new Date(2026, 9, 15).getTime(), 1);
    expect(g.cells.length % 7).toBe(0);
    expect(g.cells[0].key).toBe('2026-09-28'); // Monday before 1 Oct (a Thursday)
    expect(g.cells.filter((c) => c.inMonth)).toHaveLength(31);
    expect(monthGrid(new Date(2026, 1, 1).getTime(), 0).cells[0].key).toBe('2026-02-01'); // Feb 2026 starts on Sunday
  });

  it('scales heat and formats tiny amounts', () => {
    expect(heat(0, 100)).toBe(0);
    expect(heat(25, 100)).toBe(0.5);
    expect(formatINRTiny(950_00)).toBe('950');
    expect(formatINRTiny(12_550_00)).toBe('12.5k');
    expect(formatINRTiny(1_25_000_00)).toBe('1.2L');
    expect(formatINRTiny(3_45_00_000_00)).toBe('3.4Cr');
    expect(formatINRTiny(-1_000_00)).toBe('1k');
  });
});
