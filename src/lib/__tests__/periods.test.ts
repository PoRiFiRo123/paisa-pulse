import { periodAt, previousRange, rangeLabel } from '../periods';

const prefs = { monthStartDay: 1, weekStartDay: 1 as const };
const NOW = new Date(2026, 9, 10, 15).getTime(); // Sat 10 Oct 2026

describe('periodAt', () => {
  it('builds weeks from the week start day', () => {
    const w = periodAt('week', 0, prefs, NOW);
    expect(new Date(w.start)).toEqual(new Date(2026, 9, 5));
    expect(new Date(w.end)).toEqual(new Date(2026, 9, 12));
    expect(w.label).toBe('This week');
    const prev = periodAt('week', 1, prefs, NOW);
    expect(prev.label).toBe('28 Sep – 4 Oct');
    expect(new Date(periodAt('week', 0, { ...prefs, weekStartDay: 0 }, NOW).start)).toEqual(new Date(2026, 9, 4));
  });

  it('builds calendar quarters and years', () => {
    const q = periodAt('quarter', 0, prefs, NOW);
    expect(new Date(q.start)).toEqual(new Date(2026, 9, 1));
    expect(new Date(q.end)).toEqual(new Date(2027, 0, 1));
    expect(q.label).toBe('Oct–Dec 2026');
    expect(q.short).toBe('Q4 26');
    const q2 = periodAt('quarter', 2, prefs, NOW);
    expect(new Date(q2.start)).toEqual(new Date(2026, 3, 1));
    const y = periodAt('year', 1, prefs, NOW);
    expect(new Date(y.start)).toEqual(new Date(2025, 0, 1));
    expect(new Date(y.end)).toEqual(new Date(2026, 0, 1));
    expect(y.label).toBe('2025');
  });

  it('shifts quarters with a salary-day month start', () => {
    const q = periodAt('quarter', 0, { ...prefs, monthStartDay: 25 }, NOW);
    // The month 25 Sep – 25 Oct is "October", so the quarter starts 25 Sep.
    expect(new Date(q.start)).toEqual(new Date(2026, 8, 25));
    expect(new Date(q.end)).toEqual(new Date(2026, 11, 25));
  });
});

describe('labels', () => {
  it('formats ranges compactly', () => {
    expect(rangeLabel(new Date(2026, 8, 8).getTime(), new Date(2026, 8, 15).getTime())).toBe('8–14 Sep');
    expect(rangeLabel(new Date(2025, 11, 29).getTime(), new Date(2026, 0, 5).getTime())).toBe('29 Dec 2025 – 4 Jan 2026');
  });
  it('finds the previous range of equal length', () => {
    expect(previousRange({ start: 10, end: 15 })).toEqual({ start: 5, end: 10 });
  });
});
