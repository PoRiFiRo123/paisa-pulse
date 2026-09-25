export type Channel = 'UPI' | 'NEFT' | 'IMPS' | 'RTGS' | 'POS' | 'ATM' | 'NACH' | 'INTEREST' | 'CHARGES' | 'CARD_PAYMENT' | 'REFUND' | 'OTHER';

export type Narration = {
  channel: Channel;
  /** Clean, human payee ("Swiggy", "Acme Technologies"), or null if none could be found. */
  payee: string | null;
  upiId: string | null;
  /** Leftover remark, e.g. the UPI note "rent share". */
  note: string | null;
};

// Tokens that are never the counterparty's name.
const STOP = new Set(
  [
    'upi', 'p2m', 'p2a', 'dr', 'cr', 'neft', 'imps', 'rtgs', 'ach', 'nach', 'pos', 'ecom', 'mob', 'mb', 'ib', 'inb', 'net',
    'to transfer', 'by transfer', 'transfer', 'payment', 'pay', 'paid', 'paid via', 'sent using', 'upi payment', 'collect',
    'request', 'purchase', 'txn', 'ref', 'na', 'null', 'others', 'other', 'self', 'fund transfer', 'fund trf', 'trf', 'ft',
    'credit', 'debit', 'cash', 'from', 'to', 'by', 'via', 'ok', 'upiintent', 'intent', 'no remarks',
  ],
);
// 4-letter bank codes and IFSCs that appear inside UPI/NEFT narrations.
const BANK_CODE = /^[a-z]{4}(0[a-z0-9]{6})?$/i;
const BANKS = /^(icic|hdfc|sbin|utib|barb|yesb|kkbk|punb|cnrb|ubin|idib|indb|idfb|pytm|airp|fdrl|bkid|ioba|maha|cbin|jaka|scbl|citi|hsbc|rbl|au|axis|icici|sbi|bob|kotak|paytm|ybl|ibl|axl|okaxis|oksbi|okhdfcbank|okicici|apl|jupiteraxis|fam)$/i;

/** Known Indian merchants: narration/legal names → display name. */
const BRANDS: [RegExp, string][] = [
  [/swiggy|bundl tech/i, 'Swiggy'],
  [/zomato|zomato media|eternal ltd/i, 'Zomato'],
  [/blinkit|grofers/i, 'Blinkit'],
  [/zepto|kiranakart/i, 'Zepto'],
  [/big\s?basket|supermarket grocery/i, 'BigBasket'],
  [/instamart/i, 'Swiggy Instamart'],
  [/dmart|avenue supermarts/i, 'DMart'],
  [/uber/i, 'Uber'],
  [/\bola\b|ani technologies|olacabs/i, 'Ola'],
  [/rapido|roppen/i, 'Rapido'],
  [/amazon pay|amazon/i, 'Amazon'],
  [/flipkart/i, 'Flipkart'],
  [/myntra/i, 'Myntra'],
  [/nykaa/i, 'Nykaa'],
  [/ajio/i, 'AJIO'],
  [/meesho/i, 'Meesho'],
  [/netflix/i, 'Netflix'],
  [/spotify/i, 'Spotify'],
  [/youtube|google\s?play|google\s?india digital|google/i, 'Google'],
  [/apple\s?(services|media)|itunes|apple\.com/i, 'Apple'],
  [/hotstar|jiocinema|jiohotstar|novi digital/i, 'JioHotstar'],
  [/prime video|amazon prime/i, 'Amazon Prime'],
  [/bookmyshow|bigtree/i, 'BookMyShow'],
  [/\bpvr\b|inox/i, 'PVR INOX'],
  [/bharti airtel|airtel/i, 'Airtel'],
  [/reliance jio|\bjio\b/i, 'Jio'],
  [/vodafone|\bvi\b|idea cellular/i, 'Vi'],
  [/act fibernet|atria convergence/i, 'ACT Fibernet'],
  [/tata play|tata sky/i, 'Tata Play'],
  [/bescom/i, 'BESCOM'],
  [/tata power/i, 'Tata Power'],
  [/adani electricity/i, 'Adani Electricity'],
  [/msedcl|mahadiscom/i, 'MSEDCL'],
  [/irctc/i, 'IRCTC'],
  [/makemytrip|make my trip/i, 'MakeMyTrip'],
  [/goibibo|ibibo/i, 'Goibibo'],
  [/indigo|interglobe/i, 'IndiGo'],
  [/air india/i, 'Air India'],
  [/\boyo\b|oravel/i, 'OYO'],
  [/zerodha/i, 'Zerodha'],
  [/groww|nextbillion/i, 'Groww'],
  [/indian clearing|iccl|bse ltd|nse clearing/i, 'Mutual fund / SIP'],
  [/\blic\b|life insurance corp/i, 'LIC'],
  [/bajaj fin/i, 'Bajaj Finance'],
  [/nobroker/i, 'NoBroker'],
  [/apollo pharm|apollo/i, 'Apollo'],
  [/pharmeasy/i, 'PharmEasy'],
  [/tata 1mg|\b1mg\b/i, 'Tata 1mg'],
  [/practo/i, 'Practo'],
  [/hpcl|hindustan petroleum/i, 'HPCL'],
  [/bpcl|bharat petroleum/i, 'BPCL'],
  [/iocl|indian oil/i, 'Indian Oil'],
  [/shell/i, 'Shell'],
  [/starbucks|tata starbucks/i, 'Starbucks'],
  [/mcdonald|hardcastle|westlife/i, "McDonald's"],
  [/domino|jubilant foodworks/i, "Domino's"],
  [/\bkfc\b|devyani/i, 'KFC'],
  [/cult\.?fit|curefit/i, 'cult.fit'],
];

