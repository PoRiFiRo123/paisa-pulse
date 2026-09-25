/// <reference types="node" />
// Test-only: an in-memory database that runs the real migration SQL.
// Uses Node's built-in `node:sqlite` through Drizzle's sqlite-proxy driver.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import { drizzle } from 'drizzle-orm/sqlite-proxy';

import * as schema from '../schema';
import type { DB } from '../types';

export function createTestDb(): { db: DB; raw: DatabaseSync } {
  const raw = new DatabaseSync(':memory:');
  raw.exec('PRAGMA foreign_keys = ON;');

  const dir = join(__dirname, '..', 'migrations');
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
    for (const statement of readFileSync(join(dir, file), 'utf8').split('--> statement-breakpoint')) {
      if (statement.trim()) raw.exec(statement);
    }
  }

  const db = drizzle(
    async (sql, params, method) => {
      const stmt = raw.prepare(sql);
      if (method === 'run') {
        stmt.run(...params);
        return { rows: [] };
      }
      stmt.setReturnArrays(true);
      if (method === 'get') return { rows: (stmt.get(...params) ?? undefined) as unknown as unknown[] };
      return { rows: stmt.all(...params) as unknown as unknown[] };
    },
    { schema },
  );
  return { db: db as unknown as DB, raw };
}
