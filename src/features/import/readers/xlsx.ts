import { strFromU8, unzipSync } from 'fflate';

import type { Sheet } from './csv';
import { decodeEntities, textContent } from './xml';

function attr(tag: string, name: string): string | undefined {
  return new RegExp(`\\b${name}="([^"]*)"`).exec(tag)?.[1];
}

/** "AB12" → 27 (0-based column index). */
function columnIndex(ref: string): number {
  const letters = /^[A-Z]+/.exec(ref)?.[0] ?? 'A';
  return [...letters].reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0) - 1;
}

/**
 * Read the first worksheet of an .xlsx file into text cells. Numbers stay as written
 * (dates stored as Excel serials are converted later by the date parser).
 */
export function readXlsx(bytes: Uint8Array): Sheet {
  const files = unzipSync(bytes, { filter: (f) => f.name.startsWith('xl/') });
  const text = (name: string) => (files[name] ? strFromU8(files[name]) : '');

  // Resolve the first sheet's file through the workbook relationships.
  const workbook = text('xl/workbook.xml');
  const firstSheetRel = attr(/<sheet\b[^>]*>/.exec(workbook)?.[0] ?? '', 'r:id');
  const rels = text('xl/_rels/workbook.xml.rels');
  let target = 'worksheets/sheet1.xml';
  for (const rel of rels.match(/<Relationship\b[^>]*>/g) ?? []) {
    if (attr(rel, 'Id') === firstSheetRel) target = (attr(rel, 'Target') ?? target).replace(/^\/?xl\//, '');
  }

  const shared = (text('xl/sharedStrings.xml').match(/<si>[\s\S]*?<\/si>/g) ?? []).map((si) =>
    (si.match(/<t\b[^>]*>([\s\S]*?)<\/t>/g) ?? []).map((t) => decodeEntities(t.replace(/<\/?t\b[^>]*>/g, ''))).join(''),
  );

  const sheet: Sheet = [];
  for (const rowXml of text(`xl/${target}`).match(/<row\b[\s\S]*?<\/row>/g) ?? []) {
    const row: string[] = [];
    for (const cell of rowXml.match(/<c\b[^>]*\/>|<c\b[\s\S]*?<\/c>/g) ?? []) {
      const open = /<c\b[^>]*>/.exec(cell)?.[0] ?? cell;
      const ref = attr(open, 'r');
      const type = attr(open, 't');
      const v = /<v>([\s\S]*?)<\/v>/.exec(cell)?.[1];
      let value = '';
      if (type === 's' && v !== undefined) value = shared[Number(v)] ?? '';
      else if (type === 'inlineStr') value = textContent(/<is>([\s\S]*?)<\/is>/.exec(cell)?.[1] ?? '');
      else if (v !== undefined) value = decodeEntities(v);
      const index = ref ? columnIndex(ref) : row.length;
      while (row.length < index) row.push('');
      row[index] = value.trim();
    }
    if (row.some((c) => c !== '')) sheet.push(row);
  }
  return sheet;
}
