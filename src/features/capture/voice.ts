import { matchBrand } from '@/features/merchants/brands';

import { type CaptureContext, type CaptureDraft, displayName, findAccount, guessCategory } from './drafts';

const DAY = 86_400_000;

const UNITS: Record<string, number> = {
  zero: 0, one: 1, a: 1, an: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
};
const TENS: Record<string, number> = { twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90 };
const SCALES: Record<string, number> = { hundred: 100, thousand: 1000, k: 1000, lakh: 1e5, lakhs: 1e5, lac: 1e5, lacs: 1e5, crore: 1e7, crores: 1e7 };

const isNumWord = (w: string) => w in UNITS || w in TENS || w in SCALES || w === 'and' || w === 'half';

/**
 * Spoken numbers → digits: "two hundred and fifty" → "250", "one fifty" → "150" (as said in
 * India), "fifteen hundred" → "1500", "two lakh" → "200000". "a"/"an" only count before a scale.
 */
export function wordsToDigits(text: string): string {
  const words = text.split(/(\s+)/);
  const out: string[] = [];
  let i = 0;
  while (i < words.length) {
    const w = words[i].toLowerCase();
    const startsNumber = (w in UNITS && !['a', 'an'].includes(w)) || w in TENS || ((w === 'a' || w === 'an') && words[i + 2]?.toLowerCase() in SCALES);
    if (!startsNumber) {
      out.push(words[i]);
      i++;
      continue;
    }
    // Collect the run of number words (skipping whitespace tokens).
    const run: string[] = [];
    let j = i;
    while (j < words.length) {
      const t = words[j].toLowerCase();
      if (/^\s+$/.test(t)) {
        j++;
        continue;
      }
      if (!isNumWord(t) || (t === 'and' && !(words[j + 2]?.toLowerCase() in UNITS || words[j + 2]?.toLowerCase() in TENS))) break;
      run.push(t);
      j++;
    }
    // Trailing whitespace belongs to the text after the number.
    let end = j;
    while (end > i && /^\s+$/.test(words[end - 1])) end--;
    out.push(String(evaluateWords(run)));
    i = end;
  }
  return out.join('');
}

function evaluateWords(run: string[]): number {
  // "one fifty", "two fifty": a unit followed directly by tens/teens means hundreds.
  const nums = run.filter((w) => w !== 'and');
  if (nums.length >= 2 && nums[0] in UNITS && UNITS[nums[0]] < 10 && (nums[1] in TENS || (nums[1] in UNITS && UNITS[nums[1]] >= 10))) {
    return UNITS[nums[0]] * 100 + evaluateWords(nums.slice(1));
  }
  let total = 0;
  let current = 0;
  for (const w of nums) {
    if (w in UNITS) current += UNITS[w];
    else if (w in TENS) current += TENS[w];
    else if (w === 'half') current += 0.5;
    else if (w === 'hundred') current = (current || 1) * 100;
    else if (w in SCALES) {
      total += (current || 1) * SCALES[w];
      current = 0;
    }
  }
  return total + current;
}

const AMOUNT = /(?:₹|rs\.?|inr)?\s*(\d+(?:,\d{2,3})*(?:\.\d+)?)\s*(k|thousand|hundred|lakhs?|lacs?|crores?|cr)?\b\s*(?:rupees?|rs\.?|bucks|inr|\/-)?/i;

/** The first amount in a phrase, in paise, and the text it covered. */
export function findAmount(text: string): { paise: number; match: string } | null {
  const m = text.match(AMOUNT);
  if (!m) return null;
  const value = Number(m[1].replace(/,/g, ''));
  const scale = m[2] ? (SCALES[m[2].toLowerCase()] ?? (m[2].toLowerCase() === 'cr' ? 1e7 : 1)) : 1;
  const paise = Math.round(value * scale * 100);
  if (!Number.isSafeInteger(paise) || paise <= 0) return null;
  return { paise, match: m[0] };
}

