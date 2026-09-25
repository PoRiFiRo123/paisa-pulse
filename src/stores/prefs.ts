import { create } from 'zustand';

import { appDb } from '@/db/client';
import { getAllSettings, setSetting, type SettingsMap } from '@/db/settings';

export type Prefs = Pick<
  SettingsMap,
  'onboarded' | 'theme' | 'accent' | 'monthStartDay' | 'weekStartDay' | 'hideAmounts' | 'appLock'
> & { lastAccountId?: string };

const DEFAULTS: Prefs = {
  onboarded: false,
  theme: 'system',
  accent: 'indigo',
  monthStartDay: 1,
  weekStartDay: 1,
  hideAmounts: false,
  appLock: false,
};

type PrefsState = Prefs & {
  hydrated: boolean;
  hydrate: () => Promise<void>;
  set: <K extends keyof Prefs>(key: K, value: Prefs[K]) => void;
};

/** User preferences: kept in memory for rendering, persisted to the settings table. */
export const usePrefs = create<PrefsState>((set) => ({
  ...DEFAULTS,
  hydrated: false,
  hydrate: async () => {
    const stored = await getAllSettings(appDb);
    set({ ...DEFAULTS, ...stored, hydrated: true });
  },
  set: (key, value) => {
    set({ [key]: value } as Partial<PrefsState>);
    if (value !== undefined) setSetting(appDb, key, value as SettingsMap[typeof key]).catch(console.warn);
  },
}));
