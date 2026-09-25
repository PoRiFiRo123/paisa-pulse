import type { Sheet } from './csv';
import { textContent } from './xml';

/**
 * Many banks' ".xls" downloads are really HTML tables. Returns the largest table.
 */
export function readHtmlTable(html: string): Sheet {
  let best: Sheet = [];
  for (const table of html.match(/<table\b[\s\S]*?<\/table>/gi) ?? []) {
    const rows: Sheet = [];
    for (const tr of table.match(/<tr\b[\s\S]*?<\/tr>/gi) ?? []) {
      const cells: string[] = [];
      for (const cell of tr.match(/<t[dh]\b[^>]*>[\s\S]*?<\/t[dh]>/gi) ?? []) {
        const span = Number(/colspan="?(\d+)/i.exec(cell)?.[1] ?? 1);
        cells.push(textContent(cell));
        for (let i = 1; i < span; i++) cells.push('');
      }
      if (cells.some((c) => c !== '')) rows.push(cells);
    }
    if (rows.length > best.length) best = rows;
  }
  return best;
}
