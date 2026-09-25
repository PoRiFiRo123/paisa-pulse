import { eq } from 'drizzle-orm';

import { settings } from './schema';
import type { DB } from './types';

/** Typed app settings, stored as JSON in the `settings` table. */
export type SettingsMap = {
  'seed.categories': number;
  theme: 'system' | 'light' | 'dark' | 'amoled';
  accentColor: string;
  monthStartDay: number;
  weekStartDay: 0 | 1;
  hideAmounts: boolean;
  appLock: boolean;
};

export async function getSetting<K extends keyof SettingsMap>(db: DB, key: K): Promise<SettingsMap[K] | undefined> {
  const row = await db.select().from(settings).where(eq(settings.key, key)).get();
  return row ? (JSON.parse(row.value) as SettingsMap[K]) : undefined;
}

export async function setSetting<K extends keyof SettingsMap>(db: DB, key: K, value: SettingsMap[K]): Promise<void> {
  const json = JSON.stringify(value);
  await db.insert(settings).values({ key, value: json }).onConflictDoUpdate({ target: settings.key, set: { value: json } });
}
