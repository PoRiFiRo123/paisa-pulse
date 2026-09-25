import {
  formatINRAxis,
  CRORE,
  LAKH,
  MoneyParseError,
  evaluateAmountExpression,
  formatINR,
  formatINRCompact,
  toPaise,
  tryToPaise,
} from '../money';

describe('toPaise', () => {
  it.each([
    ['1,250.50', 125050],
    ['₹1,250.5', 125050],
    ['1250', 125000],
    ['0.01', 1],
    ['.5', 50],
    ['12.', 1200],
    ['  ₹ 12,34,567.89 ', 123456789],
    ['Rs. 99', 9900],
    ['-20', -2000],
    ['0', 0],
  ])('parses %p → %p', (input, expected) => {
    expect(toPaise(input)).toBe(expected);
  });

  it('never drifts through floating point', () => {
    expect(toPaise(0.1 + 0.2)).toBe(30);
    expect(toPaise(1.005)).toBe(tryToPaise((1.005).toFixed(2)));
    expect(toPaise('19.99')).toBe(1999);
    expect(toPaise(19.99)).toBe(1999);
  });

  it.each(['', '.', 'abc', '1.234', '1..2', '12-3', '₹'])('rejects %p', (input) => {
    expect(() => toPaise(input)).toThrow(MoneyParseError);
    expect(tryToPaise(input)).toBeNull();
  });

  it('rejects non-finite numbers', () => {
    expect(tryToPaise(NaN)).toBeNull();
    expect(tryToPaise(Infinity)).toBeNull();
  });
});

describe('formatINR', () => {
  it('matches the spec example', () => {
    expect(formatINR(125050)).toBe('₹1,250.50');
  });

  it('uses lakh and crore grouping', () => {
    expect(formatINR(10_000_000)).toBe('₹1,00,000.00');
    expect(formatINR(1_234_567_800)).toBe('₹1,23,45,678.00');
  });

  it('handles small and zero amounts', () => {
    expect(formatINR(0)).toBe('₹0.00');
    expect(formatINR(5)).toBe('₹0.05');
    expect(formatINR(99)).toBe('₹0.99');
  });

  it('supports sign, symbol and decimal options', () => {
    expect(formatINR(-125050)).toBe('-₹1,250.50');
    expect(formatINR(125050, { sign: 'always' })).toBe('+₹1,250.50');
    expect(formatINR(-125050, { sign: 'never' })).toBe('₹1,250.50');
    expect(formatINR(0, { sign: 'always' })).toBe('₹0.00');
    expect(formatINR(125000, { decimals: 'auto' })).toBe('₹1,250');
    expect(formatINR(125050, { decimals: 'auto' })).toBe('₹1,250.50');
    expect(formatINR(125050, { symbol: false })).toBe('1,250.50');
  });

  it('rejects fractional paise', () => {
    expect(() => formatINR(1.5)).toThrow(TypeError);
  });
});

describe('formatINRCompact', () => {
  it.each([
    [95_000, '₹950'],
    [1_250_050, '₹12,500'],
    [LAKH, '₹1L'],
    [125 * LAKH / 100, '₹1.25L'],
    [99_99_999 * 100, '₹99.99L'],
    [CRORE, '₹1Cr'],
    [3.4 * CRORE, '₹3.4Cr'],
    [150 * CRORE, '₹150Cr'],
    [-125 * LAKH / 100, '-₹1.25L'],
  ])('%p → %p', (paise, expected) => {
    expect(formatINRCompact(paise)).toBe(expected);
  });
});

describe('evaluateAmountExpression', () => {
  it.each([
    ['120', 12000],
    ['120+45', 16500],
    ['1,000-10.50', 98950],
    ['250×2', 50000],
    ['250*2', 50000],
    ['100+20×3', 16000],
    ['900÷3', 30000],
    ['100÷3', 3333],
    ['200÷3', 6667],
    ['10.5×3', 3150],
    ['99.99×1.5', 14999],
    ['120+', 12000],
    ['12.5−2.5', 1000],
    ['50-80', -3000],
  ])('%p → %p', (expr, expected) => {
    expect(evaluateAmountExpression(expr)).toBe(expected);
  });

  it.each(['', '+', '+5', '5++5', '1.234+1', '10÷0', 'abc'])('returns null for %p', (expr) => {
    expect(evaluateAmountExpression(expr)).toBeNull();
  });
});

describe('formatINRAxis', () => {
  it.each([
    [0, '₹0'],
    [50_000, '₹500'],
    [20_00_000, '₹20K'],
    [1_50_000_00, '₹1.5L'],
    [2 * CRORE, '₹2Cr'],
  ])('%p → %p', (paise, expected) => expect(formatINRAxis(paise)).toBe(expected));
});
