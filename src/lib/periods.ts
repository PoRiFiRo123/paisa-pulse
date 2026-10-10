import { addWeeks, format } from 'date-fns';

import { weekRange } from './dates';
import { monthAt } from './months';

export type PeriodKind = 'week' | 'month' | 'quarter' | 'year';

/** A reporting period: [start, end) plus labels for headings and chart axes. */
export type Period = { start: number; end: number; label: string; short: string };

export type PeriodPrefs = { monthStartDay: number; weekStartDay: 0 | 1 };

const sameYear = (a: number, b: number) => new Date(a).getFullYear() === new Date(b).getFullYear();

/** "8–14 Sep", "29 Sep – 5 Oct", "29 Dec 2025 – 4 Jan 2026". */
export function rangeLabel(start: number, end: number): string {
  const last = end - 1;
  if (!sameYear(start, last)) return `${format(start, 'd MMM yyyy')} – ${format(last, 'd MMM yyyy')}`;
  if (format(start, 'MMM') === format(last, 'MMM')) return `${format(start, 'd')}–${format(last, 'd MMM')}`;
  return `${format(start, 'd MMM')} – ${format(last, 'd MMM')}`;
}

/**
 * The period `offset` steps before the current one. Months follow the salary-day month
 * start; quarters and years are built from those months (Jan–Mar, …; calendar years).
 */
export function periodAt(kind: PeriodKind, offset: number, prefs: PeriodPrefs, now: number = Date.now()): Period {
  switch (kind) {
    case 'week': {
      const current = weekRange(now, prefs.weekStartDay);
      const start = addWeeks(current.start, -offset).getTime();
      const end = addWeeks(current.start, 1 - offset).getTime();
      return { start, end, label: offset === 0 ? 'This week' : rangeLabel(start, end), short: format(start, 'd MMM') };
    }
    case 'month': {
      const m = monthAt(offset, prefs.monthStartDay, now);
      return { start: m.start, end: m.end, label: m.label, short: m.short };
    }
    case 'quarter':
    case 'year': {
      const size = kind === 'quarter' ? 3 : 12;
      // Months since the start of the current quarter/year, by the month's name.
      const current = monthAt(0, prefs.monthStartDay, now);
      const named = new Date(current.start + (current.end - current.start) / 2).getMonth();
      const intoPeriod = named % size;
      const first = monthAt(intoPeriod + size * offset, prefs.monthStartDay, now);
      const last = monthAt(intoPeriod + size * offset - (size - 1), prefs.monthStartDay, now);
      const mid = new Date(first.start + (first.end - first.start) / 2);
      if (kind === 'year') return { start: first.start, end: last.end, label: String(mid.getFullYear()), short: String(mid.getFullYear()) };
      const q = Math.floor(mid.getMonth() / 3) + 1;
      return {
        start: first.start,
        end: last.end,
        label: `${first.short}–${last.short} ${format(mid, 'yyyy')}`,
        short: `Q${q} ${format(mid, 'yy')}`,
      };
    }
  }
}

/** How many periods the trend chart shows for each kind. */
export const TREND_LENGTH: Record<PeriodKind, number> = { week: 8, month: 6, quarter: 6, year: 4 };

/** The same-length period just before a custom range, for "vs previous". */
export function previousRange(range: { start: number; end: number }): { start: number; end: number } {
  return { start: range.start - (range.end - range.start), end: range.start };
}
