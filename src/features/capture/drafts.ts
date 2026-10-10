import type { AccountType, CategoryKind, TransactionType } from '@/db/schema';
import { suggestCategoryName } from '@/features/import/narration';
import { matchBrand } from '@/features/merchants/brands';

/** A transaction captured by voice or from a screenshot, waiting for the user to confirm it. */
export type CaptureDraft = {
  key: string;
  type: TransactionType;
  /** Paise, > 0. */
  amount: number;
  accountId: string | null;
  toAccountId: string | null;
  categoryId: string | null;
  payee: string | null;
  note: string | null;
  occurredAt: number;
  /** What it was read from (the spoken phrase, or the screenshot's key lines). */
  source: string;
  include: boolean;
  /** Shown on the review card, e.g. a failed payment or a likely duplicate. */
  warning?: string;
};

export type CaptureAccount = { id: string; name: string; type: AccountType; institution: string | null; last4: string | null };
export type CaptureCategory = { id: string; name: string; kind: CategoryKind; parentId: string | null };

export type CaptureContext = {
  accounts: CaptureAccount[];
  categories: CaptureCategory[];
  /** Lower-cased payee → category id, learned from past transactions. */
  learned?: Map<string, string>;
  /** Account to use when none is mentioned. */
  defaultAccountId?: string | null;
  now: number;
};

const GENERIC = new Set(['bank', 'card', 'credit', 'debit', 'account', 'acct', 'savings', 'saving', 'current', 'salary', 'my', 'the', 'of', 'ac', 'a/c']);

/** Words that refer to an account, longest first, so "axis myzone" wins over "axis". */
function accountPhrases(a: CaptureAccount): string[] {
  const phrases = new Set<string>();
  const name = a.name.toLowerCase().trim();
  phrases.add(name);
  for (const w of name.split(/\s+/)) if (w.length >= 3 && !GENERIC.has(w)) phrases.add(w);
  if (a.institution) {
    const inst = a.institution.toLowerCase();
    phrases.add(inst);
    for (const w of inst.split(/\s+/)) if (w.length >= 3 && !GENERIC.has(w)) phrases.add(w);
  }
  // Common spoken names for Indian banks.
  if (/baroda|\bbob\b/.test(`${name} ${a.institution ?? ''}`.toLowerCase())) phrases.add('bob').add('baroda').add('bank of baroda');
  if (/\bsbi\b|state bank/.test(`${name} ${a.institution ?? ''}`.toLowerCase())) phrases.add('sbi').add('state bank');
  if (a.last4) phrases.add(a.last4);
  return [...phrases].sort((x, y) => y.length - x.length);
}

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');

/**
 * Find an account mentioned in `text` ("from axis", "on my card", "cash", "BoB", "xx1234").
 * Returns the account and the matched phrase (with its preposition) so callers can strip it.
 */
export function findAccount(text: string, accounts: CaptureAccount[]): { account: CaptureAccount; phrase: string } | null {
  const lower = text.toLowerCase();
  const prep = String.raw`(?:(?:from|on|using|with|via|by|through|in|thru|frm)\s+)?(?:(?:my|the)\s+)?`;
  const tail = String.raw`(?:\s+(?:bank|account|acct|a\/c|card|credit card|debit card|wallet))?`;
  let best: { account: CaptureAccount; phrase: string; len: number } | null = null;
  for (const a of accounts) {
    for (const p of accountPhrases(a)) {
      const m = lower.match(new RegExp(String.raw`(?:^|\s)(${prep}${escape(p)}${tail})(?=$|[\s,.;!?])`));
      if (m && (!best || p.length > best.len)) best = { account: a, phrase: m[1], len: p.length };
    }
  }
  if (best) return { account: best.account, phrase: best.phrase };
  // Type words, only when exactly one account of that type exists.
  const byType: [RegExp, AccountType][] = [
    [new RegExp(String.raw`(?:^|\s)(${prep}cash)(?=$|[\s,.;!?])`), 'cash'],
    [new RegExp(String.raw`(?:^|\s)(${prep}(?:credit\s+)?card)(?=$|[\s,.;!?])`), 'card'],
    [new RegExp(String.raw`(?:^|\s)(${prep}wallet)(?=$|[\s,.;!?])`), 'wallet'],
  ];
  for (const [re, type] of byType) {
    const m = lower.match(re);
    const ofType = accounts.filter((a) => a.type === type);
    if (m && ofType.length === 1) return { account: ofType[0], phrase: m[1] };
  }
  return null;
}

