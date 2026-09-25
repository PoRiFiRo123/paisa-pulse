import { tryToPaise } from '@/lib/money';

import type { Sheet } from './readers/csv';

export type ColumnRole =
  | 'date'
  | 'valueDate'
  | 'description'
  | 'reference'
  | 'debit'
  | 'credit'
  | 'amount'
  | 'drcr'
  | 'balance'
  | 'ignore';

export const COLUMN_ROLE_LABEL: Record<ColumnRole, string> = {
  date: 'Date',
  valueDate: 'Value date',
  description: 'Description',
  reference: 'Reference / cheque',
  debit: 'Debit (money out)',
  credit: 'Credit (money in)',
  amount: 'Amount',
  drcr: 'Dr / Cr marker',
  balance: 'Balance',
  ignore: 'Ignore',
};

export type DateOrder = 'dmy' | 'mdy' | 'ymd';

/** How to read a sheet. Detected automatically, editable in the import screen. */
export type Mapping = {
  headerRow: number;
  columns: ColumnRole[];
  dateOrder: DateOrder;
  /** For a single signed Amount column: which sign means money leaving the account. */
  positiveIs: 'in' | 'out';
};

export type StatementTemplate = { id: string; name: string; kind: 'bank' | 'card' };

/** Known statement layouts. Detection uses the bank name near the top plus the header. */
export const TEMPLATES: (StatementTemplate & { match: RegExp; header?: RegExp })[] = [
  { id: 'axis-card', name: 'Axis Bank credit card', kind: 'card', match: /axis bank.*(credit card|card no)|myzone|flipkart axis|axis.*card statement/i, header: /transaction details.*debit\/credit/i },
  { id: 'axis-bank', name: 'Axis Bank', kind: 'bank', match: /axis bank/i, header: /tran date.*particulars.*\bsol\b/i },
  { id: 'bob', name: 'Bank of Baroda', kind: 'bank', match: /bank of baroda|\bbob\b|barb0/i, header: /withdrawal\s*\(dr\).*deposit\s*\(cr\)/i },
  { id: 'hdfc-card', name: 'HDFC Bank credit card', kind: 'card', match: /hdfc.*credit card/i },
  { id: 'hdfc', name: 'HDFC Bank', kind: 'bank', match: /hdfc bank/i, header: /withdrawal amt.*deposit amt.*closing balance/i },
  { id: 'icici-card', name: 'ICICI Bank credit card', kind: 'card', match: /icici.*credit card/i },
  { id: 'icici', name: 'ICICI Bank', kind: 'bank', match: /icici bank/i, header: /transaction remarks/i },
  { id: 'sbi-card', name: 'SBI Card', kind: 'card', match: /sbi card/i },
  { id: 'sbi', name: 'State Bank of India', kind: 'bank', match: /state bank of india|\bsbi\b/i, header: /txn date.*ref no\.?\/cheque/i },
];

// Header aliases per role, most specific first. Covers Axis, BoB, HDFC, ICICI, SBI and card statements.
const ROLE_PATTERNS: [ColumnRole, RegExp][] = [
  ['valueDate', /^value\s*(date|dt)\b/i],
  ['drcr', /^(dr\s*\/\s*cr|cr\s*\/\s*dr|debit\s*\/\s*credit|type|txn type|transaction type|dr\s*cr)$/i],
  ['debit', /withdraw|debit|^dr\b|\bdr\s*(amt|amount)|paid out|money out/i],
  ['credit', /deposit|credit|^cr\b|\bcr\s*(amt|amount)|paid in|money in/i],
  ['balance', /balance|^bal\b/i],
  ['date', /date|^dt$|^txn\s*dt$/i],
  ['reference', /chq|cheque|ref|utr|instrument/i],
  ['description', /narration|description|particulars|details|remarks|transaction$|merchant|payee/i],
  ['amount', /amount|amt|inr|₹/i],
];

const DATE_CELL = /^\d{1,2}[-/. ](\d{1,2}|[a-z]{3,9})[-/. ,]*\d{2,4}|^\d{4}-\d{1,2}-\d{1,2}|^\d{5}(\.\d+)?$/i;

/** First row (within the first 60) that looks like a header: several role words, followed by dated rows. */
export function detectHeaderRow(sheet: Sheet): number {
  let best = -1;
  let bestHits = 2;
  for (let i = 0; i < Math.min(sheet.length, 60); i++) {
    const hits = new Set(sheet[i].map(guessRole).filter((r) => r !== 'ignore')).size;
    if (hits > bestHits && sheet.slice(i + 1, i + 6).some((r) => r.some((c) => DATE_CELL.test(c.trim())))) {
      best = i;
      bestHits = hits;
    }
  }
  return best;
}

export function guessRole(header: string): ColumnRole {
  const h = header.replace(/\s+/g, ' ').trim();
  if (!h) return 'ignore';
  for (const [role, re] of ROLE_PATTERNS) if (re.test(h)) return role;
  return 'ignore';
}

