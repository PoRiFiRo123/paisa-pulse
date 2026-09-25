import type { BaseSQLiteDatabase } from 'drizzle-orm/sqlite-core';

import type * as schema from './schema';

/**
 * Any Drizzle SQLite database with our schema: the expo-sqlite one in the app,
 * an in-memory one in tests. Feature code takes this so it can be unit tested.
 */
export type DB = BaseSQLiteDatabase<'sync' | 'async', any, typeof schema>;
