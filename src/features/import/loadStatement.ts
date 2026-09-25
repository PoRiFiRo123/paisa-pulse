import { strFromU8 } from 'fflate';

import { parseCsv, type Sheet } from './readers/csv';
import { detectFileKind } from './readers/detect';
import { readHtmlTable } from './readers/html';
import { layoutToSheet } from './readers/pdfLayout';
import { readXlsx } from './readers/xlsx';
import type { PdfResult } from './PdfExtractor';

export type LoadResult = { ok: true; sheet: Sheet; kind: string } | { ok: false; error: 'password' | 'incorrect-password' | string };

function toBase64(bytes: Uint8Array): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const [a, b = 0, c = 0] = [bytes[i], bytes[i + 1], bytes[i + 2]];
    const n = (a << 16) | (b << 8) | c;
    out += chars[(n >> 18) & 63] + chars[(n >> 12) & 63] + (i + 1 < bytes.length ? chars[(n >> 6) & 63] : '=') + (i + 2 < bytes.length ? chars[n & 63] : '=');
  }
  return out;
}

/** Read any supported statement file into rows of cells. */
export async function loadStatement(
  bytes: Uint8Array,
  extractPdf: (base64: string, password?: string) => Promise<PdfResult>,
  password?: string,
): Promise<LoadResult> {
  const kind = detectFileKind(bytes);
  switch (kind) {
    case 'csv':
      return { ok: true, kind, sheet: parseCsv(strFromU8(bytes)) };
    case 'html':
      return { ok: true, kind, sheet: readHtmlTable(strFromU8(bytes)) };
    case 'xlsx':
      return { ok: true, kind, sheet: readXlsx(bytes) };
    case 'pdf': {
      const result = await extractPdf(toBase64(bytes), password);
      if (!result.ok) return result;
      return { ok: true, kind, sheet: layoutToSheet(result.items) };
    }
    case 'xls-binary':
      return { ok: false, error: 'This is an old Excel (.xls) file. Download the statement as PDF, CSV or .xlsx instead, or open it and save as .xlsx.' };
    default:
      return { ok: false, error: 'This file isn’t a statement Paisa Pulse can read. Use PDF, CSV or Excel (.xlsx).' };
  }
}

export { toBase64 };
