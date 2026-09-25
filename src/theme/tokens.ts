// Colour tokens from the Figma Foundations page (node 5:3).

export type ThemeName = 'light' | 'dark' | 'amoled';

export type ColorTokens = {
  background: string;
  card: string;
  label: string;
  secondary: string;
  separator: string;
  /** Hairline between list rows (Figma Row Divider). */
  rowDivider: string;
  accent: string;
  expense: string;
  income: string;
  /** Soft fill for chips, search fields and inactive keys. */
  fill: string;
  /** Liquid Glass stand-in fill and rim for the blur fallback. */
  glassFill: string;
  glassBorder: string;
  /** Hero card text on glass. */
  glassLabelSecondary: string;
  positiveTrend: string;
  /** Top of the Home aurora gradient. */
  aurora: [string, string, string];
};

const light: ColorTokens = {
  background: '#F2F2F7',
  card: '#FFFFFF',
  label: '#000000',
  secondary: '#8A8A8E',
  separator: '#E3E3E8',
  rowDivider: '#C6C6C8',
  accent: '#5E5CE6',
  expense: '#FF3B30',
  income: '#34C759',
  fill: 'rgba(118,118,128,0.12)',
  glassFill: 'rgba(255,255,255,0.3)',
  glassBorder: 'rgba(255,255,255,0.6)',
  glassLabelSecondary: 'rgba(28,28,30,0.7)',
  positiveTrend: '#1E8E3E',
  aurora: ['#665CF2', 'rgba(153,184,255,0.6)', '#F2F2F7'],
};

const dark: ColorTokens = {
  background: '#000000',
  card: '#1C1C1E',
  label: '#FFFFFF',
  secondary: '#8E8E93',
  separator: '#2C2C2E',
  rowDivider: '#38383A',
  accent: '#7D7AFF',
  expense: '#FF453A',
  income: '#30D158',
  fill: 'rgba(118,118,128,0.24)',
  glassFill: 'rgba(60,60,67,0.3)',
  glassBorder: 'rgba(255,255,255,0.18)',
  glassLabelSecondary: 'rgba(235,235,245,0.7)',
  positiveTrend: '#30D158',
  aurora: ['#3B34A8', 'rgba(60,70,150,0.45)', '#000000'],
};

export const colors: Record<ThemeName, ColorTokens> = {
  light,
  dark,
  // Pure black surfaces for OLED screens.
  amoled: { ...dark, card: '#0A0A0A', separator: '#1C1C1E', rowDivider: '#1C1C1E' },
};

export const ACCENTS = {
  indigo: { name: 'Indigo', light: '#5E5CE6', dark: '#7D7AFF' },
  blue: { name: 'Blue', light: '#007AFF', dark: '#0A84FF' },
  purple: { name: 'Purple', light: '#AF52DE', dark: '#BF5AF2' },
  pink: { name: 'Pink', light: '#FF2D55', dark: '#FF375F' },
  orange: { name: 'Orange', light: '#FF9500', dark: '#FF9F0A' },
  green: { name: 'Green', light: '#34C759', dark: '#30D158' },
  teal: { name: 'Teal', light: '#30B0C7', dark: '#40C8E0' },
} as const;
export type AccentKey = keyof typeof ACCENTS;

/** Colours offered when creating accounts and categories. */
export const PALETTE = [
  '#FF3B30', '#FF9500', '#FFB800', '#34C759', '#30B0C7', '#32ADE6', '#007AFF',
  '#5E5CE6', '#5856D6', '#AF52DE', '#FF2D55', '#A2845E', '#8E8E93', '#1E9E5A',
];

export const UNCATEGORISED_COLOR = '#8E8E93';
export const TRANSFER_COLOR = '#8E8E93';
