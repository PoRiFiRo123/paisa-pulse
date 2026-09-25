import { eq } from 'drizzle-orm';

import { settings } from './schema';
import type { DB } from './types';

/** Typed app settings, stored as JSON in the `settings` table. */
export type SettingsMap = {
  'seed.categories': number;
  onboarded: boolean;
  theme: 'system' | 'light' | 'dark' | 'amoled';
  accent: 'indigo' | 'blue' | 'purple' | 'pink' | 'orange' | 'green' | 'teal';
  monthStartDay: number;
  weekStartDay: 0 | 1;
  hideAmounts: boolean;
  appLock: boolean;
  lastAccountId: string;
};

export async function getSetting<K extends keyof SettingsMap>(db: DB, key: K): Promise<SettingsMap[K] | undefined> {
  const row = await db.select().from(settings).where(eq(settings.key, key)).get();
  return row ? (JSON.parse(row.value) as SettingsMap[K]) : undefined;
}

export async function setSetting<K extends keyof SettingsMap>(db: DB, key: K, value: SettingsMap[K]): Promise<void> {
  const json = JSON.stringify(value);
  await db.insert(settings).values({ key, value: json }).onConflictDoUpdate({ target: settings.key, set: { value: json } });
}

/** All stored settings, for hydrating the in-memory preferences store. */
export async function getAllSettings(db: DB): Promise<Partial<SettingsMap>> {
  const rows = await db.select().from(settings).all();
  const out: Record<string, unknown> = {};
  for (const row of rows) out[row.key] = JSON.parse(row.value);
  return out as Partial<SettingsMap>;
}
