import { create } from 'zustand';

export type Toast = { id: number; message: string; actionLabel?: string; onAction?: () => void };

type ToastState = {
  toast: Toast | null;
  show: (t: Omit<Toast, 'id'>, durationMs?: number) => void;
  hide: () => void;
};

let timer: ReturnType<typeof setTimeout> | undefined;
let nextId = 1;

/** One toast at a time; the Undo toast stays for 5 seconds (SPEC §4.1). */
export const useToast = create<ToastState>((set) => ({
  toast: null,
  show: (t, durationMs = 5000) => {
    clearTimeout(timer);
    const toast = { ...t, id: nextId++ };
    set({ toast });
    timer = setTimeout(() => set((s) => (s.toast?.id === toast.id ? { toast: null } : s)), durationMs);
  },
  hide: () => {
    clearTimeout(timer);
    set({ toast: null });
  },
}));
