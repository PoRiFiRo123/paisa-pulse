import { create } from 'zustand';

import type { TransactionType } from '@/db/schema';

export type ActivityFilters = {
  /** Months back from the current month; null = all time. */
  monthOffset: number | null;
  accountIds: string[];
  /** `null` inside the list = Uncategorised. */
  categoryIds: (string | null)[];
  types: TransactionType[];
};

type UiState = {
  /** Home hero: 0 = this month, 1 = last month, … */
  homeMonthOffset: number;
  setHomeMonthOffset: (n: number) => void;
  activity: ActivityFilters;
  setActivity: (patch: Partial<ActivityFilters>) => void;
  resetActivity: () => void;
};

const DEFAULT_ACTIVITY: ActivityFilters = { monthOffset: 0, accountIds: [], categoryIds: [], types: [] };

export const useUi = create<UiState>((set) => ({
  homeMonthOffset: 0,
  setHomeMonthOffset: (homeMonthOffset) => set({ homeMonthOffset }),
  activity: DEFAULT_ACTIVITY,
  setActivity: (patch) => set((s) => ({ activity: { ...s.activity, ...patch } })),
  resetActivity: () => set({ activity: DEFAULT_ACTIVITY }),
}));
