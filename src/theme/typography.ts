import { Platform, type TextStyle } from 'react-native';

// Type scale from Figma Foundations. Figma uses Inter as a stand-in; the app uses
// SF Pro (system) and SF Pro Rounded for amounts.
const rounded: TextStyle = Platform.select({ ios: { fontFamily: 'ui-rounded' }, default: {} });
const tabular: TextStyle = { fontVariant: ['tabular-nums'] };

export const type = {
  amount: { fontSize: 52, fontWeight: '700', letterSpacing: -1.5, ...rounded, ...tabular },
  amountMedium: { fontSize: 34, fontWeight: '700', letterSpacing: -0.8, ...rounded, ...tabular },
  largeTitle: { fontSize: 34, fontWeight: '700', letterSpacing: -0.8 },
  title2: { fontSize: 22, fontWeight: '700', letterSpacing: -0.4 },
  title3: { fontSize: 20, fontWeight: '700', letterSpacing: -0.2 },
  headline: { fontSize: 17, fontWeight: '600', letterSpacing: -0.2 },
  body: { fontSize: 17, fontWeight: '400', letterSpacing: -0.2 },
  bodyAmount: { fontSize: 17, fontWeight: '600', letterSpacing: -0.2, ...rounded, ...tabular },
  subhead: { fontSize: 15, fontWeight: '400', letterSpacing: -0.2 },
  subheadAmount: { fontSize: 15, fontWeight: '600', letterSpacing: -0.2, ...rounded, ...tabular },
  footnote: { fontSize: 13, fontWeight: '400', letterSpacing: -0.1 },
  caption: { fontSize: 12, fontWeight: '400' },
  caption2: { fontSize: 10, fontWeight: '500' },
  sectionHeader: { fontSize: 13, fontWeight: '400', letterSpacing: 0.2, textTransform: 'uppercase' },
} satisfies Record<string, TextStyle>;

export const radius = {
  card: 22,
  hero: 30,
  capsule: 999,
  button: 22,
};
