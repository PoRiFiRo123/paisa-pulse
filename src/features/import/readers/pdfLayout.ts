import type { Sheet } from './csv';

/** A positioned run of text from pdf.js (x/y in PDF points, y grows downwards here). */
export type TextItem = { str: string; x: number; y: number; w: number; h: number; page: number };

type Cell = { text: string; x0: number; x1: number };
type Line = { page: number; y: number; cells: Cell[] };

const HEADER_WORDS = /\b(date|narration|description|particulars|details|remarks|debit|credit|withdrawal|deposit|balance|amount|dr|cr|cheque|chq|ref)\b/i;
const DATE_LIKE = /^\d{1,2}[-/. ](\d{1,2}|[a-z]{3})[-/. ]\d{2,4}$|^\d{4}-\d{2}-\d{2}$|^\d{1,2} [a-z]{3},? \d{2,4}$/i;

/** Group text items into visual lines, then merge nearby items on a line into cells. */
export function itemsToLines(items: TextItem[]): Line[] {
  const sorted = items.filter((i) => i.str.trim()).sort((a, b) => a.page - b.page || a.y - b.y || a.x - b.x);
  const lines: Line[] = [];
  for (const item of sorted) {
    const last = lines[lines.length - 1];
    // Items on one visual line share a baseline; keep this tight so neighbouring rows don't merge.
    const tol = Math.max(1.5, item.h * 0.25);
    const line = last && last.page === item.page && Math.abs(last.y - item.y) <= tol ? last : null;
    const target = line ?? (lines.push({ page: item.page, y: item.y, cells: [] }), lines[lines.length - 1]);
    target.cells.push({ text: item.str, x0: item.x, x1: item.x + item.w });
  }
  for (const line of lines) {
    line.cells.sort((a, b) => a.x0 - b.x0);
    const merged: Cell[] = [];
    for (const c of line.cells) {
      const prev = merged[merged.length - 1];
      // Words of one cell sit closer than about one character width.
      const gap = prev ? c.x0 - prev.x1 : Infinity;
      const charW = prev ? (prev.x1 - prev.x0) / Math.max(prev.text.length, 1) : 0;
      if (prev && gap < Math.max(charW * 1.2, 3)) {
        prev.text = `${prev.text}${gap > charW * 0.25 ? ' ' : ''}${c.text}`.trim();
        prev.x1 = c.x1;
      } else merged.push({ ...c, text: c.text.trim() });
    }
    line.cells = merged;
  }
  return lines;
}

function isHeader(line: Line): boolean {
  return line.cells.filter((c) => HEADER_WORDS.test(c.text)).length >= 3;
}

/**
 * Rebuild a statement table from PDF text positions:
 * 1. the header line's cells become column anchors;
 * 2. every value goes to the column it overlaps most (else the nearest centre);
 * 3. lines with a date start a row; text-only lines (wrapped narrations) join the nearest
 *    such row by vertical distance, which handles both top- and centre-aligned cells;
 * 4. headers repeated on later pages are skipped.
 */
export function layoutToSheet(items: TextItem[]): Sheet {
  const lines = itemsToLines(items);
  const headerIndex = lines.findIndex(isHeader);
  if (headerIndex < 0) return lines.map((l) => l.cells.map((c) => c.text));
  const header = lines[headerIndex].cells;
  const headerKey = header.map((c) => c.text.toLowerCase()).join('|');
  const columnOf = (c: Cell) => {
    let best = 0;
    let bestScore = -Infinity;
    header.forEach((h, i) => {
      const overlap = Math.min(c.x1, h.x1) - Math.max(c.x0, h.x0);
      const distance = Math.abs((c.x0 + c.x1) / 2 - (h.x0 + h.x1) / 2);
      const score = overlap > 0 ? 1000 + overlap : -distance;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    });
    return best;
  };
  const toRow = (line: Line) => {
    const row = header.map(() => '');
    for (const cell of line.cells) {
      const col = columnOf(cell);
      row[col] = row[col] ? `${row[col]} ${cell.text}` : cell.text;
    }
    return row;
  };
  // Wrapped narration text only ever sits in description-type columns.
  const structural = new Set(
    header.flatMap((h, i) => (/date|debit|credit|withdraw|deposit|amount|balance|\bdr\b|\bcr\b/i.test(h.text) ? [i] : [])),
  );
  const heights = items.map((i) => i.h).sort((a, b) => a - b);
  const lineHeight = heights[Math.floor(heights.length / 2)] ?? 10;
  const maxReach = lineHeight * 3.5;

  type Group = { page: number; y: number; parts: { y: number; row: string[] }[]; anchor: boolean };
  const groups: Group[] = [];
  const pending: { page: number; y: number; row: string[] }[] = [];
  for (const line of lines.slice(headerIndex + 1)) {
    if (line.cells.map((c) => c.text.toLowerCase()).join('|') === headerKey) continue;
    const row = toRow(line);
    const filledCols = row.flatMap((v, i) => (v !== '' ? [i] : []));
    if (row.some((v) => DATE_LIKE.test(v))) {
      groups.push({ page: line.page, y: line.y, parts: [{ y: line.y, row }], anchor: true });
    } else if (filledCols.length && filledCols.every((i) => !structural.has(i))) {
      pending.push({ page: line.page, y: line.y, row });
    } else {
      // Numbers without a date (opening/closing balance, totals): keep as their own row.
      groups.push({ page: line.page, y: line.y, parts: [{ y: line.y, row }], anchor: false });
    }
  }
  // Attach each wrapped line to the nearest dated row on the same page (ties go to the row above).
  for (const p of pending) {
    let best: Group | null = null;
    let bestD = Infinity;
    for (const g of groups) {
      if (!g.anchor || g.page !== p.page) continue;
      const d = Math.abs(g.y - p.y) + (g.y > p.y ? 0.01 : 0);
      if (d < bestD) {
        bestD = d;
        best = g;
      }
    }
    if (best && bestD <= maxReach) best.parts.push(p);
    else groups.push({ page: p.page, y: p.y, parts: [p], anchor: false });
  }
  groups.sort((a, b) => a.page - b.page || a.y - b.y);

  const sheet: Sheet = [header.map((h) => h.text)];
  for (const g of groups) {
    const parts = g.parts.sort((a, b) => a.y - b.y);
    sheet.push(header.map((_, i) => parts.map((p) => p.row[i]).filter(Boolean).join(' ')));
  }
  return sheet;
}