/** Roles for a header row, keeping only the first column for single-use roles. */
export function guessColumns(header: string[]): ColumnRole[] {
  const used = new Set<ColumnRole>();
  const roles = header.map((h) => {
    const role = guessRole(h);
    if (role === 'ignore' || used.has(role)) return 'ignore';
    used.add(role);
    return role;
  });
  // "Amount" next to separate Debit/Credit columns is redundant.
  if (roles.includes('debit') && roles.includes('credit')) return roles.map((r) => (r === 'amount' ? 'ignore' : r));
  return roles;
}

/**
 * Which bank/card the statement is from: the bank name above the table first (data rows
 * mention other banks, e.g. "BILLDESK/AXIS BANK CREDIT CARD"), then the header's shape.
 */
export function detectTemplate(sheet: Sheet, headerRow = detectHeaderRow(sheet)): StatementTemplate | null {
  const preamble = sheet
    .slice(0, Math.max(headerRow, 0))
    .map((r) => r.join(' '))
    .join(' ');
  const header = headerRow >= 0 ? sheet[headerRow].join(' ') : '';
  const found =
    (preamble && TEMPLATES.find((t) => t.match.test(preamble))) || TEMPLATES.find((t) => t.header && t.header.test(header));
  return found ? { id: found.id, name: found.name, kind: found.kind } : null;
}

// ---------------------------------------------------------------------------------------
// Dates and amounts

const MONTHS: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12 };

/**
 * Parse a statement date to local noon (statements rarely have times; noon avoids
 * timezone day-shifts). Handles 01-09-2026, 01/09/26, 1-Sep-2026, 01 SEP 26,
 * 2026-09-01, "01/09/2026 10:15", and Excel serial numbers. Ambiguous numeric dates
 * follow `order` (Indian banks: day first).
 */
export function parseStatementDate(value: string, order: DateOrder = 'dmy'): number | null {
  const s = value.trim();
  if (!s) return null;
  const at = (y: number, m: number, d: number, hh = 12, mm = 0) => {
    const year = y < 100 ? 2000 + y : y;
    if (m < 1 || m > 12 || d < 1 || d > 31 || year < 1990 || year > 2100) return null;
    const date = new Date(year, m - 1, d, hh, mm);
    return date.getMonth() === m - 1 ? date.getTime() : null;
  };
  // Excel serial (days since 1899-12-30).
  if (/^\d{5}(\.\d+)?$/.test(s)) {
    const serial = Number(s);
    if (serial < 30000 || serial > 80000) return null;
    const utc = new Date(Date.UTC(1899, 11, 30) + Math.floor(serial) * 86_400_000);
    return at(utc.getUTCFullYear(), utc.getUTCMonth() + 1, utc.getUTCDate());
  }
  const time = /(\d{1,2}):(\d{2})(?::\d{2})?\s*(am|pm)?/i.exec(s);
  let hh = 12;
  let mm = 0;
  if (time) {
    const h = Number(time[1]);
    const ampm = time[3]?.toLowerCase();
    hh = ampm ? (h % 12) + (ampm === 'pm' ? 12 : 0) : h;
    mm = Number(time[2]);
  }
  const iso = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/.exec(s);
  if (iso) return at(Number(iso[1]), Number(iso[2]), Number(iso[3]), hh, mm);
  const month = (name: string) => MONTHS[name.toLowerCase().slice(0, 4)] ?? MONTHS[name.toLowerCase().slice(0, 3)];
  const named = /^(\d{1,2})[-/. ]*([a-z]{3,9})[-/. ,]*(\d{2,4})/i.exec(s);
  if (named && month(named[2])) return at(Number(named[3]), month(named[2]), Number(named[1]), hh, mm);
  const monthFirst = /^([a-z]{3,9})[-/. ]+(\d{1,2}),?[-/. ]+(\d{2,4})/i.exec(s);
  if (monthFirst && month(monthFirst[1])) return at(Number(monthFirst[3]), month(monthFirst[1]), Number(monthFirst[2]), hh, mm);
  const num = /^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})/.exec(s);
  if (num) {
    const [a, b, y] = [Number(num[1]), Number(num[2]), Number(num[3])];
    return order === 'mdy' ? at(y, a, b, hh, mm) : at(y, b, a, hh, mm);
  }
  return null;
}

/**
 * Parse a statement amount to signed paise. "1,23,456.78", "₹ 1,234", "INR 50", "(120.00)",
 * "-50", "120.00 Dr", "1,234.50CR". Blank, "-" and "0.00" mean no amount (null).
 */
export function parseStatementAmount(value: string): { paise: number; marker: 'dr' | 'cr' | null } | null {
  let s = value.replace(/\s+/g, ' ').trim();
  if (!s || /^[-–—]$/.test(s)) return null;
  let marker: 'dr' | 'cr' | null = null;
  const m = /(?<![a-z])(dr|cr|debit|credit)\.?$/i.exec(s);
  if (m) {
    marker = m[1].toLowerCase().startsWith('d') ? 'dr' : 'cr';
    s = s.slice(0, m.index).trim();
  }
  let negative = false;
  if (/^\(.*\)$/.test(s)) {
    negative = true;
    s = s.slice(1, -1);
  }
  s = s.replace(/^(inr|rs\.?|₹)\s*/i, '').replace(/\s*(inr)$/i, '');
  if (s.startsWith('-')) {
    negative = !negative;
    s = s.slice(1);
  } else if (s.startsWith('+')) s = s.slice(1);
  if (!/^[\d,]*\.?\d*$/.test(s) || !/\d/.test(s)) return null;
  // Statements sometimes show more than 2 decimals; round to paise.
  const [whole, frac = ''] = s.split('.');
  const paise = tryToPaise(frac.length > 2 ? `${whole}.${Math.round(Number(`0.${frac}`) * 100).toString().padStart(2, '0')}` : s);
  if (paise === null || paise === 0) return null;
  return { paise: negative ? -paise : paise, marker };
}

