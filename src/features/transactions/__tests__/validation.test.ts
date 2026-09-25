import { validateTransaction, type TransactionInput } from '../validation';

const NOW = Date.UTC(2026, 8, 25);
const base: TransactionInput = { type: 'expense', amount: 25000, accountId: 'axis' };
const codes = (input: TransactionInput) => validateTransaction(input, NOW).map((e) => e.code);

describe('validateTransaction', () => {
  it('accepts a minimal expense, income and transfer', () => {
    expect(codes(base)).toEqual([]);
    expect(codes({ ...base, type: 'income', categoryId: 'salary' })).toEqual([]);
    expect(codes({ type: 'transfer', amount: 1, accountId: 'axis', toAccountId: 'card' })).toEqual([]);
  });

  it('requires a positive whole-paise amount', () => {
    expect(codes({ ...base, amount: 0 })).toEqual(['amount_not_positive']);
    expect(codes({ ...base, amount: -5 })).toEqual(['amount_not_positive']);
    expect(codes({ ...base, amount: 12.5 })).toEqual(['amount_not_integer']);
    expect(codes({ ...base, amount: NaN })).toEqual(['amount_not_integer']);
  });

  it('requires an account', () => {
    expect(codes({ ...base, accountId: '' })).toEqual(['account_required']);
  });

  it('requires two distinct accounts for a transfer and no category', () => {
    expect(codes({ ...base, type: 'transfer' })).toEqual(['to_account_required']);
    expect(codes({ ...base, type: 'transfer', toAccountId: 'axis' })).toEqual(['same_account_transfer']);
    expect(codes({ ...base, type: 'transfer', toAccountId: 'card', categoryId: 'food' })).toEqual([
      'category_not_allowed',
    ]);
  });

  it('rejects a destination account on expenses and income', () => {
    expect(codes({ ...base, toAccountId: 'card' })).toEqual(['to_account_not_allowed']);
  });

  it('allows dates up to one year ahead', () => {
    const oneYear = Date.UTC(2027, 8, 25);
    expect(codes({ ...base, occurredAt: oneYear })).toEqual([]);
    expect(codes({ ...base, occurredAt: oneYear + 1 })).toEqual(['date_too_far_in_future']);
    expect(codes({ ...base, occurredAt: Date.UTC(2020, 0, 1) })).toEqual([]);
  });
});