/** Suggested starter-category name for a payee or narration. */
const CATEGORY_RULES: [RegExp, string][] = [
  [/salary|\bsal\b|payroll|wages/i, 'Salary'],
  [/interest|int\.?\s?pd|int\.?\s?cr|\bsb int/i, 'Interest'],
  [/cashback|cash back/i, 'Cashback'],
  [/refund|reversal|\brev\b|chargeback/i, 'Refund'],
  [/swiggy|zomato|starbucks|mcdonald|domino|kfc|restaurant|cafe|hotel|dhaba|food|eatery|bakery|chai|pizza|biryani/i, 'Food & Dining'],
  [/blinkit|zepto|bigbasket|instamart|dmart|grocery|kirana|supermarket|more retail|reliance fresh|nature'?s basket|milk|dairy/i, 'Groceries'],
  [/hpcl|bpcl|indian oil|shell|petrol|fuel|filling station/i, 'Fuel'],
  [/uber|\bola\b|rapido|metro|namma|bmtc|auto|cab|fastag|parking/i, 'Metro/Auto/Cab'],
  [/bescom|tata power|adani electricity|msedcl|electricity|power|kseb|tneb|bses/i, 'Electricity'],
  [/airtel|\bjio\b|\bvi\b|vodafone|act fibernet|broadband|recharge|postpaid|prepaid|hathway/i, 'Mobile/Internet'],
  [/tata play|dish ?tv|d2h|sun direct|\bdth\b/i, 'DTH'],
  [/\brent\b|nobroker|housing\.com|landlord/i, 'Rent'],
  [/\bemi\b|loan|bajaj fin|home credit|nach.*fin/i, 'EMI/Loans'],
  [/netflix|spotify|prime|hotstar|youtube|apple|google play|subscription|jiocinema/i, 'Subscriptions'],
  [/bookmyshow|pvr|inox|cinema|movie|steam|playstation/i, 'Entertainment'],
  [/irctc|makemytrip|goibibo|indigo|air india|vistara|cleartrip|yatra|oyo|airbnb|redbus|flight|railway/i, 'Travel'],
  [/apollo|pharm|1mg|practo|hospital|clinic|medical|diagnostic|lab\b|dental/i, 'Health'],
  [/zerodha|groww|sip|mutual fund|iccl|nse|bse|smallcase|kuvera|ppf|nps/i, 'Investments'],
  [/\blic\b|insurance|policy/i, 'Bills & Utilities'],
  [/amazon|flipkart|myntra|nykaa|ajio|meesho|decathlon|ikea|croma|reliance digital|mall|store|shop/i, 'Shopping'],
  [/school|college|university|course|udemy|coursera|byju|unacademy|tuition|fees/i, 'Education'],
  [/salon|spa|parlour|barber|urban company|cult\.?fit|gym/i, 'Personal Care'],
  [/donation|temple|charity|gift/i, 'Gifts & Donations'],
];

const CARD_PAYMENT = /credit card|cc payment|card payment|cc bill|card bill|autopay.*card|billdesk.*card|bbps.*card|cred club|\bcred\b|payment received|payment - thank|thank you for (your )?payment|bbps payment received/i;
const ATM = /\batm\b|atm-wdl|atw-|nwd-|nfs\/cash|cash wdl|cash withdrawal|cardless cash/i;
const CHARGES = /charges?|chrgs|\bgst\b|annual fee|amc|sms alert|debit card fee|penalty|min bal|late fee|finance charge/i;

function titleCase(s: string): string {
  return s.toLowerCase().replace(/\b([a-z])/g, (m) => m.toUpperCase()).replace(/\b(Upi|Neft|Imps|Atm|Emi|Lic|Llp)\b/g, (m) => m.toUpperCase());
}

/** Clean a raw counterparty name: brand mapping, drop "Pvt Ltd", title case. */
export function cleanPayee(raw: string): string {
  const brand = BRANDS.find(([re]) => re.test(raw));
  if (brand) return brand[1];
  const cleaned = raw
    .replace(/\b(private|pvt|limited|ltd|llp|india|p ltd|pvt ltd|co|inc)\b\.?/gi, ' ')
    .replace(/[^a-z0-9&'. ]/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return titleCase(cleaned || raw.trim());
}

const isName = (t: string) => {
  const s = t.trim();
  return (
    s.length >= 3 &&
    /[a-z]/i.test(s) &&
    !/@/.test(s) &&
    !STOP.has(s.toLowerCase()) &&
    !BANK_CODE.test(s) &&
    !BANKS.test(s) &&
    !/^[a-z]{0,4}\d{5,}$/i.test(s) && // references like N245260123456
    !/^x+\d+$/i.test(s) && // masked card numbers
    !/^\d/.test(s) &&
    // Channel prefixes ("NEFT CR", "ACH D") and UPI remarks ("Payment for order") aren't names.
    !/^(neft|imps|rtgs|ach|nach|ecs|upi|mmt|bil|onl|trf|pos)\b/i.test(s) &&
    !/^(payment|paid|pay|sent|collect|received|transfer)\b/i.test(s)
  );
};

/**
 * Understand a statement narration from Axis, BoB, HDFC, ICICI or SBI:
 *   UPI/P2M/424412345678/SWIGGY LIMITED/swiggy@icici/Payment…     (Axis)
 *   UPI-SWIGGY LIMITED-swiggy@icici-ICIC0DC0099-424412345678-Pay   (HDFC)
 *   TO TRANSFER-UPI/DR/424412345678/SWIGGY L/ICIC/swiggy@icici/…   (SBI)
 *   UPI/424412345678/Payment for order/swiggy@icici/ICICI Bank     (ICICI)
 *   NEFT/N245260123456/ACME TECHNOLOGIES PVT LTD/SALARY SEP
 *   POS 512345XXXXXX1234 AMAZON PAY INDIA
 */
export function parseNarration(text: string): Narration {
  const raw = text.replace(/\s+/g, ' ').trim();
  const lower = raw.toLowerCase();
  const tokens = raw.split(/[/|\\]|(?<=\S)-(?=\S)|\s-\s|:/).map((t) => t.trim()).filter(Boolean);
  const upiId = /[a-z0-9._-]+@[a-z]{2,}/i.exec(raw)?.[0] ?? null;

  let channel: Channel = 'OTHER';
  if (CARD_PAYMENT.test(raw)) channel = 'CARD_PAYMENT';
  else if (/\bupi\b/i.test(raw) || upiId) channel = 'UPI';
  else if (ATM.test(raw)) channel = 'ATM';
  else if (/\bneft\b/i.test(raw)) channel = 'NEFT';
  else if (/\bimps\b|mmt\/imps/i.test(raw)) channel = 'IMPS';
  else if (/\brtgs\b/i.test(raw)) channel = 'RTGS';
  else if (/\b(nach|ach|ecs)\b/i.test(raw)) channel = 'NACH';
  else if (/^pos\b|\bpos\s|ecom|card txn|\bvps\b|\bvin\b/i.test(raw)) channel = 'POS';
  else if (/interest|int\.?\s?pd|int\.?\s?cr/i.test(raw)) channel = 'INTEREST';
  else if (/refund|reversal|\brev\b/i.test(raw)) channel = 'REFUND';
  else if (CHARGES.test(raw)) channel = 'CHARGES';

  let payee: string | null = null;
  let note: string | null = null;
  const brand = BRANDS.find(([re]) => re.test(raw))?.[1];
  const fixed: Partial<Record<Channel, string>> = {
    ATM: 'ATM withdrawal',
    INTEREST: 'Interest',
    CHARGES: 'Bank charges',
    CARD_PAYMENT: 'Credit card payment',
  };
  if (fixed[channel]) return { channel, payee: fixed[channel]!, upiId, note: null };
  if (channel === 'UPI') {
    const at = tokens.findIndex((t) => t.includes('@'));
    // The name usually sits right before the UPI id; otherwise take the longest name-like token.
    const before = at > 0 ? tokens.slice(0, at).reverse().find(isName) : undefined;
    const names = tokens.filter(isName);
    payee = brand ?? before ?? names.sort((a, b) => b.length - a.length)[0] ?? (upiId ? upiId.split('@')[0].replace(/[._-]?\d+$/, '') : null);
    const after = at >= 0 ? tokens.slice(at + 1).filter((t) => isName(t) && !BANKS.test(t.replace(/\s*bank$/i, ''))) : [];
    note = after.length ? after.join(' ') : null;
  } else if (channel === 'POS') {
    const m = /(?:pos|ecom|vps|vin)[\s/]*(?:[x\d*]{6,}\s*)?(.+)$/i.exec(raw);
    payee = brand ?? (m ? m[1].split('/')[0] : (tokens.find(isName) ?? null));
  } else {
    const names = tokens.filter(isName);
    payee = brand ?? names[0] ?? null;
    note = names.length > 1 ? names.slice(1).join(' ') : null;
  }
  return {
    channel,
    payee: payee ? cleanPayee(payee) : lower ? cleanPayee(raw.slice(0, 40)) : null,
    upiId,
    note,
  };
}

/** Suggested starter-category name from payee/narration keywords, or null. */
export function suggestCategoryName(narration: string, payee: string | null, direction: 'in' | 'out'): string | null {
  const text = `${payee ?? ''} ${narration}`;
  for (const [re, name] of CATEGORY_RULES) {
    if (!re.test(text)) continue;
    const incomeOnly = ['Salary', 'Interest', 'Cashback', 'Refund'].includes(name);
    if (incomeOnly === (direction === 'in')) return name;
  }
  return null;
}