/** Split "250 lunch, 80 auto and 40 chai" into one phrase per amount. */
export function splitPhrases(text: string): string[] {
  const coarse = text
    .split(/,(?!\d)|;|\n|\.(?!\d)|\b(?:and then|then|also|plus|after that)\b/i)
    .map((s) => s.trim())
    .filter(Boolean);
  const out: string[] = [];
  for (const part of coarse) {
    const pieces = part.split(/\band\b/i).map((s) => s.trim()).filter(Boolean);
    // Only split on "and" when it separates amounts ("bread and butter 60" stays whole).
    const withAmount = pieces.filter((p) => findAmount(p));
    if (withAmount.length < 2) {
      out.push(part);
      continue;
    }
    let buffer = '';
    for (const p of pieces) {
      if (findAmount(p) && findAmount(buffer)) {
        out.push(buffer.trim());
        buffer = p;
      } else buffer = buffer ? `${buffer} and ${p}` : p;
    }
    if (buffer) out.push(buffer.trim());
  }
  return out;
}

const WEEKDAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

/** Spoken dates: today, yesterday, day before yesterday, last night, 3 days ago, (last) monday, on the 5th. */
export function findDate(text: string, now: number): { at: number; match: string } | null {
  const lower = text.toLowerCase();
  const noon = (ms: number) => new Date(ms).setHours(12, 0, 0, 0);
  let m: RegExpMatchArray | null;
  if ((m = lower.match(/\b(?:on\s+)?day before yesterday\b/))) return { at: noon(now - 2 * DAY), match: m[0] };
  if ((m = lower.match(/\blast night\b/))) return { at: new Date(now - DAY).setHours(21, 0, 0, 0), match: m[0] };
  if ((m = lower.match(/\byesterday(?:\s+(?:morning|afternoon|evening|night))?\b/))) {
    const part = m[0].split(/\s+/)[1];
    const hours: Record<string, number> = { morning: 9, afternoon: 14, evening: 19, night: 21 };
    const hour = part ? (hours[part] ?? null) : null;
    return { at: hour === null ? now - DAY : new Date(now - DAY).setHours(hour, 0, 0, 0), match: m[0] };
  }
  if ((m = lower.match(/\b(this morning|this afternoon|this evening|tonight|today)\b/))) {
    const hours: Record<string, number> = { 'this morning': 9, 'this afternoon': 14, 'this evening': 19, tonight: 20 };
    const hour = hours[m[1]] ?? null;
    const at = hour === null ? now : Math.min(now, new Date(now).setHours(hour, 0, 0, 0));
    return { at, match: m[0] };
  }
  if ((m = lower.match(/\b(\d{1,2}|a|one|two|three|four|five|six|seven)\s+days?\s+ago\b/))) {
    const n = Number(m[1]) || UNITS[m[1]] || 1;
    return { at: noon(now - n * DAY), match: m[0] };
  }
  if ((m = lower.match(/\b(?:on\s+|last\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b/))) {
    const target = WEEKDAYS.indexOf(m[1]);
    const today = new Date(now).getDay();
    let back = (today - target + 7) % 7;
    if (back === 0 && /last/.test(m[0])) back = 7;
    return { at: back === 0 ? now : noon(now - back * DAY), match: m[0] };
  }
  if ((m = lower.match(/\bon\s+(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)\b/))) {
    const day = Number(m[1]);
    const d = new Date(now);
    let at = new Date(d.getFullYear(), d.getMonth(), day, 12).getTime();
    if (day > d.getDate()) at = new Date(d.getFullYear(), d.getMonth() - 1, day, 12).getTime();
    return { at, match: m[0] };
  }
  return null;
}

const INCOME = /\b(received|receive|earned|salary|credited|refund(?:ed)?|cashback|income|bonus|stipend|got paid|got back)\b|\bgot\b.*\bfrom\b/i;
const CARD_BILL = /\b(?:paid|pay|cleared|clear)\b.*\b(?:credit\s+)?card\s+bill\b|\bcard\s+(?:bill\s+)?payment\b/i;
const TRANSFER = /\b(?:transfer(?:red)?|moved?|sent|shift(?:ed)?|deposited|withdrew|withdrawn)\b/i;
const FILLER =
  /\b(?:i|i've|ive|i have|just|spent|spend|paid|pay|bought|buy|for|on|at|to|the|a|an|my|of|got|gave|give|was|is|it|some|from|today|rupees?|rs|bucks|expense|income|transferred|transfer|moved|sent|received|earned|credited|added|add|log|record)\b/gi;

function tidy(text: string): string {
  return text.replace(/\s+/g, ' ').replace(/^[\s,.\-–]+|[\s,.\-–]+$/g, '').trim();
}

/**
 * Turn a spoken sentence into draft transactions, entirely on the phone:
 * "250 lunch, 80 auto and 40 chai" → three expenses; "got salary 90k yesterday" → income;
 * "moved 5000 from axis to baroda" → transfer; "paid card bill 8360" → transfer to the card.
 */
export function parseSpokenTransactions(sentence: string, ctx: CaptureContext): { drafts: CaptureDraft[]; skipped: string[] } {
  const text = wordsToDigits(sentence.replace(/[“”"]/g, ''));
  const drafts: CaptureDraft[] = [];
  const skipped: string[] = [];
  // A date or account said once applies to the following phrases too ("yesterday 200 lunch and 50 chai").
  let carryDate: number | null = null;
  let carryAccount: string | null = null;

  splitPhrases(text).forEach((phrase, index) => {
    const amount = findAmount(phrase);
    if (!amount) {
      if (phrase.trim()) skipped.push(phrase.trim());
      const d = findDate(phrase, ctx.now);
      if (d) carryDate = d.at;
      return;
    }
    let rest = phrase.replace(amount.match, ' ');
    const date = findDate(rest, ctx.now);
    if (date) {
      rest = rest.replace(new RegExp(date.match, 'i'), ' ');
      carryDate = date.at;
    }

    let type: CaptureDraft['type'] = INCOME.test(phrase) ? 'income' : 'expense';
    let accountId: string | null = null;
    let toAccountId: string | null = null;

    // Transfers: "from A to B", or paying a credit card bill.
    const fromTo = rest.match(/\bfrom\s+(.+?)\s+(?:to|into)\s+(.+)$/i);
    if (fromTo && TRANSFER.test(phrase)) {
      const a = findAccount(fromTo[1], ctx.accounts);
      const b = findAccount(fromTo[2], ctx.accounts);
      if (a && b && a.account.id !== b.account.id) {
        type = 'transfer';
        accountId = a.account.id;
        toAccountId = b.account.id;
        rest = rest.replace(fromTo[0], ' ');
      }
    }
    if (type !== 'transfer' && CARD_BILL.test(phrase)) {
      const cards = ctx.accounts.filter((a) => a.type === 'card');
      const named = findAccount(rest.replace(/\bcard\s+bill\b|\bbill\b/gi, ' '), ctx.accounts);
      const card = named?.account.type === 'card' ? named.account : cards.length === 1 ? cards[0] : null;
      const from =
        named && named.account.type !== 'card'
          ? named.account
          : (ctx.accounts.find((a) => a.id === ctx.defaultAccountId && a.type !== 'card') ?? ctx.accounts.find((a) => a.type === 'bank'));
      if (card && from) {
        type = 'transfer';
        accountId = from.id;
        toAccountId = card.id;
        rest = ' ';
      }
    }
    if (type !== 'transfer') {
      const acc = findAccount(rest, ctx.accounts);
      if (acc) {
        accountId = acc.account.id;
        carryAccount = acc.account.id;
        rest = rest.replace(new RegExp(`(^|\\s)${acc.phrase.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')}(?=$|\\s|[,.;!?])`, 'i'), ' ');
      }
    }

    // Payee: "to Rahul", "at DMart", "from Acme" (income), or a known brand.
    let payee: string | null = null;
    const named = rest.match(type === 'income' ? /\bfrom\s+([a-z][\w&'.-]*(?:\s+[a-z][\w&'.-]*){0,2})/i : /\b(?:to|at)\s+([a-z][\w&'.-]*(?:\s+[a-z][\w&'.-]*){0,2})/i);
    if (named) {
      payee = displayName(named[1]);
      rest = rest.replace(named[0], ' ');
    }
    const description = tidy(rest.replace(FILLER, ' '));
    if (!payee && matchBrand(description)) {
      payee = matchBrand(description)!.name;
    }
    const note = description && description.toLowerCase() !== payee?.toLowerCase() ? displayName(description) : null;
    const brandInNote = note && payee && note.toLowerCase().includes(payee.toLowerCase());

    drafts.push({
      key: `voice-${index}`,
      type,
      amount: amount.paise,
      accountId: accountId ?? carryAccount ?? ctx.defaultAccountId ?? ctx.accounts[0]?.id ?? null,
      toAccountId,
      categoryId: guessCategory(description, payee, type, ctx),
      payee,
      note: brandInNote ? null : note,
      occurredAt: carryDate ?? ctx.now,
      source: phrase.trim(),
      include: true,
    });
  });
  return { drafts, skipped };
}
