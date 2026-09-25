import type { Account } from '@/db/schema';

import type { StatementTemplate } from './parse';

const BANK_WORDS: Record<string, RegExp> = {
  'axis-bank': /axis/i,
  'axis-card': /axis|myzone|flipkart|ace|neo|magnus/i,
  bob: /baroda|\bbob\b/i,
  hdfc: /hdfc/i,
  'hdfc-card': /hdfc|regalia|millennia|swiggy|tata neu|infinia/i,
  icici: /icici/i,
  'icici-card': /icici|amazon pay|coral|sapphiro/i,
  sbi: /sbi|state bank/i,
  'sbi-card': /sbi|simplyclick|cashback|elite/i,
};

/** The account a statement most likely belongs to: same kind and bank name, else same kind. */
export function guessAccount(accounts: Account[], template: StatementTemplate | null): Account | undefined {
  const active = accounts.filter((a) => a.archivedAt === null);
  if (!template) return active.find((a) => a.type === 'bank') ?? active[0];
  const word = BANK_WORDS[template.id];
  const sameKind = active.filter((a) => (template.kind === 'card' ? a.type === 'card' : a.type !== 'card'));
  return sameKind.find((a) => word && word.test(`${a.name} ${a.institution ?? ''}`)) ?? sameKind[0] ?? active[0];
}
