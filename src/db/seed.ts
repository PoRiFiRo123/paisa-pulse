import { newId } from '@/lib/ids';

import { type CategoryKind, categories, type NewCategory } from './schema';
import { getSetting, setSetting } from './settings';
import type { DB } from './types';

type StarterCategory = {
  name: string;
  /** SF Symbol name. Android maps these to Material Symbols. */
  icon: string;
  color: string;
  children?: Omit<StarterCategory, 'color' | 'children'>[];
};

/** Starter pack for India (SPEC §4.3). Subcategories inherit the parent colour. */
export const STARTER_CATEGORIES: Record<CategoryKind, StarterCategory[]> = {
  expense: [
    { name: 'Food & Dining', icon: 'fork.knife', color: '#FF9500' },
    { name: 'Groceries', icon: 'cart.fill', color: '#34C759' },
    {
      name: 'Transport',
      icon: 'car.fill',
      color: '#007AFF',
      children: [
        { name: 'Fuel', icon: 'fuelpump.fill' },
        { name: 'Metro/Auto/Cab', icon: 'tram.fill' },
      ],
    },
    { name: 'Shopping', icon: 'bag.fill', color: '#FF2D55' },
    {
      name: 'Bills & Utilities',
      icon: 'doc.text.fill',
      color: '#FFB800',
      children: [
        { name: 'Electricity', icon: 'bolt.fill' },
        { name: 'Mobile/Internet', icon: 'wifi' },
        { name: 'DTH', icon: 'tv.fill' },
      ],
    },
    { name: 'Rent', icon: 'house.fill', color: '#AF52DE' },
    { name: 'EMI/Loans', icon: 'building.columns.fill', color: '#8E8E93' },
    { name: 'Health', icon: 'cross.case.fill', color: '#FF3B30' },
    { name: 'Entertainment', icon: 'popcorn.fill', color: '#5856D6' },
    { name: 'Subscriptions', icon: 'repeat.circle.fill', color: '#32ADE6' },
    { name: 'Travel', icon: 'airplane', color: '#00C7BE' },
    { name: 'Education', icon: 'graduationcap.fill', color: '#A2845E' },
    { name: 'Gifts & Donations', icon: 'gift.fill', color: '#E0457B' },
    { name: 'Investments', icon: 'chart.line.uptrend.xyaxis', color: '#1E9E5A' },
    { name: 'Personal Care', icon: 'sparkles', color: '#C969E0' },
    { name: 'Family', icon: 'figure.2.and.child.holdinghands', color: '#FF8C69' },
  ],
  income: [
    { name: 'Salary', icon: 'banknote.fill', color: '#30B0C7' },
    { name: 'Freelance', icon: 'laptopcomputer', color: '#5E5CE6' },
    { name: 'Interest', icon: 'percent', color: '#34C759' },
    { name: 'Refund', icon: 'arrow.uturn.backward.circle.fill', color: '#007AFF' },
    { name: 'Cashback', icon: 'indianrupeesign.circle.fill', color: '#FF9500' },
    { name: 'Other', icon: 'ellipsis.circle.fill', color: '#8E8E93' },
  ],
};

/** Bump when the starter pack changes in a way existing installs should receive. */
const SEED_VERSION = 1;

export function buildStarterCategoryRows(now: number = Date.now()): NewCategory[] {
  const rows: NewCategory[] = [];
  for (const kind of ['expense', 'income'] as const) {
    STARTER_CATEGORIES[kind].forEach((cat, i) => {
      const id = newId();
      const base = { kind, color: cat.color, archivedAt: null, createdAt: now, updatedAt: now };
      rows.push({ ...base, id, parentId: null, name: cat.name, icon: cat.icon, sortOrder: i });
      cat.children?.forEach((child, j) => {
        rows.push({ ...base, id: newId(), parentId: id, name: child.name, icon: child.icon, sortOrder: j });
      });
    });
  }
  return rows;
}

/** Insert the starter categories once per install. Safe to call on every launch. */
export async function seedStarterCategories(db: DB, now: number = Date.now()): Promise<boolean> {
  const seeded = await getSetting(db, 'seed.categories');
  if (seeded !== undefined && seeded >= SEED_VERSION) return false;
  // Parents come before children in the list, so the foreign keys are satisfied in order.
  await db.insert(categories).values(buildStarterCategoryRows(now));
  await setSetting(db, 'seed.categories', SEED_VERSION);
  return true;
}
