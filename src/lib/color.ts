// OKLab/OKLCH helpers for chart colours (https://bottosson.github.io/posts/oklab/).

type RGB = [number, number, number];

const toLinear = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const toGamma = (c: number) => (c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055);

function hexToRgb(hex: string): RGB {
  const n = parseInt(hex.replace('#', ''), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => c / 255) as RGB;
}

function rgbToHex(rgb: RGB): string {
  return `#${rgb.map((c) => Math.round(Math.min(Math.max(c, 0), 1) * 255).toString(16).padStart(2, '0')).join('').toUpperCase()}`;
}

export function hexToOklch(hex: string): [number, number, number] {
  const [r, g, b] = hexToRgb(hex).map(toLinear);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return [L, Math.hypot(A, B), Math.atan2(B, A)];
}

export function oklchToHex(L: number, C: number, h: number): string {
  const A = C * Math.cos(h);
  const B = C * Math.sin(h);
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3;
  const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3;
  const s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3;
  const rgb: RGB = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
  return rgbToHex(rgb.map(toGamma) as RGB);
}

/** Lightness band a chart mark must sit in to read against the surface (validated in dataviz checks). */
export const CHART_BAND = { light: [0.45, 0.75], dark: [0.5, 0.65] } as const;

/**
 * A category colour adjusted for chart marks: same hue and chroma, lightness clamped
 * into the mode's band (e.g. Bills yellow gets darker on a white card).
 */
export function chartColor(hex: string, dark: boolean): string {
  const [L, C, h] = hexToOklch(hex);
  const [lo, hi] = CHART_BAND[dark ? 'dark' : 'light'];
  const clamped = Math.min(Math.max(L, lo), hi);
  if (clamped === L) return hex.toUpperCase();
  // Reduce chroma slightly if needed to stay inside sRGB after the lightness change.
  for (let c = C; c >= 0; c -= 0.01) {
    const out = oklchToHex(clamped, c, h);
    const [L2] = hexToOklch(out);
    if (Math.abs(L2 - clamped) < 0.02) return out;
  }
  return oklchToHex(clamped, 0, h);
}
