/** A merchant we recognise: display name, brand colour (for the monogram) and website (for an optional logo). */
export type Brand = { name: string; match: RegExp; color: string; domain: string | null };

const b = (match: RegExp, name: string, color: string, domain: string | null = null): Brand => ({ name, match, color, domain });

/** Known Indian merchants. Order matters: more specific patterns first (Instamart before Swiggy, Prime before Amazon). */
export const BRANDS: Brand[] = [
  b(/instamart/i, 'Swiggy Instamart', '#FC8019', 'swiggy.com'),
  b(/swiggy|bundl tech/i, 'Swiggy', '#FC8019', 'swiggy.com'),
  b(/zomato|zomato media|eternal ltd/i, 'Zomato', '#E23744', 'zomato.com'),
  b(/blinkit|grofers/i, 'Blinkit', '#F8CB46', 'blinkit.com'),
  b(/zepto|kiranakart/i, 'Zepto', '#5A1F9E', 'zeptonow.com'),
  b(/big\s?basket|supermarket grocery/i, 'BigBasket', '#84C225', 'bigbasket.com'),
  b(/dmart|avenue supermarts/i, 'DMart', '#0D8F44', 'dmart.in'),
  b(/uber/i, 'Uber', '#000000', 'uber.com'),
  b(/\bola\b|ani technologies|olacabs/i, 'Ola', '#1C1C1C', 'olacabs.com'),
  b(/rapido|roppen/i, 'Rapido', '#F9C935', 'rapido.bike'),
  b(/prime video|amazon prime/i, 'Amazon Prime', '#00A8E1', 'primevideo.com'),
  b(/amazon pay|amazon/i, 'Amazon', '#FF9900', 'amazon.in'),
  b(/flipkart/i, 'Flipkart', '#2874F0', 'flipkart.com'),
  b(/myntra/i, 'Myntra', '#FF3F6C', 'myntra.com'),
  b(/nykaa/i, 'Nykaa', '#FC2779', 'nykaa.com'),
  b(/ajio/i, 'AJIO', '#2C4152', 'ajio.com'),
  b(/meesho/i, 'Meesho', '#9F2089', 'meesho.com'),
  b(/netflix/i, 'Netflix', '#E50914', 'netflix.com'),
  b(/spotify/i, 'Spotify', '#1DB954', 'spotify.com'),
  b(/youtube/i, 'YouTube', '#FF0000', 'youtube.com'),
  b(/google\s?play|google\s?india digital|google pay|google/i, 'Google', '#4285F4', 'google.com'),
  b(/apple\s?(services|media)|itunes|apple\.com|apple/i, 'Apple', '#000000', 'apple.com'),
  b(/hotstar|jiocinema|jiohotstar|novi digital/i, 'JioHotstar', '#1F80E0', 'hotstar.com'),
  b(/bookmyshow|bigtree/i, 'BookMyShow', '#C4242B', 'bookmyshow.com'),
  b(/\bpvr\b|inox/i, 'PVR INOX', '#F7C600', 'pvrcinemas.com'),
  b(/bharti airtel|airtel/i, 'Airtel', '#E40000', 'airtel.in'),
  b(/reliance jio|\bjio\b/i, 'Jio', '#0F3CC9', 'jio.com'),
  b(/vodafone|\bvi\b|idea cellular/i, 'Vi', '#ED1C24', 'myvi.in'),
  b(/act fibernet|atria convergence/i, 'ACT Fibernet', '#EC1C24', 'actcorp.in'),
  b(/tata play|tata sky/i, 'Tata Play', '#A1006B', 'tataplay.com'),
  b(/bescom/i, 'BESCOM', '#1B5E20'),
  b(/tata power/i, 'Tata Power', '#0070C0', 'tatapower.com'),
  b(/adani electricity/i, 'Adani Electricity', '#2E3192', 'adanielectricity.com'),
  b(/msedcl|mahadiscom/i, 'MSEDCL', '#0B6E4F', 'mahadiscom.in'),
  b(/irctc/i, 'IRCTC', '#213A8F', 'irctc.co.in'),
  b(/makemytrip|make my trip/i, 'MakeMyTrip', '#EB2026', 'makemytrip.com'),
  b(/goibibo|ibibo/i, 'Goibibo', '#2276E3', 'goibibo.com'),
  b(/indigo|interglobe/i, 'IndiGo', '#001B94', 'goindigo.in'),
  b(/air india/i, 'Air India', '#DA0E29', 'airindia.com'),
  b(/\boyo\b|oravel/i, 'OYO', '#EE2E24', 'oyorooms.com'),
  b(/zerodha/i, 'Zerodha', '#387ED1', 'zerodha.com'),
  b(/groww|nextbillion/i, 'Groww', '#00D09C', 'groww.in'),
  b(/indian clearing|iccl|bse ltd|nse clearing/i, 'Mutual fund / SIP', '#5856D6'),
  b(/\blic\b|life insurance corp/i, 'LIC', '#0066B3', 'licindia.in'),
  b(/bajaj fin/i, 'Bajaj Finance', '#005BAC', 'bajajfinserv.in'),
  b(/nobroker/i, 'NoBroker', '#FD3752', 'nobroker.in'),
  b(/apollo pharm|apollo/i, 'Apollo', '#00539B', 'apollopharmacy.in'),
  b(/pharmeasy/i, 'PharmEasy', '#10847E', 'pharmeasy.in'),
  b(/tata 1mg|\b1mg\b/i, 'Tata 1mg', '#FF6F61', '1mg.com'),
  b(/practo/i, 'Practo', '#14BEF0', 'practo.com'),
  b(/hpcl|hindustan petroleum/i, 'HPCL', '#003A8C', 'hindustanpetroleum.com'),
  b(/bpcl|bharat petroleum/i, 'BPCL', '#0055A5', 'bharatpetroleum.in'),
  b(/iocl|indian oil/i, 'Indian Oil', '#F37022', 'iocl.com'),
  b(/shell/i, 'Shell', '#FFD500', 'shell.in'),
  b(/starbucks|tata starbucks/i, 'Starbucks', '#00704A', 'starbucks.in'),
  b(/mcdonald|hardcastle|westlife/i, "McDonald's", '#DA291C', 'mcdonaldsindia.com'),
  b(/domino|jubilant foodworks/i, "Domino's", '#006491', 'dominos.co.in'),
  b(/\bkfc\b|devyani/i, 'KFC', '#A3080C', 'kfc.co.in'),
  b(/cult\.?fit|curefit/i, 'cult.fit', '#1C1C1C', 'cult.fit'),
  b(/paytm|one97/i, 'Paytm', '#00BAF2', 'paytm.com'),
  b(/phonepe/i, 'PhonePe', '#5F259F', 'phonepe.com'),
  b(/\bcred\b|dreamplug/i, 'CRED', '#1C1C1C', 'cred.club'),
  b(/urban\s?company|urbanclap/i, 'Urban Company', '#000000', 'urbancompany.com'),
  b(/croma|infiniti retail/i, 'Croma', '#00B3A0', 'croma.com'),
  b(/reliance digital/i, 'Reliance Digital', '#E42529', 'reliancedigital.in'),
  b(/jiomart|reliance (fresh|smart|retail)/i, 'JioMart', '#0078AD', 'jiomart.com'),
  b(/lenskart/i, 'Lenskart', '#000042', 'lenskart.com'),
  b(/decathlon/i, 'Decathlon', '#0082C3', 'decathlon.in'),
  b(/ikea/i, 'IKEA', '#0058A3', 'ikea.com'),
];

