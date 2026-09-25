import { create } from 'zustand';

export type Toast = { id: number; message: string; actionLabel?: string; onAction?: () => unknown };

/** The most recent undoable action; also reachable by shaking the phone. */
export type UndoEntry = { label: string; run: () => unknown; at: number };

/** Shake-to-undo stays available this long after the action, like iOS. */
export const UNDO_WINDOW_MS = 2 * 60_000;

type ToastState = {
  toast: Toast | null;
  lastUndo: UndoEntry | null;
  show: (t: Omit<Toast, 'id'>, durationMs?: number) => void;
  hide: () => void;
  /** Run the latest undo (toast button or shake) and forget it. */
  undo: () => void;
};

let timer: ReturnType<typeof setTimeout> | undefined;
let nextId = 1;

/** One toast at a time; the Undo toast stays for 5 seconds (SPEC §4.1). */
export const useToast = create<ToastState>((set, get) => ({
  toast: null,
  lastUndo: null,
  show: (t, durationMs = 5000) => {
    clearTimeout(timer);
    const toast = { ...t, id: nextId++ };
    set({
      toast,
      ...(t.onAction && t.actionLabel === 'Undo' ? { lastUndo: { label: t.message, run: t.onAction, at: Date.now() } } : {}),
    });
    timer = setTimeout(() => set((s) => (s.toast?.id === toast.id ? { toast: null } : s)), durationMs);
  },
  hide: () => {
    clearTimeout(timer);
    set({ toast: null });
  },
  undo: () => {
    const { lastUndo } = get();
    clearTimeout(timer);
    set({ toast: null, lastUndo: null });
    lastUndo?.run();
  },
}));
