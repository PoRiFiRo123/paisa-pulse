import { create } from 'zustand';

type SelectionState = {
  active: boolean;
  ids: string[];
  /** Enter selection mode, optionally with one row already selected. */
  start: (id?: string) => void;
  toggle: (id: string) => void;
  setAll: (ids: string[]) => void;
  clear: () => void;
};

/** Multi-select for bulk edits in Activity. */
export const useSelection = create<SelectionState>((set) => ({
  active: false,
  ids: [],
  start: (id) => set({ active: true, ids: id ? [id] : [] }),
  toggle: (id) => set((s) => ({ ids: s.ids.includes(id) ? s.ids.filter((x) => x !== id) : [...s.ids, id] })),
  setAll: (ids) => set({ ids }),
  clear: () => set({ active: false, ids: [] }),
}));
