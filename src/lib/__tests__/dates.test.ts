import { monthRange } from '../dates';

const local = (y: number, m: number, d: number, h = 0) => new Date(y, m - 1, d, h).getTime();

describe('monthRange', () => {
  it('returns the calendar month by default', () => {
    expect(monthRange(local(2026, 9, 25, 15))).toEqual({ start: local(2026, 9, 1), end: local(2026, 10, 1) });
  });

  it('starts the month on salary day', () => {
    expect(monthRange(local(2026, 9, 25), 26)).toEqual({ start: local(2026, 8, 26), end: local(2026, 9, 26) });
    expect(monthRange(local(2026, 9, 26), 26)).toEqual({ start: local(2026, 9, 26), end: local(2026, 10, 26) });
  });

  it('wraps across the year and clamps the start day to 28', () => {
    expect(monthRange(local(2027, 1, 3), 31)).toEqual({ start: local(2026, 12, 28), end: local(2027, 1, 28) });
  });
});
