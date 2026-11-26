// Bank SMS → transaction, in the browser. A JavaScript port of the apps' BankAlerts parser
// (androidApp …/logic/BankAlerts.kt, apple/App/Import/BankAlerts.swift), checked by scripts/website-parser.test.mjs
// against the same cases. Nothing typed into the demo leaves the page.
(() => {
  const ri = (p) => new RegExp(p, 'i');
  const rg = (p) => new RegExp(p, 'gi');

  const ignore = ri("\\b(otp|one[- ]time password|verification code|will be (auto[- ]?)?debited|is due|due (on|date|by)|minimum (amount )?due|" +
    "has requested|requested (money|rs|inr|₹)|collect request|request of|failed|declined|unsuccessful|reversal|reversed|" +
    "pre-?approved|apply now|offer|cashback of up to|e-?mandate (is )?(created|registered)|statement (is|has been) generated)\\b");
  const debit = ri('\\b(debited|spent|sent|paid|withdrawn|purchase|deducted|transferred from|txn of|dr\\.?)\\b');
  const credit = ri('\\b(credited|received|deposited|cr\\.?)\\b');
  const money = '(?:rs\\.?|inr|₹)\\s*([\\d,]+(?:\\.\\d{1,2})?)';
  const bareAmount = ri('\\b(?:debited|credited|spent|sent|paid)\\s+(?:by|with|for|of)?\\s*([\\d,]+(?:\\.\\d{1,2})?)\\b');
  const notTheAmount = ri('(avl|avbl|available|total|a/c|acct)?\\.?\\s*(bal|balance|lmt|limit)\\s*:?\\s*$');
  const last4 = '(?:x{2,}|\\*+|\\.{2,}|ending(?:\\s+(?:with|in))?\\s*|a/c\\s*(?:no\\.?)?\\s*[x*]*|acct\\s*[x*]*|card\\s*(?:no\\.?)?\\s*[x*]*)(\\d{3,4})\\b';
  const ref = ri('(?:ref(?:erence)?(?:\\s*no\\.?)?|rrn|utr|upi(?:\\s*ref)?(?:\\s*no\\.?)?)[\\s:.#-]*(\\d{9,16})');
  const upiRef = ri('upi/(?:p2[ma]/)?(\\d{9,16})');
  const vpa = ri('\\b([\\w.-]{2,}@[a-z]{2,})\\b');
  const cardBill = ri('(payment|amount) of .{0,40}(received|credited) (towards|to|on|for) your .{0,30}credit card|credit card .{0,40}payment .{0,20}(received|credited)');

  const payeePatterns = [
    ri("info[-:\\s]+(?:upi/(?:p2[ma]/)?\\d+/)?([a-z0-9][a-z0-9 .&'_-]{1,40}?)(?:/|\\s+not you|\\.\\s|\\.$|$)"), // Axis
    ri("trf to\\s+([a-z0-9][a-z0-9 .&'_-]{1,40}?)\\s+(?:ref\\w*|on)\\b"), // SBI
    ri(";\\s*([a-z0-9][a-z0-9 .&'_-]{1,40}?)\\s+credited\\b"), // ICICI
    ri("\\btowards\\s+([a-z][a-z0-9 .&'_-]{1,40}?)\\s+(?:for|on|ref\\w*|umn|via|vide|dt|date)\\b"), // BoB, UPI mandates
    ri("\\bto[:\\s]+(?:vpa\\s+)?([a-z0-9][a-z0-9 .&'@_-]{1,40}?)\\s+(?:on|ref\\w*|via|upi|from|dt|date)\\b"), // HDFC, Kotak
    ri("\\bat\\s+([a-z0-9][a-z0-9 .&'*_-]{1,40}?)(?:\\s+on\\b|\\s+avl|\\.\\s|,|\\.$|$)"), // card spends
    ri("\\b(?:from|by)\\s+(?:(?:neft|imps|rtgs|upi|transfer)\\s+(?:from\\s+)?)?([a-z][a-z0-9 .&'_-]{1,40}?)(?:\\s+on\\b|\\s+ref\\w*|\\s+upi|\\.\\s|\\.$|$)"), // income
  ];
  const companySuffix = ri('\\s+(?:(?:pvt|private)\\.?\\s*)?(?:ltd|limited)\\.?$|\\s+(?:pvt|private)\\.?$');
  const junkPayee = ri('^(upi|neft|imps|rtgs|your|a/c|acct|account|card|bank|vpa|you|the|net ?banking|atm|pos)\\b|^\\d+$|^[0-9a-f]{12,}$|\\d{8,}');

  const BANKS = [
    [/axis/i, 'Axis Bank'], [/bank of baroda|\bbob\b|baroda/i, 'Bank of Baroda'], [/hdfc/i, 'HDFC Bank'], [/icici/i, 'ICICI Bank'],
    [/\bsbi\b|state bank/i, 'SBI'], [/kotak/i, 'Kotak'], [/\byes bank/i, 'Yes Bank'], [/idfc/i, 'IDFC FIRST'], [/indusind/i, 'IndusInd'],
    [/canara/i, 'Canara Bank'], [/\bpnb\b|punjab national/i, 'PNB'], [/union bank/i, 'Union Bank'], [/federal/i, 'Federal Bank'],
  ];

  const D = () => globalThis.PaisaData || { brands: [], categoryRules: [] };
  const brand = (text) => {
    if (!text) return null;
    const b = D().brands.find(([re]) => re.test(text));
    return b ? { name: b[1], color: b[2] } : null;
  };

  function paise(s) {
    const m = /^(\d+)(?:\.(\d{1,2}))?$/.exec(s.replace(/,/g, ''));
    if (!m) return null;
    const p = Number(m[1]) * 100 + Number((m[2] || '').padEnd(2, '0'));
    return p > 0 ? p : null;
  }

  function amount(text) {
    for (const m of text.matchAll(rg(money))) {
      const before = text.slice(Math.max(0, m.index - 28), m.index);
      if (notTheAmount.test(before)) continue;
      const p = paise(m[1]);
      if (p != null) return p;
    }
    const b = bareAmount.exec(text);
    return b ? paise(b[1]) : null;
  }

  function payee(text) {
    for (const p of payeePatterns) {
      const m = p.exec(text);
      if (!m) continue;
      const raw = m[1].trim().replace(/[.\-/]+$/, '');
      if (raw.length < 2 || junkPayee.test(raw)) continue;
      const name = raw.includes('@') ? raw.split('@')[0] : raw;
      return name.replace(companySuffix, '') || name;
    }
    // A VPA's name part, unless it's an ID (UPI mandate numbers look like 01a2079d…@yesg).
    const v = vpa.exec(text);
    const name = v ? v[1].split('@')[0] : null;
    return name && !junkPayee.test(name) ? name : null;
  }

  // Java's String.hashCode, so keys match the apps' keys.
  function javaHash(s) {
    let h = 0;
    for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
    return (h >>> 0).toString(16);
  }

  function key(text, amt) {
    const r = (upiRef.exec(text) || ref.exec(text) || [])[1];
    if (r) return `alert:${r}`;
    const norm = text.toLowerCase().replace(/[^a-z0-9]/g, '');
    return `alert:${amt}:${javaHash(norm)}`;
  }

  function method(text) {
    const t = text.toLowerCase();
    if (/\b(nach|ecs|mandate|autopay|auto debit|auto-debit|standing instruction|\bsi\b|\bumn\b)/.test(t)) return 'Auto-debit';
    if (/\brtgs\b/.test(t)) return 'RTGS';
    if (/\bneft\b/.test(t)) return 'NEFT';
    if (/\bimps\b/.test(t)) return 'IMPS';
    if (/\bupi\b|@[a-z]{2,}\b|\bvpa\b/.test(t)) return 'UPI';
    if (/\bcredit card\b|\bcard\b.*\b(lmt|limit)\b/.test(t)) return 'Credit card';
    if (/\b(chq|cheque|clg|clearing)\b/.test(t)) return 'Cheque';
    if (/\b(net ?banking|inb|ib fund|internet banking)\b/.test(t)) return 'Net banking';
    if (/\b(atm|cash wdl|cash withdrawal)\b/.test(t)) return 'ATM';
    if (/\b(pos|ecom|card \d{4}|debit card|card)\b/.test(t)) return 'Card';
    return null;
  }

  function category(text, name, type) {
    if (type === 'transfer') return null;
    const s = `${name || ''} ${text}`;
    for (const [re, cat] of D().categoryRules) {
      if (!re.test(s)) continue;
      const incomeOnly = ['Salary', 'Interest', 'Cashback', 'Refund'].includes(cat);
      if (incomeOnly === (type === 'income')) return cat;
    }
    return null;
  }

  // Why a message was skipped, in plain words.
  function skipReason(text) {
    const t = text.toLowerCase();
    if (/\botp\b|one[- ]time password|verification code/.test(t)) return 'This is an OTP, not a payment. Skipped.';
    if (/will be (auto[- ]?)?debited|e-?mandate/.test(t)) return 'A future debit, not a payment yet. Skipped.';
    if (/is due|due (on|date|by)|minimum (amount )?due|statement/.test(t)) return 'A bill reminder, not a payment. It shows up under Bills instead.';
    if (/requested|collect request|request of/.test(t)) return 'A payment request, not a payment. Skipped.';
    if (/failed|declined|unsuccessful|revers/.test(t)) return 'The payment didn\'t go through. Skipped.';
    if (/offer|pre-?approved|apply now|cashback of up to/.test(t)) return 'An offer or ad. Skipped.';
    return 'Doesn\'t look like money moving. Skipped.';
  }

  /** Same rules as the apps. Returns { draft } or { skipped: reason }. */
  function parse(input, sender = '') {
    const text = String(input || '').replace(/\s+/g, ' ').trim();
    if (!text) return { skipped: 'Paste a bank message to try it.' };
    if (ignore.test(text)) return { skipped: skipReason(text) };
    const amt = amount(text);
    if (amt == null) return { skipped: 'No amount found. Is this a bank debit or credit message?' };
    const isDebit = debit.test(text);
    const isCredit = !isDebit && credit.test(text);
    const isBill = cardBill.test(text);
    if (!isDebit && !isCredit && !isBill) return { skipped: skipReason(text) };

    const l4 = [...text.matchAll(rg(last4))].map((m) => m[1]);
    const bank = (BANKS.find(([re]) => re.test(`${text} ${sender}`)) || [])[1] || null;
    const isCard = /\bcard\b/i.test(text) && !/debit card/i.test(text);
    const type = isBill ? 'transfer' : isCredit ? 'income' : 'expense';
    const name = payee(text);
    const b = brand(name) || brand(text);
    const titled = name ? name.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase()) : null;
    const payeeName = type === 'transfer' ? null : b ? b.name : titled;
    return {
      draft: {
        key: key(text, amt), type, amount: amt, payee: payeeName, brandColor: b ? b.color : null,
        category: category(`${text} ${name || ''}`, payeeName, type),
        bank, last4: l4[0] || null, accountKind: isBill || isCard ? 'card' : 'bank',
        method: method(text), note: type === 'transfer' ? 'Card bill payment' : null,
      },
    };
  }

  const api = { parse, amount, payee, key, method };
  globalThis.PaisaParser = api;
})();
