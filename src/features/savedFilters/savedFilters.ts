import { asc, eq, sql } from 'drizzle-orm';

import { savedFilters } from '@/db/schema';
import type { DB } from '@/db/types';
import { newId } from '@/lib/ids';
import type { ActivityFilters } from '@/stores/ui';

export type FilterPayload = { filters: ActivityFilters; search: string };

const EMPTY: FilterPayload = { filters: { monthOffset: null, accountIds: [], categoryIds: [], types: [] }, search: '' };

/** Parse a stored payload defensively (older or hand-edited backups). */
export function parsePayload(json: string): FilterPayload {
  try {
    const p = JSON.parse(json) as Partial<FilterPayload>;
    const f = (p.filters ?? {}) as Partial<ActivityFilters>;
    return {
      search: typeof p.search === 'string' ? p.search : '',
      filters: {
        monthOffset: typeof f.monthOffset === 'number' ? f.monthOffset : null,
        accountIds: Array.isArray(f.accountIds) ? f.accountIds : [],
        categoryIds: Array.isArray(f.categoryIds) ? f.categoryIds : [],
        types: Array.isArray(f.types) ? f.types : [],
      },
    };
  } catch {
    return EMPTY;
  }
}

export async function listSavedFilters(db: DB) {
  const rows = await db.select().from(savedFilters).orderBy(asc(savedFilters.sortOrder), asc(savedFilters.createdAt));
  return rows.map((r) => ({ ...r, payload: parsePayload(r.filters) }));
}

export async function saveFilter(db: DB, name: string, payload: FilterPayload, now: number = Date.now()) {
  const trimmed = name.trim();
  if (!trimmed) throw new Error('Give the filter a name');
  const last = await db.select({ max: sql<number | null>`max(${savedFilters.sortOrder})` }).from(savedFilters).get();
  const row = { id: newId(), name: trimmed, filters: JSON.stringify(payload), sortOrder: (last?.max ?? -1) + 1, createdAt: now, updatedAt: now };
  await db.insert(savedFilters).values(row);
  return row;
}

export async function updateSavedFilter(db: DB, id: string, patch: { name?: string; payload?: FilterPayload }, now: number = Date.now()) {
  await db
    .update(savedFilters)
    .set({
      ...(patch.name !== undefined ? { name: patch.name.trim() } : {}),
      ...(patch.payload ? { filters: JSON.stringify(patch.payload) } : {}),
      updatedAt: now,
    })
    .where(eq(savedFilters.id, id));
}

export async function deleteSavedFilter(db: DB, id: string) {
  await db.delete(savedFilters).where(eq(savedFilters.id, id));
}
