/** A statement as rows of text cells, whatever file it came from. */
export type Sheet = string[][];

const DELIMITERS = [',', ';', '\t', '|'];

/** Pick the delimiter that splits the first lines most consistently (quotes respected). */
function detectDelimiter(text: string): string {
  const lines = text.split(/\r?\n/).filter((l) => l.trim()).slice(0, 30);
  let best = ',';
  let bestScore = -1;
  for (const d of DELIMITERS) {
    const counts = lines.map((l) => {
      let n = 0;
      let quoted = false;
      for (const ch of l) {
        if (ch === '"') quoted = !quoted;
        else if (ch === d && !quoted) n++;
      }
      return n;
    });
    const withCols = counts.filter((c) => c > 0);
    // Reward many lines sharing the most common column count.
    const mode = withCols.sort((a, b) => withCols.filter((x) => x === b).length - withCols.filter((x) => x === a).length)[0] ?? 0;
    const score = withCols.filter((c) => c === mode).length * Math.min(mode, 12);
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return best;
}

/** RFC 4180-ish CSV: quotes, "" escapes, CR/LF/CRLF, BOM, and auto-detected delimiter. */
export function parseCsv(text: string, delimiter?: string): Sheet {
  const src = text.replace(/^﻿/, '');
  const d = delimiter ?? detectDelimiter(src);
  const rows: Sheet = [];
  let row: string[] = [];
  let cell = '';
  let quoted = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (quoted) {
      if (ch === '"') {
        if (src[i + 1] === '"') {
          cell += '"';
          i++;
        } else quoted = false;
      } else cell += ch;
    } else if (ch === '"' && cell.trim() === '') {
      quoted = true;
      cell = '';
    } else if (ch === d) {
      row.push(cell);
      cell = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && src[i + 1] === '\n') i++;
      row.push(cell);
      rows.push(row);
      row = [];
      cell = '';
    } else cell += ch;
  }
  if (cell !== '' || row.length) {
    row.push(cell);
    rows.push(row);
  }
  return rows.map((r) => r.map((c) => c.trim())).filter((r) => r.some((c) => c !== ''));
}