/** Everyday words → starter category names (on top of the statement-import rules). */
const SPOKEN_CATEGORIES: [RegExp, string][] = [
  [/\b(lunch|dinner|breakfast|brunch|snacks?|chai|tea|coffee|juice|food|meal|biryani|pizza|burger|dosa|idli|samosa|momos?|restaurant|cafe|canteen|tiffin|swiggy|zomato)\b/i, 'Food & Dining'],
  [/\b(groceries|grocery|vegetables?|veggies|sabzi|fruits?|milk|eggs|bread|atta|rice|dal|kirana|ration)\b/i, 'Groceries'],
  [/\b(petrol|diesel|fuel|cng)\b/i, 'Fuel'],
  [/\b(auto|rickshaw|cab|taxi|uber|ola|rapido|metro|bus|train ticket|local train|toll|parking|fastag)\b/i, 'Metro/Auto/Cab'],
  [/\b(rent)\b/i, 'Rent'],
  [/\b(electricity|power bill|light bill)\b/i, 'Electricity'],
  [/\b(recharge|mobile bill|phone bill|wifi|internet|broadband)\b/i, 'Mobile/Internet'],
  [/\b(medicines?|medical|doctor|pharmacy|hospital|clinic|tablets?|chemist)\b/i, 'Health'],
  [/\b(movie|movies|cinema|concert|game|netflix)\b/i, 'Entertainment'],
  [/\b(clothes|shirt|shoes|jeans|dress|kurta|shopping|amazon|flipkart|myntra)\b/i, 'Shopping'],
  [/\b(flight|hotel|trip|travel|holiday)\b/i, 'Travel'],
  [/\b(haircut|salon|spa|gym|parlour)\b/i, 'Personal Care'],
  [/\b(gift|donation|temple|church|mosque|gurudwara)\b/i, 'Gifts & Donations'],
  [/\b(fees|tuition|books?|course)\b/i, 'Education'],
  [/\b(salary|paycheck)\b/i, 'Salary'],
  [/\b(freelance|client|invoice)\b/i, 'Freelance'],
  [/\b(refund|returned)\b/i, 'Refund'],
  [/\b(cashback)\b/i, 'Cashback'],
  [/\b(interest)\b/i, 'Interest'],
];

/** Best category for a description/payee: history first, then everyday words, then statement rules. */
export function guessCategory(text: string, payee: string | null, type: TransactionType, ctx: CaptureContext): string | null {
  if (type === 'transfer') return null;
  const kind: CategoryKind = type === 'income' ? 'income' : 'expense';
  const ofKind = ctx.categories.filter((c) => c.kind === kind);
  if (payee && ctx.learned) {
    const id = ctx.learned.get(payee.toLowerCase());
    if (id && ofKind.some((c) => c.id === id)) return id;
  }
  const byName = (name: string) => ofKind.find((c) => c.name.toLowerCase() === name.toLowerCase())?.id ?? null;
  const haystack = `${payee ?? ''} ${text}`;
  // A category the user named directly ("groceries", "rent").
  for (const c of ofKind) {
    if (c.name.length >= 3 && new RegExp(`\\b${escape(c.name.toLowerCase())}\\b`).test(haystack.toLowerCase())) return c.id;
  }
  for (const [re, name] of SPOKEN_CATEGORIES) if (re.test(haystack) && byName(name)) return byName(name);
  const rule = suggestCategoryName(text, payee, kind === 'income' ? 'in' : 'out');
  return rule ? byName(rule) : null;
}

/** "swiggy" → "Swiggy", known brands get their proper name. */
export function displayName(text: string): string {
  const brand = matchBrand(text);
  if (brand) return brand.name;
  const t = text.trim();
  return t ? t.charAt(0).toUpperCase() + t.slice(1) : t;
}
