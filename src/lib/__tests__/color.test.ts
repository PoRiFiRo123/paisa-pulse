import { CHART_BAND, chartColor, hexToOklch, oklchToHex } from '../color';

const CATEGORY = ['#AF52DE', '#FF9500', '#007AFF', '#FF2D55', '#34C759', '#32ADE6', '#FFB800', '#5856D6', '#30B0C7', '#8E8E93'];

describe('chartColor', () => {
  it('round-trips through OKLCH', () => {
    for (const hex of CATEGORY) {
      const [L, C, h] = hexToOklch(hex);
      expect(oklchToHex(L, C, h)).toBe(hex);
    }
  });

  it.each([false, true])('keeps every category colour inside the lightness band (dark=%s)', (dark) => {
    const [lo, hi] = CHART_BAND[dark ? 'dark' : 'light'];
    for (const hex of CATEGORY) {
      const [L] = hexToOklch(chartColor(hex, dark));
      expect(L).toBeGreaterThanOrEqual(lo - 0.02);
      expect(L).toBeLessThanOrEqual(hi + 0.02);
    }
  });

  it('leaves colours already in band untouched and keeps the hue', () => {
    expect(chartColor('#007AFF', false)).toBe('#007AFF');
    const [, , h1] = hexToOklch('#FFB800');
    const [, , h2] = hexToOklch(chartColor('#FFB800', false));
    expect(Math.abs(h1 - h2)).toBeLessThan(0.1);
  });
});
