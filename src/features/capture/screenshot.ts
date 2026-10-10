import { matchBrand } from '@/features/merchants/brands';

import { type CaptureContext, type CaptureDraft, displayName, findAccount, guessCategory } from './drafts';

const MONTHS: Record<string, number> = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, sept: 8, oct: 9, nov: 10, dec: 11 };

/** OCR output (lines on iOS, blocks on Android) → clean, non-empty lines. */
export function toLines(texts: string[]): string[] {
  return texts
    .flatMap((t) => t.split(/\r?\n/))
    .map((l) => l.replace(/\s+/g, ' ').trim())
    .filter(Boolean);
}

/** Lines that hold ids, not amounts (UTR 424412345678, Transaction ID T2410…). */
const ID_LINE = /\b(utr|upi ref|ref(erence)?\s*(no|number|id)?|transaction id|txn id|order id|google transaction|upi transaction|rrn)\b/i;

/** The paid amount: a ₹/Rs/INR figure, or the figure next to "Amount". */
export function findPaidAmount(lines: string[]): number | null {
  const money = /(?:₹|rs\.?|inr|amount\s*(?:paid|sent|received)?\s*:?\s*₹?)\s*([\d,]+(?:\.\d{1,2})?)\b/i;
  for (const line of lines) {
    if (ID_LINE.test(line)) continue;
    const m = line.match(money);
    if (m) {
      const paise = Math.round(Number(m[1].replace(/,/g, '')) * 100);
      if (paise > 0 && Number.isSafeInteger(paise)) return paise;
    }
  }
  // Some OCR drops the ₹: a line that is only a money-looking number ("420", "1,250.00").
  for (const line of lines) {
    const m = line.match(/^([\d,]{1,9}(?:\.\d{2})?)$/);
    if (m && !/^\d{10,}$/.test(m[1].replace(/,/g, ''))) {
      const paise = Math.round(Number(m[1].replace(/,/g, '')) * 100);
      if (paise > 0) return paise;
    }
  }
  return null;
}

/** Date and time on the receipt: "10 Oct 2026, 2:15 pm", "02:15 pm on 10 Oct 2026", "10 Oct, 02:15 PM", "10/10/2026 14:15". */
export function findReceiptDate(lines: string[], now: number): number | null {
  const text = lines.join(' \n ');
  let day: number | undefined;
  let month: number | undefined;
  let year: number | undefined;
  let m = text.match(/\b(\d{1,2})(?:st|nd|rd|th)?[\s-]+(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*[\s,-]*(\d{4})?/i);
  if (m) {
    day = Number(m[1]);
    month = MONTHS[m[2].toLowerCase()];
    year = m[3] ? Number(m[3]) : undefined;
  } else if ((m = text.match(/\b(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\s+(\d{1,2}),?\s*(\d{4})?/i))) {
    month = MONTHS[m[1].toLowerCase()];
    day = Number(m[2]);
    year = m[3] ? Number(m[3]) : undefined;
  } else if ((m = text.match(/\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})\b/))) {
    day = Number(m[1]);
    month = Number(m[2]) - 1;
    year = Number(m[3]) < 100 ? 2000 + Number(m[3]) : Number(m[3]);
  }
  if (day === undefined || month === undefined) return null;
  let hours = 12;
  let minutes = 0;
  const t = text.match(/\b(\d{1,2}):(\d{2})(?::\d{2})?\s*(am|pm)?\b/i);
  if (t) {
    hours = Number(t[1]) % 24;
    minutes = Number(t[2]);
    if (t[3]?.toLowerCase() === 'pm' && hours < 12) hours += 12;
    if (t[3]?.toLowerCase() === 'am' && hours === 12) hours = 0;
  }
  const thisYear = new Date(now).getFullYear();
  let at = new Date(year ?? thisYear, month, day, hours, minutes).getTime();
  // No year printed and the date is ahead of today: it was last year.
  if (year === undefined && at > now + 86_400_000) at = new Date(thisYear - 1, month, day, hours, minutes).getTime();
  return Number.isNaN(at) ? null : at;
}

const RECEIVED = /\b(received from|money received|you received|credited to your|received)\b/i;
const SENT = /\b(paid to|paid successfully|payment successful|money sent|sent to|debited from|you paid|transaction successful)\b/i;
const FAILED = /\b(failed|declined|unsuccessful|pending|processing)\b/i;
// Labels whose value is on the next line.
const PAYEE_LABEL = /^(paid to|paid successfully to|money sent to|sent to|received from|to|from|beneficiary( name)?|payee( name)?|merchant( name)?|paying)\s*:?$/i;
const NOT_A_NAME = /(@|\d{6,}|successful|completed|transaction|upi|banking name|share|split|pay again|view|details|debited|credited|xx|\*\*|•)/i;

