import { and, asc, eq, isNull } from 'drizzle-orm';

import { type CategoryKind, categories } from '@/db/schema';
import type { DB } from '@/db/types';

/** Active categories of one kind, parents and children flat, in display order. */
export function categoriesByKind(db: DB, kind: CategoryKind, { includeArchived = false } = {}) {
  const where = includeArchived
    ? eq(categories.kind, kind)
    : and(eq(categories.kind, kind), isNull(categories.archivedAt));
  return db.select().from(categories).where(where).orderBy(asc(categories.sortOrder), asc(categories.name));
}
