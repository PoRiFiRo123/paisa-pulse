import { addMonths, format } from 'date-fns';

import { monthRange } from './dates';

/** The financial month `offset` months before the one containing `now`. */
export function monthAt(offset: number, monthStartDay: number, now: number = Date.now()) {
  const current = monthRange(now, monthStartDay);
  const start = addMonths(current.start, -offset).getTime();
  const range = monthRange(start, monthStartDay);
  // Name the month by the calendar month that most of the period falls in.
  const mid = range.start + (range.end - range.start) / 2;
  return { ...range, name: format(mid, 'MMMM'), label: format(mid, 'MMMM yyyy'), short: format(mid, 'MMM') };
}
