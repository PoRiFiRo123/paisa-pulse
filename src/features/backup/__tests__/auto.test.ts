/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';
import { setSetting } from '@/db/settings';
import { createAccount } from '@/features/accounts/mutations';

import { type BackupStore, backUpNow, backupFileName, backupTime, getAutoBackup, isBackupDue, KEEP_BACKUPS, listBackups, runAutoBackupIfDue } from '../auto';
import { parseBackup } from '../backup';

function memoryStore(): BackupStore & { files: Map<string, string> } {
  const files = new Map<string, string>();
  return {
    kind: 'device',
    label: 'Memory',
    files,
    available: async () => true,
    list: async () => [...files.keys(), 'notes.txt'],
    write: async (n, t) => void files.set(n, t),
    read: async (n) => files.get(n)!,
    remove: async (n) => void files.delete(n),
  };
}

const HOUR = 3_600_000;
const T0 = new Date(2026, 9, 10, 18, 30).getTime();

describe('automatic backup', () => {
  it('names files by time and reads them back', () => {
    expect(backupFileName(T0)).toBe('paisa-pulse-2026-10-10-1830.json');
    expect(backupTime('paisa-pulse-2026-10-10-1830.json')).toBe(T0);
    expect(backupTime('notes.txt')).toBeNull();
  });

  it('is due by frequency', () => {
    expect(isBackupDue({ frequency: 'off', lastAt: null, lastError: null }, T0)).toBe(false);
    expect(isBackupDue({ frequency: 'daily', lastAt: null, lastError: null }, T0)).toBe(true);
    expect(isBackupDue({ frequency: 'daily', lastAt: T0 - 10 * HOUR, lastError: null }, T0)).toBe(false);
    expect(isBackupDue({ frequency: 'daily', lastAt: T0 - 21 * HOUR, lastError: null }, T0)).toBe(true);
    expect(isBackupDue({ frequency: 'weekly', lastAt: T0 - 3 * 24 * HOUR, lastError: null }, T0)).toBe(false);
  });

  it('backs up when due, after onboarding, and keeps the newest files', async () => {
    const { db, raw } = createTestDb();
    const store = memoryStore();
    await createAccount(db, { name: 'Axis', type: 'bank', color: '#000', icon: 'x' }, T0);
    expect(await runAutoBackupIfDue(db, store, T0)).toBe(false); // not onboarded yet
    await setSetting(db, 'onboarded', true);
    expect(await runAutoBackupIfDue(db, store, T0)).toBe(true);
    expect(await runAutoBackupIfDue(db, store, T0 + HOUR)).toBe(false);
    const [file] = await listBackups(store);
    expect(parseBackup(store.files.get(file.name)!).accounts).toHaveLength(1);
    expect(await getAutoBackup(db)).toMatchObject({ lastAt: T0, lastError: null, lastStore: 'device' });

    for (let i = 1; i <= KEEP_BACKUPS + 3; i++) await backUpNow(db, store, T0 + i * 24 * HOUR);
    const kept = await listBackups(store);
    expect(kept).toHaveLength(KEEP_BACKUPS);
    expect(kept[0].at).toBe(T0 + (KEEP_BACKUPS + 3) * 24 * HOUR);
    raw.close();
  });

  it('records failures without throwing from the automatic path', async () => {
    const { db, raw } = createTestDb();
    await setSetting(db, 'onboarded', true);
    const broken = { ...memoryStore(), write: async () => Promise.reject(new Error('iCloud is full')) };
    expect(await runAutoBackupIfDue(db, broken, T0)).toBe(false);
    expect((await getAutoBackup(db)).lastError).toBe('iCloud is full');
    raw.close();
  });
});
