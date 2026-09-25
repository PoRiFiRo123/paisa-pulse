import type { Account, Transaction } from '@/db/schema';

type BalanceTxn = Pick<Transaction, 'type' | 'amount' | 'accountId' | 'toAccountId' | 'deletedAt'>;

/**
 * How one transaction changes one account's balance, in paise.
 * Balances are signed: a credit card you owe money on is negative, so spending on it
 * pushes it further below zero and a bill payment (a transfer into it) brings it back up.
 */
export function balanceEffect(txn: BalanceTxn, accountId: string): number {
  if (txn.deletedAt != null) return 0;
  switch (txn.type) {
    case 'expense':
      return txn.accountId === accountId ? -txn.amount : 0;
    case 'income':
      return txn.accountId === accountId ? txn.amount : 0;
    case 'transfer':
      if (txn.accountId === accountId) return -txn.amount;
      if (txn.toAccountId === accountId) return txn.amount;
      return 0;
  }
}

/** Balance = opening balance + effect of every live transaction. Never stored. */
export function computeBalance(account: Pick<Account, 'id' | 'openingBalance'>, txns: readonly BalanceTxn[]): number {
  return txns.reduce((sum, t) => sum + balanceEffect(t, account.id), account.openingBalance);
}

/** Sum of balances for accounts that count towards totals (not archived, not excluded). */
export function computeNetWorth(
  accounts: readonly (Pick<Account, 'archivedAt' | 'excludeFromTotals'> & { balance: number })[],
): number {
  return accounts.reduce((sum, a) => (a.archivedAt == null && !a.excludeFromTotals ? sum + a.balance : sum), 0);
}
