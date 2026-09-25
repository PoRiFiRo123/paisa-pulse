// Money is always integer paise (1 rupee = 100 paise). Never do maths on rupee floats.

export const PAISE_PER_RUPEE = 100;
export const LAKH = 100_000 * PAISE_PER_RUPEE;
export const CRORE = 100 * LAKH;

export class MoneyParseError extends Error {
  constructor(input: string) {
    super(`Not a valid amount: "${input}"`);
    this.name = 'MoneyParseError';
  }
}

const AMOUNT_RE = /^(-)?(\d*)(?:\.(\d{0,2}))?$/;

/** Like `toPaise`, but returns null instead of throwing. */
export function tryToPaise(input: string | number): number | null {
  const raw = typeof input === 'number' ? numberToString(input) : input;
  if (raw === null) return null;
  const cleaned = raw.replace(/[₹,\s]/g, '').replace(/^Rs\.?/i, '');
  const match = AMOUNT_RE.exec(cleaned);
  if (!match) return null;
  const [, minus, whole = '', frac = ''] = match;
  if (whole === '' && frac === '') return null;
  const paise = Number(whole || '0') * PAISE_PER_RUPEE + Number(frac.padEnd(2, '0'));
  if (!Number.isSafeInteger(paise)) return null;
  return minus && paise !== 0 ? -paise : paise;
}

/**
 * Parse a rupee amount into paise without going through floats.
 * Accepts "1,250.50", "₹1,250.5", "1250", ".5", "-20". Rejects more than 2 decimals.
 */
export function toPaise(input: string | number): number {
  const paise = tryToPaise(input);
  if (paise === null) throw new MoneyParseError(String(input));
  return paise;
}

function numberToString(n: number): string | null {
  if (!Number.isFinite(n)) return null;
  // Round to 2dp in string space: 0.1 + 0.2 must still parse as 30 paise.
  return n.toFixed(2);
}

let groupFormatter: Intl.NumberFormat | undefined;

/** "1234567" → "12,34,567" (Indian lakh/crore grouping). */
function groupIndian(rupees: number): string {
  groupFormatter ??= new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0, useGrouping: true });
  return groupFormatter.format(rupees);
}

export type FormatINROptions = {
  /** Prefix with ₹. Default true. */
  symbol?: boolean;
  /** 'always' → "₹1,000.00"; 'auto' → "₹1,000" but "₹1,000.50". Default 'always'. */
  decimals?: 'always' | 'auto';
  /** 'auto' → "-₹5"; 'always' → "+₹5" / "-₹5"; 'never' → "₹5" for both. Default 'auto'. */
  sign?: 'auto' | 'always' | 'never';
};

/** formatINR(125050) → "₹1,250.50"; formatINR(1234567800) → "₹1,23,45,678.00". */
export function formatINR(paise: number, options: FormatINROptions = {}): string {
  assertPaise(paise);
  const { symbol = true, decimals = 'always', sign = 'auto' } = options;
  const abs = Math.abs(paise);
  const rupees = Math.floor(abs / PAISE_PER_RUPEE);
  const rem = abs % PAISE_PER_RUPEE;
  let body = groupIndian(rupees);
  if (decimals === 'always' || rem !== 0) body += '.' + String(rem).padStart(2, '0');
  return signPrefix(paise, sign) + (symbol ? '₹' : '') + body;
}

/**
 * Short form for tight spaces: "₹950", "₹12,500", "₹1.25L", "₹3.4Cr".
 * Below one lakh it shows whole rupees; above, one or two decimals of L/Cr (rounded down,
 * so ₹99,99,999 never shows as "₹1Cr").
 */
export function formatINRCompact(paise: number, options: Pick<FormatINROptions, 'symbol' | 'sign'> = {}): string {
  assertPaise(paise);
  const { symbol = true, sign = 'auto' } = options;
  const abs = Math.abs(paise);
  let body: string;
  if (abs >= CRORE) body = trimDecimal(abs, CRORE) + 'Cr';
  else if (abs >= LAKH) body = trimDecimal(abs, LAKH) + 'L';
  else body = groupIndian(Math.floor(abs / PAISE_PER_RUPEE));
  return signPrefix(paise, sign) + (symbol ? '₹' : '') + body;
}

