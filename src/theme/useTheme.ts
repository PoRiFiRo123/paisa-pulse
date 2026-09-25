import { useColorScheme } from 'react-native';

import { colors, type ColorTokens, type ThemeName } from './tokens';

// TODO: read the user's Light / Dark / AMOLED / System choice from settings.
export function useTheme(): { name: ThemeName; colors: ColorTokens } {
  const name: ThemeName = useColorScheme() === 'dark' ? 'dark' : 'light';
  return { name, colors: colors[name] };
}
