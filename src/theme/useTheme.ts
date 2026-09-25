import { useColorScheme } from 'react-native';

import { useA11y } from '@/stores/a11y';
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
  const increaseContrast = useA11y((a) => a.increaseContrast);
  const accentColor = ACCENTS[accent]?.[dark ? 'dark' : 'light'] ?? colors[name].accent;
  const base = { ...colors[name], accent: accentColor };
  return { name, dark, colors: increaseContrast ? { ...base, ...(dark ? HIGH_CONTRAST_DARK : HIGH_CONTRAST_LIGHT) } : base };
}

// Increase Contrast: stronger secondary text, dividers and glass (Apple's high-contrast system colours).
const HIGH_CONTRAST_LIGHT: Partial<ColorTokens> = {
  secondary: '#6C6C70',
  separator: '#C6C6C8',
  rowDivider: '#8E8E93',
  glassBorder: 'rgba(0,0,0,0.35)',
  glassLabelSecondary: 'rgba(0,0,0,0.85)',
};
const HIGH_CONTRAST_DARK: Partial<ColorTokens> = {
  secondary: '#AEAEB2',
  separator: '#545458',
  rowDivider: '#8E8E93',
  glassBorder: 'rgba(255,255,255,0.5)',
  glassLabelSecondary: 'rgba(255,255,255,0.9)',
};