function trimDecimal(abs: number, unit: number): string {
  const hundredths = Math.floor((abs * 100) / unit);
  const whole = Math.floor(hundredths / 100);
  const frac = String(hundredths % 100).padStart(2, '0').replace(/0+$/, '');
  return frac ? `${groupIndian(whole)}.${frac}` : groupIndian(whole);
}

function signPrefix(paise: number, sign: FormatINROptions['sign']): string {
  if (sign === 'never' || paise === 0) return '';
  if (paise < 0) return '-';
  return sign === 'always' ? '+' : '';
}

function assertPaise(paise: number): void {
  if (!Number.isSafeInteger(paise)) throw new TypeError(`Paise must be a safe integer, got ${paise}`);
}

// ---------------------------------------------------------------------------
// Keypad maths: "120+45", "250×2", "1,000-10.50", "900÷3".

type Op = '+' | '-' | '×' | '÷';
const OPS: Record<string, Op> = { '+': '+', '-': '-', '−': '-', '×': '×', '*': '×', x: '×', '÷': '÷', '/': '÷' };

/**
 * Evaluate a keypad expression to paise with normal precedence (× ÷ before + −).
 * Numbers are parsed as exact paise; × and ÷ round the result to the nearest paisa.
 * A trailing operator is ignored so the live display works while typing ("120+" → 12000).
 * Returns null for malformed input, division by zero or overflow.
 */
export function evaluateAmountExpression(expr: string): number | null {
  const tokens = tokenize(expr);
  if (!tokens || tokens.length === 0) return null;
  if (typeof tokens[tokens.length - 1] !== 'number') tokens.pop();
  if (tokens.length === 0) return null;

  // First pass: × and ÷ (left to right). Right operands are multipliers, stored as paise (×100).
  const terms: (number | Op)[] = [tokens[0]];
  for (let i = 1; i < tokens.length; i += 2) {
    const op = tokens[i] as Op;
    const rhs = tokens[i + 1] as number;
    if (op === '×' || op === '÷') {
      const lhs = terms.pop() as number;
      if (op === '÷' && rhs === 0) return null;
      if (!Number.isSafeInteger(lhs * Math.max(rhs, PAISE_PER_RUPEE))) return null;
      const value = op === '×' ? roundDiv(lhs * rhs, PAISE_PER_RUPEE) : roundDiv(lhs * PAISE_PER_RUPEE, rhs);
      terms.push(value);
    } else {
      terms.push(op, rhs);
    }
  }

  // Second pass: + and −.
  let total = terms[0] as number;
  for (let i = 1; i < terms.length; i += 2) {
    total = terms[i] === '+' ? total + (terms[i + 1] as number) : total - (terms[i + 1] as number);
  }
  return Number.isSafeInteger(total) ? total : null;
}

/** Alternating [number, op, number, op, ...]; null if malformed. */
function tokenize(expr: string): (number | Op)[] | null {
  const src = expr.replace(/[₹,\s]/g, '');
  const tokens: (number | Op)[] = [];
  let i = 0;
  while (i < src.length) {
    const expectNumber = tokens.length % 2 === 0;
    if (expectNumber) {
      const m = /^\d*\.?\d*/.exec(src.slice(i));
      const text = m?.[0] ?? '';
      const paise = text ? tryToPaise(text) : null;
      if (paise === null) return null;
      tokens.push(paise);
      i += text.length;
    } else {
      const op = OPS[src[i]];
      if (!op) return null;
      tokens.push(op);
      i += 1;
    }
  }
  return tokens;
}

/** Integer division rounded half away from zero. */
function roundDiv(n: number, d: number): number {
  const q = Math.round(Math.abs(n) / Math.abs(d));
  return Math.sign(n) * Math.sign(d) < 0 ? -q : q;
}

/** Very short axis labels: "₹500", "₹20K", "₹1.5L", "₹2Cr". */
export function formatINRAxis(paise: number): string {
  assertPaise(paise);
  const rupees = Math.abs(paise) / PAISE_PER_RUPEE;
  const sign = paise < 0 ? '-' : '';
  const short = (v: number) => String(Math.round(v * 10) / 10);
  if (rupees >= 1_00_00_000) return `${sign}₹${short(rupees / 1_00_00_000)}Cr`;
  if (rupees >= 1_00_000) return `${sign}₹${short(rupees / 1_00_000)}L`;
  if (rupees >= 1_000) return `${sign}₹${short(rupees / 1_000)}K`;
  return `${sign}₹${Math.round(rupees)}`;
}
