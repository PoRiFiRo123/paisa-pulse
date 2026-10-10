/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';

import { convertToPaise, formatForeign, formatRate, hundredthsToMinor, minorToHundredths } from '../currency';
import { getRates, parseRates, RATES_MAX_AGE } from '../rates';

describe('currency maths', () => {
  it('converts keypad hundredths to minor units per currency', () => {
    expect(hundredthsToMinor(1234, 'USD')).toBe(1234);
    expect(hundredthsToMinor(150000, 'JPY')).toBe(1500);
    expect(hundredthsToMinor(350, 'KWD')).toBe(3500);
    expect(minorToHundredths(1500, 'JPY')).toBe(150000);
  });

  it('converts to paise and formats', () => {
    expect(convertToPaise(1234, 'USD', 83.25)).toBe(1027_31); // $12.34 × 83.25 = ₹1,027.305
    expect(convertToPaise(1500, 'JPY', 0.56)).toBe(840_00);
    expect(formatForeign(1234, 'USD')).toBe('$12.34');
    expect(formatForeign(150000, 'JPY')).toBe('¥150,000');
    expect(formatForeign(4550, 'AED')).toBe('AED 45.50');
    expect(formatRate(83.2512)).toBe('₹83.25');
    expect(formatRate(0.00523)).toBe('₹0.0052');
  });
});

describe('rates', () => {
  const body = { result: 'success', base_code: 'INR', time_last_update_unix: 1_760_000_000, rates: { INR: 1, USD: 0.012, JPY: 1.8 } };

  it('parses rupees per unit', () => {
    const r = parseRates(body, 0);
    expect(r.inrPer.USD).toBeCloseTo(83.333, 2);
    expect(r.inrPer.JPY).toBeCloseTo(0.5556, 3);
    expect(r.inrPer.INR).toBeUndefined();
    expect(() => parseRates({ result: 'error' }, 0)).toThrow();
  });

  it('caches, refreshes when stale and falls back offline', async () => {
    const { db, raw } = createTestDb();
    const ok = jest.fn(async () => ({ ok: true, json: async () => body }) as unknown as Response);
    const now = 1_760_000_000_000;
    expect((await getRates(db, { now, fetcher: ok }))?.inrPer.USD).toBeCloseTo(83.33, 1);
    await getRates(db, { now: now + 1000, fetcher: ok });
    expect(ok).toHaveBeenCalledTimes(1);
    const offline = jest.fn(async () => {
      throw new Error('offline');
    });
    expect((await getRates(db, { now: now + RATES_MAX_AGE + 1, fetcher: offline as unknown as typeof fetch }))?.inrPer.USD).toBeCloseTo(83.33, 1);
    expect(offline).toHaveBeenCalledTimes(1);
    raw.close();
  });
});
