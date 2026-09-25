import { maxOccurredAt } from '@/lib/dates';
import type { TransactionType } from '@/db/schema';

export type TransactionInput = {
  type: TransactionType;
  /** Paise, > 0. */
  amount: number;
  accountId: string;
  /** Required for transfers, must be empty otherwise. */
  toAccountId?: string | null;
  /** Null = Uncategorised. Must be empty for transfers. */
  categoryId?: string | null;
  payee?: string | null;
  note?: string | null;
  /** Epoch ms. Defaults to now. */
  occurredAt?: number;
};

export type TransactionErrorCode =
  | 'amount_not_positive'
  | 'amount_not_integer'
  | 'account_required'
  | 'to_account_required'
  | 'same_account_transfer'
  | 'to_account_not_allowed'
  | 'category_not_allowed'
  | 'date_too_far_in_future';

export type TransactionError = { field: keyof TransactionInput; code: TransactionErrorCode };

export class TransactionValidationError extends Error {
  constructor(public readonly errors: TransactionError[]) {
    super(`Invalid transaction: ${errors.map((e) => e.code).join(', ')}`);
    this.name = 'TransactionValidationError';
  }
}

/** SPEC §4.1 validation rules. Returns an empty list when the input is valid. */
export function validateTransaction(input: TransactionInput, now: number = Date.now()): TransactionError[] {
  const errors: TransactionError[] = [];
  if (!Number.isSafeInteger(input.amount)) errors.push({ field: 'amount', code: 'amount_not_integer' });
  else if (input.amount <= 0) errors.push({ field: 'amount', code: 'amount_not_positive' });

  if (!input.accountId) errors.push({ field: 'accountId', code: 'account_required' });

  if (input.type === 'transfer') {
    if (!input.toAccountId) errors.push({ field: 'toAccountId', code: 'to_account_required' });
    else if (input.toAccountId === input.accountId)
      errors.push({ field: 'toAccountId', code: 'same_account_transfer' });
    if (input.categoryId) errors.push({ field: 'categoryId', code: 'category_not_allowed' });
  } else if (input.toAccountId) {
    errors.push({ field: 'toAccountId', code: 'to_account_not_allowed' });
  }

  if (input.occurredAt !== undefined && input.occurredAt > maxOccurredAt(now))
    errors.push({ field: 'occurredAt', code: 'date_too_far_in_future' });

  return errors;
}

export function assertValidTransaction(input: TransactionInput, now?: number): void {
  const errors = validateTransaction(input, now);
  if (errors.length) throw new TransactionValidationError(errors);
}
