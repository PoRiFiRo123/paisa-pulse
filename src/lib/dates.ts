import { addMonths, addYears, setDate, startOfDay, startOfMonth } from 'date-fns';

export const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * The [start, end) range of the "financial month" containing `at`.
 * `monthStartDay` lets users start their month on salary day (clamped to 1–28
 * so every month has that day).
 */
export function monthRange(at: Date | number, monthStartDay = 1): { start: number; end: number } {
  const day = Math.min(Math.max(Math.trunc(monthStartDay), 1), 28);
  const date = new Date(at);
  let start = startOfDay(setDate(startOfMonth(date), day));
  if (start.getTime() > date.getTime()) start = addMonths(start, -1);
  return { start: start.getTime(), end: addMonths(start, 1).getTime() };
}

/** Latest allowed `occurredAt`: transactions can't be more than a year in the future. */
export function maxOccurredAt(now: number = Date.now()): number {
  return addYears(now, 1).getTime();
}