// ---------------------------------------------------------------------------------------
// Rows

export type StatementRow = {
  /** Index in the sheet, for display and stable ids. */
  line: number;
  date: number;
  description: string;
  reference: string;
  /** Always positive; `direction` says which way it moved. */
  amount: number;
  direction: 'in' | 'out';
  balance: number | null;
};

export function detectMapping(sheet: Sheet, template: StatementTemplate | null, accountKind: 'bank' | 'card'): Mapping | null {
  const headerRow = detectHeaderRow(sheet);
  if (headerRow < 0) return null;
  const columns = guessColumns(sheet[headerRow]);
  if (!columns.includes('date')) return null;
  // Pick the date order that parses the most rows (dd/mm is the Indian default).
  const dateCol = columns.indexOf('date');
  const samples = sheet.slice(headerRow + 1, headerRow + 60).map((r) => r[dateCol] ?? '');
  const score = (o: DateOrder) => samples.filter((v) => parseStatementDate(v, o) !== null).length;
  const dateOrder: DateOrder = score('dmy') >= score('mdy') ? 'dmy' : 'mdy';
  const kind = template?.kind ?? accountKind;
  return { headerRow, columns, dateOrder, positiveIs: kind === 'card' ? 'out' : 'in' };
}

/** Apply a mapping. Rows without a valid date or amount (opening balance, totals) are skipped. */
export function extractRows(sheet: Sheet, mapping: Mapping): StatementRow[] {
  const col = (role: ColumnRole) => mapping.columns.indexOf(role);
  const [dateC, descC, refC, debitC, creditC, amountC, drcrC, balC] = (
    ['date', 'description', 'reference', 'debit', 'credit', 'amount', 'drcr', 'balance'] as ColumnRole[]
  ).map(col);
  const cell = (row: string[], i: number) => (i >= 0 ? (row[i] ?? '').trim() : '');
  const rows: StatementRow[] = [];

  sheet.slice(mapping.headerRow + 1).forEach((row, i) => {
    const date = parseStatementDate(cell(row, dateC), mapping.dateOrder);
    if (date === null) return;
    let amount = 0;
    let direction: 'in' | 'out' | null = null;
    const debit = parseStatementAmount(cell(row, debitC));
    const credit = parseStatementAmount(cell(row, creditC));
    if (debit || credit) {
      const d = Math.abs(debit?.paise ?? 0);
      const c = Math.abs(credit?.paise ?? 0);
      if (d >= c) {
        amount = d;
        direction = 'out';
      } else {
        amount = c;
        direction = 'in';
      }
    } else {
      const a = parseStatementAmount(cell(row, amountC));
      if (a) {
        amount = Math.abs(a.paise);
        const marker = a.marker ?? (/^(d|dr|debit|withdrawal)/i.test(cell(row, drcrC)) ? 'dr' : /^(c|cr|credit|deposit)/i.test(cell(row, drcrC)) ? 'cr' : null);
        if (marker) direction = marker === 'dr' ? 'out' : 'in';
        else if (a.paise < 0) direction = mapping.positiveIs === 'in' ? 'out' : 'in';
        else direction = mapping.positiveIs;
      }
    }
    if (!direction || amount <= 0) return;
    const balance = parseStatementAmount(cell(row, balC));
    const description = [cell(row, descC)].filter(Boolean).join(' ') || row.filter((c, j) => j !== dateC && c && !/^[\d,.\s()-]+$/.test(c)).join(' ');
    rows.push({
      line: mapping.headerRow + 1 + i,
      date,
      description: description.replace(/\s+/g, ' ').trim(),
      reference: cell(row, refC),
      amount,
      direction,
      balance: balance ? (balance.marker === 'dr' ? -Math.abs(balance.paise) : balance.paise) : null,
    });
  });
  return rows;
}

/**
 * Sanity check using the running balance column: each row's balance should equal the
 * previous balance ± its amount (statements may be oldest- or newest-first).
 * Returns the number of rows that don't reconcile, or null when there's no balance column.
 */
export function balanceMismatches(rows: StatementRow[]): number | null {
  const withBalance = rows.filter((r) => r.balance !== null);
  if (withBalance.length < 2) return null;
  const count = (list: StatementRow[]) =>
    list.slice(1).filter((r, i) => list[i].balance! + (r.direction === 'in' ? r.amount : -r.amount) !== r.balance).length;
  return Math.min(count(withBalance), count([...withBalance].reverse()));
}
