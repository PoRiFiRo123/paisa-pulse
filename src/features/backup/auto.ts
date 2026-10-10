import { format } from 'date-fns';

import { getSetting, setSetting, type SettingsMap } from '@/db/settings';
import type { DB } from '@/db/types';

import { exportBackup } from './backup';

export type BackupFrequency = 'off' | 'daily' | 'weekly';
export type AutoBackupSettings = SettingsMap['autoBackup'];

/** Where backups live: iCloud Drive (iOS) or this phone's app storage (Android: carried by Google backup). */
export type BackupStore = {
  kind: 'icloud' | 'device';
  label: string;
  available(): Promise<boolean>;
  list(): Promise<string[]>;
  write(name: string, text: string): Promise<void>;
  read(name: string): Promise<string>;
  remove(name: string): Promise<void>;
};

export type BackupFile = { name: string; at: number };

export const DEFAULT_AUTO_BACKUP: AutoBackupSettings = { frequency: 'daily', lastAt: null, lastError: null };
/** Backups kept per store; older ones are deleted after each new one. */
export const KEEP_BACKUPS = 14;

const INTERVAL: Record<Exclude<BackupFrequency, 'off'>, number> = { daily: 20 * 3_600_000, weekly: 6.5 * 86_400_000 };

export const backupFileName = (now: number) => `paisa-pulse-${format(now, 'yyyy-MM-dd-HHmm')}.json`;

/** "paisa-pulse-2026-10-10-1830.json" → its time, or null for other files. */
export function backupTime(name: string): number | null {
  const m = name.match(/^paisa-pulse-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})\.json$/);
  if (!m) return null;
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5])).getTime();
}

/** Backups in a store, newest first. */
export async function listBackups(store: BackupStore): Promise<BackupFile[]> {
  const names = await store.list();
  return names
    .map((name) => ({ name, at: backupTime(name) }))
    .filter((f): f is BackupFile => f.at !== null)
    .sort((a, b) => b.at - a.at);
}

/** Due when automatic backup is on and the last one is older than the interval (a little slack so a daily habit isn't skipped). */
export function isBackupDue(s: AutoBackupSettings, now: number): boolean {
  if (s.frequency === 'off') return false;
  return s.lastAt === null || now - s.lastAt >= INTERVAL[s.frequency];
}

export async function getAutoBackup(db: DB): Promise<AutoBackupSettings> {
  return { ...DEFAULT_AUTO_BACKUP, ...((await getSetting(db, 'autoBackup')) ?? {}) };
}

/** Write a full backup now and delete old ones beyond `KEEP_BACKUPS`. Records success or the error. */
export async function backUpNow(db: DB, store: BackupStore, now: number = Date.now()): Promise<BackupFile> {
  const settings = await getAutoBackup(db);
  try {
    const name = backupFileName(now);
    const backup = await exportBackup(db, now);
    // The backup records when it ran, so a restored phone doesn't immediately back up again.
    await store.write(name, JSON.stringify(backup));
    const all = await listBackups(store);
    for (const old of all.slice(KEEP_BACKUPS)) await store.remove(old.name).catch(() => {});
    await setSetting(db, 'autoBackup', { ...settings, lastAt: now, lastError: null, lastStore: store.kind });
    return { name, at: now };
  } catch (e) {
    await setSetting(db, 'autoBackup', { ...settings, lastError: e instanceof Error ? e.message : String(e) });
    throw e;
  }
}

/** Called at launch, on foreground and when going to the background. Never throws. */
export async function runAutoBackupIfDue(db: DB, store: BackupStore | null, now: number = Date.now()): Promise<boolean> {
  if (!store) return false;
  try {
    const settings = await getAutoBackup(db);
    if (!isBackupDue(settings, now)) return false;
    // Nothing worth backing up before onboarding.
    if (!(await getSetting(db, 'onboarded'))) return false;
    if (!(await store.available())) return false;
    await backUpNow(db, store, now);
    return true;
  } catch {
    return false;
  }
}
