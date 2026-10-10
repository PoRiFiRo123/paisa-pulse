/** Currencies people commonly spend in when travelling from India (plus INR). */
export const CURRENCIES: { code: string; name: string; symbol: string; flag: string }[] = [
  { code: 'INR', name: 'Indian Rupee', symbol: '₹', flag: '🇮🇳' },
  { code: 'USD', name: 'US Dollar', symbol: '$', flag: '🇺🇸' },
  { code: 'EUR', name: 'Euro', symbol: '€', flag: '🇪🇺' },
  { code: 'GBP', name: 'British Pound', symbol: '£', flag: '🇬🇧' },
  { code: 'AED', name: 'UAE Dirham', symbol: 'AED', flag: '🇦🇪' },
  { code: 'SGD', name: 'Singapore Dollar', symbol: 'S$', flag: '🇸🇬' },
  { code: 'THB', name: 'Thai Baht', symbol: '฿', flag: '🇹🇭' },
  { code: 'MYR', name: 'Malaysian Ringgit', symbol: 'RM', flag: '🇲🇾' },
  { code: 'IDR', name: 'Indonesian Rupiah', symbol: 'Rp', flag: '🇮🇩' },
  { code: 'VND', name: 'Vietnamese Dong', symbol: '₫', flag: '🇻🇳' },
  { code: 'JPY', name: 'Japanese Yen', symbol: '¥', flag: '🇯🇵' },
  { code: 'KRW', name: 'South Korean Won', symbol: '₩', flag: '🇰🇷' },
  { code: 'CNY', name: 'Chinese Yuan', symbol: 'CN¥', flag: '🇨🇳' },
  { code: 'HKD', name: 'Hong Kong Dollar', symbol: 'HK$', flag: '🇭🇰' },
  { code: 'AUD', name: 'Australian Dollar', symbol: 'A$', flag: '🇦🇺' },
  { code: 'NZD', name: 'New Zealand Dollar', symbol: 'NZ$', flag: '🇳🇿' },
  { code: 'CAD', name: 'Canadian Dollar', symbol: 'C$', flag: '🇨🇦' },
  { code: 'CHF', name: 'Swiss Franc', symbol: 'CHF', flag: '🇨🇭' },
  { code: 'SAR', name: 'Saudi Riyal', symbol: 'SAR', flag: '🇸🇦' },
  { code: 'QAR', name: 'Qatari Riyal', symbol: 'QAR', flag: '🇶🇦' },
  { code: 'KWD', name: 'Kuwaiti Dinar', symbol: 'KWD', flag: '🇰🇼' },
  { code: 'OMR', name: 'Omani Rial', symbol: 'OMR', flag: '🇴🇲' },
  { code: 'BHD', name: 'Bahraini Dinar', symbol: 'BHD', flag: '🇧🇭' },
  { code: 'LKR', name: 'Sri Lankan Rupee', symbol: 'Rs', flag: '🇱🇰' },
  { code: 'NPR', name: 'Nepalese Rupee', symbol: 'रू', flag: '🇳🇵' },
  { code: 'BDT', name: 'Bangladeshi Taka', symbol: '৳', flag: '🇧🇩' },
  { code: 'MVR', name: 'Maldivian Rufiyaa', symbol: 'Rf', flag: '🇲🇻' },
  { code: 'TRY', name: 'Turkish Lira', symbol: '₺', flag: '🇹🇷' },
  { code: 'ZAR', name: 'South African Rand', symbol: 'R', flag: '🇿🇦' },
  { code: 'EGP', name: 'Egyptian Pound', symbol: 'E£', flag: '🇪🇬' },
  { code: 'PHP', name: 'Philippine Peso', symbol: '₱', flag: '🇵🇭' },
];

export const currencyInfo = (code: string) => CURRENCIES.find((c) => c.code === code) ?? { code, name: code, symbol: code, flag: '🏳️' };

/** Decimal places of a currency's minor unit (ISO 4217). */
export function minorDigits(code: string): number {
  if (['JPY', 'KRW', 'VND', 'CLP', 'ISK', 'UGX'].includes(code)) return 0;
  if (['KWD', 'BHD', 'OMR', 'JOD', 'TND', 'LYD', 'IQD'].includes(code)) return 3;
  return 2;
}

/**
 * The keypad works in "paise-like" hundredths. Turn its value into the currency's minor
 * units: ¥1,500 → 1500, $12.34 → 1234, KWD 3.5 → 3500.
 */
export function hundredthsToMinor(hundredths: number, code: string): number {
  return Math.round((hundredths * 10 ** minorDigits(code)) / 100);
}

export function minorToHundredths(minor: number, code: string): number {
  return Math.round((minor * 100) / 10 ** minorDigits(code));
}

/** INR paise for an amount in a foreign currency, given rupees per one unit of it. */
export function convertToPaise(minor: number, code: string, inrPerUnit: number): number {
  return Math.round((minor / 10 ** minorDigits(code)) * inrPerUnit * 100);
}

/** "$12.34", "¥1,500", "AED 45.50". */
export function formatForeign(minor: number, code: string): string {
  const digits = minorDigits(code);
  const value = minor / 10 ** digits;
  const info = currencyInfo(code);
  const body = value.toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits });
  return /^[A-Z]{2,}$/.test(info.symbol) ? `${info.symbol} ${body}` : `${info.symbol}${body}`;
}

/** "₹83.21" style rate label, trimmed to 2–4 significant decimals for small units (₹0.0052 per IDR). */
export function formatRate(inrPerUnit: number): string {
  const decimals = inrPerUnit >= 10 ? 2 : inrPerUnit >= 1 ? 3 : 4;
  return `₹${inrPerUnit.toLocaleString('en-IN', { maximumFractionDigits: decimals, minimumFractionDigits: Math.min(2, decimals) })}`;
}
