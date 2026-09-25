import { drizzle, type ExpoSQLiteDatabase } from 'drizzle-orm/expo-sqlite';
import { openDatabaseAsync, openDatabaseSync } from 'expo-sqlite';
import { Platform } from 'react-native';

import * as schema from './schema';
import type { DB } from './types';

export const DATABASE_NAME = 'paisa-pulse.db';

type AppDrizzle = ExpoSQLiteDatabase<typeof schema>;

function open(): AppDrizzle {
  // enableChangeListener powers live queries.
  const expoDb = openDatabaseSync(DATABASE_NAME, { enableChangeListener: true });
  // WAL is not supported by the browser storage backend (web is only used for previews).
  expoDb.execSync(Platform.OS === 'web' ? 'PRAGMA foreign_keys = ON;' : 'PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');
  return drizzle(expoDb, { schema });
}

let webDb: AppDrizzle | undefined;

/**
 * The app database. On iOS/Android it opens synchronously at import. On web the SQLite
 * worker must boot first (see `prepareDatabase`), so the instance is created on first use.
 */
export const db: AppDrizzle =
  Platform.OS === 'web'
    ? new Proxy({} as AppDrizzle, {
        get(_target, prop) {
          webDb ??= open();
          const value = Reflect.get(webDb, prop, webDb);
          return typeof value === 'function' && prop !== 'constructor' ? value.bind(webDb) : value;
        },
      })
    : open();

/** The app database, typed as the shared `DB` that feature code accepts. */
export const appDb: DB = db as unknown as DB;

/** Web only: boot the SQLite worker asynchronously before the first synchronous call. */
export async function prepareDatabase(): Promise<void> {
  if (Platform.OS !== 'web' || webDb) return;
  const warm = await openDatabaseAsync(DATABASE_NAME);
  await warm.closeAsync();
}
