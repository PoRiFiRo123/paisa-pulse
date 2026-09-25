import { and, eq, isNull, sql } from 'drizzle-orm';

import { type Category, type CategoryKind, categories, transactions } from '@/db/schema';
import type { DB } from '@/db/types';
import { newId } from '@/lib/ids';

export type CategoryInput = {
  kind: CategoryKind;
  name: string;
  /** SF Symbol name. */
  icon: string;
  color: string;
  parentId?: string | null;
};

export class CategoryError extends Error {
  name = 'CategoryError';
}

async function getCategory(db: DB, id: string): Promise<Category> {
  const row = await db.select().from(categories).where(eq(categories.id, id)).get();
  if (!row) throw new CategoryError(`Category ${id} not found`);
  return row;
}

/** Nesting is two levels deep, and a child must share its parent's kind. */
async function assertValidParent(db: DB, kind: CategoryKind, parentId: string | null, selfId?: string) {
  if (!parentId) return;
  if (parentId === selfId) throw new CategoryError('A category cannot be its own parent');
  const parent = await getCategory(db, parentId);
  if (parent.parentId) throw new CategoryError('Categories can only be nested two levels deep');
  if (parent.kind !== kind) throw new CategoryError('Parent must be the same kind');
  if (selfId) {
    const child = await db.select({ id: categories.id }).from(categories).where(eq(categories.parentId, selfId)).get();
    if (child) throw new CategoryError('A category with subcategories cannot become a subcategory');
  }
}

export async function createCategory(db: DB, input: CategoryInput, now: number = Date.now()): Promise<Category> {
  const name = input.name.trim();
  if (!name) throw new CategoryError('Category name is required');
  const parentId = input.parentId ?? null;
  await assertValidParent(db, input.kind, parentId);
  const last = await db
    .select({ max: sql<number | null>`max(${categories.sortOrder})` })
    .from(categories)
    .where(and(eq(categories.kind, input.kind), parentId ? eq(categories.parentId, parentId) : isNull(categories.parentId)))
    .get();
  const row: Category = {
    id: newId(),
    parentId,
    kind: input.kind,
    name,
    icon: input.icon,
    color: input.color,
    sortOrder: (last?.max ?? -1) + 1,
    archivedAt: null,
    createdAt: now,
    updatedAt: now,
  };
  await db.insert(categories).values(row);
  return row;
}

/** Rename, recolour, change icon or parent. Kind is fixed once created. */
export async function updateCategory(
  db: DB,
  id: string,
  input: Omit<CategoryInput, 'kind'>,
  now: number = Date.now(),
): Promise<void> {
  const existing = await getCategory(db, id);
  const name = input.name.trim();
  if (!name) throw new CategoryError('Category name is required');
  const parentId = input.parentId ?? null;
  await assertValidParent(db, existing.kind, parentId, id);
  await db
    .update(categories)
    .set({ name, icon: input.icon, color: input.color, parentId, updatedAt: now })
    .where(eq(categories.id, id));
}

/** Persist a drag-to-reorder among siblings: `ids` in their new order. */
export async function reorderCategories(db: DB, ids: readonly string[], now: number = Date.now()): Promise<void> {
  for (const [sortOrder, id] of ids.entries()) {
    await db.update(categories).set({ sortOrder, updatedAt: now }).where(eq(categories.id, id));
  }
}

/** Archiving a parent archives its subcategories too; unarchiving restores only itself. */
export async function setCategoryArchived(db: DB, id: string, archived: boolean, now: number = Date.now()) {
  const archivedAt = archived ? now : null;
  await db.update(categories).set({ archivedAt, updatedAt: now }).where(eq(categories.id, id));
  if (archived) {
    await db.update(categories).set({ archivedAt, updatedAt: now }).where(eq(categories.parentId, id));
  }
}

/**
 * Merge `fromId` into `intoId`: every transaction moves across and `fromId` is archived.
 * Subcategories of `fromId` move under `intoId` when that keeps nesting at two levels.
 */
export async function mergeCategory(db: DB, fromId: string, intoId: string, now: number = Date.now()): Promise<void> {
  if (fromId === intoId) throw new CategoryError('Cannot merge a category into itself');
  const [from, into] = await Promise.all([getCategory(db, fromId), getCategory(db, intoId)]);
  if (from.kind !== into.kind) throw new CategoryError('Can only merge categories of the same kind');
  if (into.parentId === fromId) throw new CategoryError('Cannot merge a category into its own subcategory');

  const hasChildren = await db
    .select({ id: categories.id })
    .from(categories)
    .where(eq(categories.parentId, fromId))
    .get();
  if (hasChildren && into.parentId) {
    throw new CategoryError('Move or merge the subcategories first');
  }

  await db
    .update(transactions)
    .set({ categoryId: intoId, updatedAt: now })
    .where(eq(transactions.categoryId, fromId));
  if (hasChildren) {
    await db.update(categories).set({ parentId: intoId, updatedAt: now }).where(eq(categories.parentId, fromId));
  }
  await db.update(categories).set({ archivedAt: now, updatedAt: now }).where(eq(categories.id, fromId));
}
