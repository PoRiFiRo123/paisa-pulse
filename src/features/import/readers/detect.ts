import { strFromU8 } from 'fflate';

export type FileKind = 'csv' | 'xlsx' | 'html' | 'pdf' | 'xls-binary' | 'unknown';

/** Identify a statement file by its bytes (extensions lie: many ".xls" files are HTML). */
export function detectFileKind(bytes: Uint8Array): FileKind {
  const b = (i: number) => bytes[i];
  if (b(0) === 0x25 && b(1) === 0x50 && b(2) === 0x44 && b(3) === 0x46) return 'pdf'; // %PDF
  if (b(0) === 0x50 && b(1) === 0x4b && b(2) === 0x03 && b(3) === 0x04) return 'xlsx'; // PK zip
  if (b(0) === 0xd0 && b(1) === 0xcf && b(2) === 0x11 && b(3) === 0xe0) return 'xls-binary'; // OLE2 / BIFF
  // Latin-1 view is enough to sniff markup and binary bytes (Hermes lacks TextDecoder).
  const head = strFromU8(bytes.subarray(0, 4096), true).toLowerCase();
  if (/<(html|table)\b/.test(head)) return 'html';
  if (/[\x00-\x08\x0e-\x1f]/.test(head.replace(/﻿/, ''))) return 'unknown';
  return 'csv';
}