function payeeFrom(lines: string[], received: boolean): { name: string | null; upiId: string | null } {
  const upiId = lines.map((l) => l.match(/\b[\w.-]{2,}@[a-z]{2,}\b/i)?.[0]).find(Boolean) ?? null;
  const want = received ? /^(received from|from|money received from)\b/i : /^(paid to|paid successfully to|money sent to|sent to|to|beneficiary|payee|merchant|paying)\b/i;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (PAYEE_LABEL.test(line) && want.test(line)) {
      const next = lines.slice(i + 1, i + 3).find((l) => !NOT_A_NAME.test(l) && /[a-z]/i.test(l) && !/^₹/.test(l));
      if (next) return { name: next, upiId };
      continue;
    }
    const inline = line.match(received ? /^(?:received from|from)\s*:?\s+(.+)$/i : /^(?:paid to|paid successfully to|money sent to|sent to|to|beneficiary name|payee name)\s*:?\s+(.+)$/i);
    if (inline && !NOT_A_NAME.test(inline[1]) && /[a-z]/i.test(inline[1])) return { name: inline[1].replace(/\s*\(.*\)\s*$/, ''), upiId };
  }
  return { name: null, upiId };
}

/** The user's own account on the receipt: "Debited from XX5678", "From: Nishit (Axis Bank)", "Axis Bank ••5678". */
function accountFrom(lines: string[], ctx: CaptureContext) {
  const own = lines.filter((l) => /(debited|credited|from|account|a\/c|bank|xx|\*{2,}|•{2,})/i.test(l));
  for (const line of own) {
    const last4 = line.match(/(?:x{2,}|\*{2,}|•{2,}|\.{2,}|a\/c\s*(?:no\.?)?\s*)\s*(\d{4})\b/i)?.[1];
    if (last4) {
      const hit = ctx.accounts.find((a) => a.last4 === last4);
      if (hit) return hit;
    }
  }
  for (const line of own) {
    const hit = findAccount(line, ctx.accounts);
    if (hit) return hit.account;
  }
  return null;
}

/**
 * Read one payment screenshot (GPay, PhonePe, Paytm, BHIM, CRED, bank apps) into a draft.
 * Returns null when there's no amount to be found.
 */
export function parsePaymentScreenshot(texts: string[], ctx: CaptureContext, key = 'shot'): CaptureDraft | null {
  const lines = toLines(texts);
  const amount = findPaidAmount(lines);
  if (!amount) return null;
  const text = lines.join('\n');
  const received = RECEIVED.test(text) && !/\bpaid to\b|\bdebited from\b/i.test(text);
  const { name, upiId } = payeeFrom(lines, received);
  const account = accountFrom(lines, ctx);
  const brand = matchBrand(name) ?? matchBrand(upiId);
  const payee = brand?.name ?? (name ? displayName(name.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase())) : upiId ? upiId.split('@')[0] : null);

  let type: CaptureDraft['type'] = received ? 'income' : 'expense';
  let toAccountId: string | null = null;
  let accountId: string | null = account?.id ?? ctx.defaultAccountId ?? ctx.accounts[0]?.id ?? null;
  // Paying a credit card bill (CRED, GPay "Axis Bank Credit Card") is a transfer to the card.
  if (!received && /credit card|card bill|cc bill|card payment/i.test(text)) {
    const cards = ctx.accounts.filter((a) => a.type === 'card');
    const last4s = [...text.matchAll(/(\d{4})\b/g)].map((m) => m[1]);
    const card = cards.find((c) => c.last4 && last4s.includes(c.last4)) ?? (cards.length === 1 ? cards[0] : undefined);
    if (card) {
      type = 'transfer';
      toAccountId = card.id;
      if (accountId === card.id) accountId = ctx.accounts.find((a) => a.type === 'bank')?.id ?? null;
    }
  }

  const failed = FAILED.test(text) && !/\bsuccess/i.test(text);
  return {
    key,
    type,
    amount,
    accountId,
    toAccountId,
    categoryId: guessCategory(`${name ?? ''} ${upiId ?? ''}`, payee, type, ctx),
    payee: type === 'transfer' ? null : payee,
    note: type === 'transfer' ? 'Card bill payment' : null,
    occurredAt: findReceiptDate(lines, ctx.now) ?? ctx.now,
    source: lines.slice(0, 12).join(' · '),
    include: !failed,
    ...(failed ? { warning: 'This payment may have failed or be pending.' } : {}),
    ...(SENT.test(text) || received ? {} : { warning: 'Couldn’t tell if this was a payment. Check the details.' }),
  };
}
