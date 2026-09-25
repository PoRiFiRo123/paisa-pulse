// Colour tokens from the Figma Foundations page (see CLAUDE.md).

export type ThemeName = 'light' | 'dark' | 'amoled';

export type ColorTokens = {
  background: string;
  card: string;
  label: string;
  secondary: string;
  separator: string;
  accent: string;
  expense: string;
  income: string;
};

export const colors: Record<ThemeName, ColorTokens> = {
  light: {
    background: '#F2F2F7',
    card: '#FFFFFF',
    label: '#000000',
    secondary: '#8A8A8E',
    separator: '#E3E3E8',
    accent: '#5E5CE6',
    expense: '#FF3B30',
    income: '#34C759',
  },
  dark: {
    background: '#000000',
    card: '#1C1C1E',
    label: '#FFFFFF',
    secondary: '#8E8E93',
    separator: '#2C2C2E',
    accent: '#7D7AFF',
    expense: '#FF453A',
    income: '#30D158',
  },
  // Pure black surfaces for OLED screens; cards get a hairline-dark fill so they still read.
  amoled: {
    background: '#000000',
    card: '#0A0A0A',
    label: '#FFFFFF',
    secondary: '#8E8E93',
    separator: '#1C1C1E',
    accent: '#7D7AFF',
    expense: '#FF453A',
    income: '#30D158',
  },
};

export const categoryColors = {
  food: '#FF9500',
  groceries: '#34C759',
  transport: '#007AFF',
  shopping: '#FF2D55',
  bills: '#FFB800',
  rent: '#AF52DE',
  entertainment: '#5856D6',
  health: '#FF3B30',
  subscriptions: '#32ADE6',
  salary: '#30B0C7',
} as const;
