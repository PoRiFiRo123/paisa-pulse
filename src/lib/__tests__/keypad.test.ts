import { evaluateAmountExpression } from '@/lib/money';

import { applyKey } from '@/lib/keypad';

const type = (keys: string) => [...keys].reduce(applyKey, '');

describe('applyKey', () => {
  it('builds numbers and expressions', () => {
    expect(type('120+45')).toBe('120+45');
    expect(evaluateAmountExpression(type('120+45'))).toBe(16500);
  });

  it('prefixes a bare decimal point with zero and allows one point per number', () => {
    expect(type('.5')).toBe('0.5');
    expect(type('1.2.3')).toBe('1.23');
    expect(type('1.5+.5')).toBe('1.5+0.5');
  });

  it('limits decimals to two places', () => {
    expect(type('9.999')).toBe('9.99');
  });

  it('replaces a trailing operator and ignores a leading one', () => {
    expect(type('+')).toBe('');
    expect(type('12+−')).toBe('12−');
    expect(type('12×÷3')).toBe('12÷3');
  });

  it('drops leading zeros', () => {
    expect(type('007')).toBe('7');
    expect(type('0.07')).toBe('0.07');
  });

  it('deletes and clears', () => {
    expect(applyKey('120', '⌫')).toBe('12');
    expect(applyKey('120+4', 'C')).toBe('');
  });

  it('caps each number at nine digits', () => {
    expect(type('1234567890')).toBe('123456789');
  });
});
