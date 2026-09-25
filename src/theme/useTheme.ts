import { useColorScheme } from 'react-native';

import { usePrefs } from '@/stores/prefs';

import { ACCENTS, colors, type ColorTokens, type ThemeName } from './tokens';

export type Theme = { name: ThemeName; dark: boolean; colors: ColorTokens };

/** Current colours from the Light / Dark / AMOLED / System choice and the accent colour. */
export function useTheme(): Theme {
  const system = useColorScheme();
  const pref = usePrefs((s) => s.theme);
  const accent = usePrefs((s) => s.accent);
  const name: ThemeName = pref === 'system' ? (system === 'dark' ? 'dark' : 'light') : pref;
  const dark = name !== 'light';
  const accentColor = ACCENTS[accent]?.[dark ? 'dark' : 'light'] ?? colors[name].accent;
  return { name, dark, colors: { ...colors[name], accent: accentColor } };
}
