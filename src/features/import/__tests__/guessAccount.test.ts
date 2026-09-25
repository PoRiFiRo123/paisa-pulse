import type { Account } from '@/db/schema';

import { guessAccount } from '../guessAccount';

const acc = (id: string, name: string, type: Account['type'], institution: string | null = null) =>
  ({ id, name, type, institution, archivedAt: null }) as Account;

it('matches the statement to the right bank or card account', () => {
  const list = [acc('bob', 'Bank of Baroda', 'bank'), acc('axis', 'Salary account', 'bank', 'Axis Bank'), acc('card', 'Axis MyZone', 'card'), acc('cash', 'Cash', 'cash')];
  expect(guessAccount(list, { id: 'axis-bank', name: 'Axis Bank', kind: 'bank' })?.id).toBe('axis');
  expect(guessAccount(list, { id: 'bob', name: 'Bank of Baroda', kind: 'bank' })?.id).toBe('bob');
  expect(guessAccount(list, { id: 'axis-card', name: 'Axis card', kind: 'card' })?.id).toBe('card');
  expect(guessAccount(list, { id: 'hdfc', name: 'HDFC', kind: 'bank' })?.id).toBe('bob');
  expect(guessAccount(list, null)?.id).toBe('bob');
});
