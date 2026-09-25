import { drizzle } from 'drizzle-orm/expo-sqlite';
import { openDatabaseSync } from 'expo-sqlite';

import * as schema from './schema';
import type { DB } from './types';

export const DATABASE_NAME = 'paisa-pulse.db';

// enableChangeListener powers Drizzle's useLiveQuery.
export const expoDb = openDatabaseSync(DATABASE_NAME, { enableChangeListener: true });
expoDb.execSync('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');

export const db = drizzle(expoDb, { schema });

/** The app database, typed as the shared `DB` that feature code accepts. */
export const appDb: DB = db as unknown as DB;