const cache = new Map<string, Brand | null>();

/** The brand a payee or narration refers to, if we know it. Cached: rows call this on every render. */
export function matchBrand(text: string | null | undefined): Brand | null {
  if (!text) return null;
  const hit = cache.get(text);
  if (hit !== undefined) return hit;
  const brand = BRANDS.find((x) => x.match.test(text)) ?? null;
  if (cache.size > 2000) cache.clear();
  cache.set(text, brand);
  return brand;
}

/** Black or white text for a background colour (WCAG relative luminance). */
export function onColor(hex: string): '#FFFFFF' | '#000000' {
  const n = parseInt(hex.replace('#', ''), 16);
  const ch = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  const lum = 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
  // Contrast with white vs with black; pick the larger.
  return 1.05 / (lum + 0.05) >= (lum + 0.05) / 0.05 ? '#FFFFFF' : '#000000';
}

/** One letter for the monogram ("Swiggy" → "S", "1mg" → "1"). */
export function monogram(name: string): string {
  const m = name.trim().match(/[\p{L}\p{N}]/u);
  return m ? m[0].toUpperCase() : '•';
}

/** Logo URL for a brand (only fetched when the user turns on merchant logos). */
export function logoUrl(brand: Brand, size = 128): string | null {
  return brand.domain ? `https://www.google.com/s2/favicons?domain=${brand.domain}&sz=${size}` : null;
}
