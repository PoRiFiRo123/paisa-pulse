import { getSetting, setSetting } from '@/db/settings';
import type { DB } from '@/db/types';

/** Cached exchange rates: rupees per one unit of each currency. */
export type RatesCache = { at: number; inrPer: Record<string, number>; source: string };

export const RATES_URL = 'https://open.er-api.com/v6/latest/INR';
/** Refresh rates when they're older than this. */
export const RATES_MAX_AGE = 12 * 60 * 60 * 1000;

/** Parse an open.er-api.com response (units per 1 INR) into rupees per unit. */
export function parseRates(json: unknown, now: number): RatesCache {
  const data = json as { result?: string; base_code?: string; rates?: Record<string, number>; time_last_update_unix?: number };
  if (data?.result !== 'success' || data.base_code !== 'INR' || !data.rates) throw new Error('Exchange rates unavailable');
  const inrPer: Record<string, number> = {};
  for (const [code, perInr] of Object.entries(data.rates)) {
    if (typeof perInr === 'number' && perInr > 0 && code !== 'INR') inrPer[code] = 1 / perInr;
  }
  return { at: data.time_last_update_unix ? data.time_last_update_unix * 1000 : now, inrPer, source: 'open.er-api.com' };
}

export async function cachedRates(db: DB): Promise<RatesCache | null> {
  return (await getSetting(db, 'fx.rates')) ?? null;
}

/**
 * Rates for converting, refreshing from the network when stale. Only currency codes are
 * requested; nothing about your spending leaves the phone. Falls back to the cache offline.
 */
export async function getRates(db: DB, { force = false, now = Date.now(), fetcher = fetch } = {}): Promise<RatesCache | null> {
  const cached = await cachedRates(db);
  if (!force && cached && now - cached.at < RATES_MAX_AGE) return cached;
  try {
    const res = await fetcher(RATES_URL);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const fresh = parseRates(await res.json(), now);
    await setSetting(db, 'fx.rates', fresh);
    return fresh;
  } catch {
    return cached;
  }
}
