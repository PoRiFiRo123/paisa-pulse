import type { CaptureContext } from '../drafts';
import { findAmount, findDate, parseSpokenTransactions, splitPhrases, wordsToDigits } from '../voice';

const NOW = new Date(2026, 9, 10, 15, 30).getTime(); // Saturday

const ctx: CaptureContext = {
  now: NOW,
  defaultAccountId: 'axis',
  accounts: [
    { id: 'axis', name: 'Axis Bank', type: 'bank', institution: 'Axis Bank', last4: '5678' },
    { id: 'bob', name: 'Bank of Baroda', type: 'bank', institution: 'Bank of Baroda', last4: null },
    { id: 'card', name: 'Axis MyZone', type: 'card', institution: 'Axis Bank', last4: '3307' },
    { id: 'cash', name: 'Cash', type: 'cash', institution: null, last4: null },
  ],
  categories: [
    { id: 'food', name: 'Food & Dining', kind: 'expense', parentId: null },
    { id: 'groceries', name: 'Groceries', kind: 'expense', parentId: null },
    { id: 'transport', name: 'Transport', kind: 'expense', parentId: null },
    { id: 'cab', name: 'Metro/Auto/Cab', kind: 'expense', parentId: 'transport' },
    { id: 'rent', name: 'Rent', kind: 'expense', parentId: null },
    { id: 'salary', name: 'Salary', kind: 'income', parentId: null },
  ],
  learned: new Map([['rahul', 'rent']]),
};

describe('number words', () => {
  it('turns spoken numbers into digits', () => {
    expect(wordsToDigits('two hundred and fifty for lunch')).toBe('250 for lunch');
    expect(wordsToDigits('one fifty auto')).toBe('150 auto');
    expect(wordsToDigits('fifteen hundred groceries')).toBe('1500 groceries');
    expect(wordsToDigits('two lakh fifty thousand')).toBe('250000');
    expect(wordsToDigits('a thousand rupees')).toBe('1000 rupees');
    expect(wordsToDigits('a coffee')).toBe('a coffee');
    expect(wordsToDigits('bread and butter')).toBe('bread and butter');
  });

  it('finds amounts with Indian shorthands', () => {
    expect(findAmount('₹1,500 dinner')?.paise).toBe(1500_00);
    expect(findAmount('spent 1.5k on shoes')?.paise).toBe(1500_00);
    expect(findAmount('rent 18 thousand')?.paise).toBe(18000_00);
    expect(findAmount('salary 1.2 lakh')?.paise).toBe(120000_00);
    expect(findAmount('99.50 rupees')?.paise).toBe(99_50);
    expect(findAmount('lunch')).toBeNull();
  });
});

describe('phrases and dates', () => {
  it('splits on commas and on "and" only between amounts', () => {
    expect(splitPhrases('250 lunch, 80 auto and 40 chai')).toEqual(['250 lunch', '80 auto', '40 chai']);
    expect(splitPhrases('60 bread and butter')).toEqual(['60 bread and butter']);
    expect(splitPhrases('1,500 groceries then 200 petrol')).toEqual(['1,500 groceries', '200 petrol']);
  });

  it('understands relative dates', () => {
    expect(new Date(findDate('yesterday', NOW)!.at).getDate()).toBe(9);
    expect(new Date(findDate('day before yesterday', NOW)!.at).getDate()).toBe(8);
    expect(new Date(findDate('on monday', NOW)!.at).getDate()).toBe(5);
    expect(new Date(findDate('last saturday', NOW)!.at).getDate()).toBe(3);
    expect(new Date(findDate('3 days ago', NOW)!.at).getDate()).toBe(7);
    expect(new Date(findDate('on the 12th', NOW)!.at)).toEqual(new Date(2026, 8, 12, 12));
    expect(new Date(findDate('last night', NOW)!.at).getHours()).toBe(21);
  });
});

describe('parseSpokenTransactions', () => {
  it('logs several expenses from one sentence', () => {
    const { drafts } = parseSpokenTransactions('250 lunch, 80 auto and 40 chai', ctx);
    expect(drafts.map((d) => [d.amount, d.note, d.categoryId, d.type])).toEqual([
      [250_00, 'Lunch', 'food', 'expense'],
      [80_00, 'Auto', 'cab', 'expense'],
      [40_00, 'Chai', 'food', 'expense'],
    ]);
    expect(drafts.every((d) => d.accountId === 'axis' && d.occurredAt === NOW)).toBe(true);
  });

  it('picks up payees, brands, accounts and dates', () => {
    const { drafts } = parseSpokenTransactions('Yesterday I paid 420 on swiggy using my card, and two thousand to Rahul in cash', ctx);
    expect(drafts).toHaveLength(2);
    expect(drafts[0]).toMatchObject({ amount: 420_00, payee: 'Swiggy', accountId: 'card', categoryId: 'food' });
    expect(new Date(drafts[0].occurredAt).getDate()).toBe(9);
    expect(drafts[1]).toMatchObject({ amount: 2000_00, payee: 'Rahul', accountId: 'cash', categoryId: 'rent' });
    expect(new Date(drafts[1].occurredAt).getDate()).toBe(9);
  });

  it('recognises income and transfers', () => {
    const income = parseSpokenTransactions('got salary 90k from acme in axis', ctx).drafts[0];
    expect(income).toMatchObject({ type: 'income', amount: 90000_00, categoryId: 'salary', accountId: 'axis', payee: 'Acme' });

    const move = parseSpokenTransactions('moved 5000 from axis to baroda', ctx).drafts[0];
    expect(move).toMatchObject({ type: 'transfer', accountId: 'axis', toAccountId: 'bob', categoryId: null });

    const bill = parseSpokenTransactions('paid the credit card bill 8360', ctx).drafts[0];
    expect(bill).toMatchObject({ type: 'transfer', accountId: 'axis', toAccountId: 'card', amount: 8360_00 });
  });

  it('reports phrases without an amount', () => {
    const { drafts, skipped } = parseSpokenTransactions('coffee with Priya, 180 coffee', ctx);
    expect(drafts).toHaveLength(1);
    expect(skipped).toEqual(['coffee with Priya']);
  });
});
