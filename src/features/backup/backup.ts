import { accounts, budgets, categories, recurringRules, savedFilters, settings, transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { formatINR } from '@/lib/money';

export const BACKUP_FORMAT = 'paisa-pulse-backup';
/** v2 adds recurring rules, budgets and saved filters. v1 files still restore. */
export const BACKUP_VERSION = 2;

export type Backup = {
  format: typeof BACKUP_FORMAT;
  version: number;
  exportedAt: number;
  accounts: (typeof accounts.$inferSelect)[];
  categories: (typeof categories.$inferSelect)[];
  transactions: (typeof transactions.$inferSelect)[];
  settings: (typeof settings.$inferSelect)[];
  recurringRules: (typeof recurringRules.$inferSelect)[];
  budgets: (typeof budgets.$inferSelect)[];
  savedFilters: (typeof savedFilters.$inferSelect)[];
};

export class BackupError extends Error {
  name = 'BackupError';
}

/** Everything in the database, including soft-deleted rows and archived items. */
export async function exportBackup(db: DB, now: number = Date.now()): Promise<Backup> {
  const [a, c, t, s, r, b, f] = await Promise.all([
    db.select().from(accounts).all(),
    db.select().from(categories).all(),
    db.select().from(transactions).all(),
    db.select().from(settings).all(),
    db.select().from(recurringRules).all(),
    db.select().from(budgets).all(),
    db.select().from(savedFilters).all(),
  ]);
  return {
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    exportedAt: now,
    accounts: a,
    categories: c,
    transactions: t,
    settings: s,
    recurringRules: r,
    budgets: b,
    savedFilters: f,
  };
}

export function parseBackup(json: string): Backup {
  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch {
    throw new BackupError('This file is not a Paisa Pulse backup.');
  }
  const b = data as Partial<Backup>;
  if (b?.format !== BACKUP_FORMAT || typeof b.version !== 'number') throw new BackupError('This file is not a Paisa Pulse backup.');
  if (b.version > BACKUP_VERSION) throw new BackupError('This backup was made by a newer version of Paisa Pulse.');
  for (const key of ['accounts', 'categories', 'transactions', 'settings'] as const) {
    if (!Array.isArray(b[key])) throw new BackupError(`Backup is missing ${key}.`);
  }
  // Tables added after v1 are optional in older files.
  b.recurringRules ??= [];
  b.budgets ??= [];
  b.savedFilters ??= [];
  for (const t of b.transactions!) {
    t.recurringId ??= null;
    if (!Number.isSafeInteger(t.amount) || t.amount <= 0) throw new BackupError('Backup contains an invalid amount.');
  }
  return b as Backup;
}

/**
 * Replace all data with a backup. Rows are inserted parents-first so foreign keys hold;
 * any constraint failure throws before the app state is trusted again.
 */
export async function restoreBackup(db: DB, backup: Backup): Promise<void> {
  await db.delete(transactions);
  await db.delete(budgets);
  await db.delete(recurringRules);
  await db.delete(savedFilters);
  await db.delete(categories);
  await db.delete(accounts);
  await db.delete(settings);

  const chunk = <T,>(rows: T[], size = 200) =>
    Array.from({ length: Math.ceil(rows.length / size) }, (_, i) => rows.slice(i * size, (i + 1) * size));

  for (const rows of chunk(backup.accounts)) await db.insert(accounts).values(rows);
  const parentsFirst = [...backup.categories].sort((x, y) => Number(x.parentId !== null) - Number(y.parentId !== null));
  for (const rows of chunk(parentsFirst)) await db.insert(categories).values(rows);
  for (const rows of chunk(backup.recurringRules)) await db.insert(recurringRules).values(rows);
  for (const rows of chunk(backup.transactions)) await db.insert(transactions).values(rows);
  for (const rows of chunk(backup.budgets)) await db.insert(budgets).values(rows);
  for (const rows of chunk(backup.savedFilters)) await db.insert(savedFilters).values(rows);
  for (const rows of chunk(backup.settings)) await db.insert(settings).values(rows);
}

function csvCell(value: string | number | null | undefined): string {
  if (value === null || value === undefined) return '';
  const s = String(value);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function isoLocal(ms: number): string {
  const d = new Date(ms);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** Spreadsheet-friendly CSV of live transactions, newest first. Amounts in rupees. */
export async function exportCsv(db: DB): Promise<string> {
  const backup = await exportBackup(db);
  const acc = new Map(backup.accounts.map((a) => [a.id, a.name]));
  const cat = new Map(backup.categories.map((c) => [c.id, c]));
  const header = ['Date', 'Type', 'Amount', 'Account', 'To account', 'Category', 'Subcategory', 'Payee', 'Note', 'ID'];
  const rows = backup.transactions
    .filter((t) => t.deletedAt === null)
    .sort((a, b) => b.occurredAt - a.occurredAt)
    .map((t) => {
      const c = t.categoryId ? cat.get(t.categoryId) : undefined;
      const parent = c?.parentId ? cat.get(c.parentId) : undefined;
      return [
        isoLocal(t.occurredAt),
        t.type,
        formatINR(t.amount, { symbol: false }).replace(/,/g, ''),
        acc.get(t.accountId) ?? '',
        t.toAccountId ? (acc.get(t.toAccountId) ?? '') : '',
        parent ? parent.name : (c?.name ?? (t.type === 'transfer' ? '' : 'Uncategorised')),
        parent ? c?.name : '',
        t.payee,
        t.note,
        t.id,
      ]
        .map(csvCell)
        .join(',');
    });
  return [header.join(','), ...rows].join('\n') + '\n';
}
