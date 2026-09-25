import { sql } from 'drizzle-orm';
import {
  type AnySQLiteColumn,
  check,
  index,
  integer,
  sqliteTable,
  text,
} from 'drizzle-orm/sqlite-core';

// Conventions
// - IDs are UUIDv7 strings (see src/lib/ids.ts).
// - Money is integer paise. Never store rupees or floats.
// - Timestamps are epoch milliseconds.

export const ACCOUNT_TYPES = ['bank', 'card', 'cash', 'wallet'] as const;
export type AccountType = (typeof ACCOUNT_TYPES)[number];

export const CATEGORY_KINDS = ['expense', 'income'] as const;
export type CategoryKind = (typeof CATEGORY_KINDS)[number];

export const TRANSACTION_TYPES = ['expense', 'income', 'transfer'] as const;
export type TransactionType = (typeof TRANSACTION_TYPES)[number];

// Auto-capture (later phases) writes into the same table with a different source.
export const TRANSACTION_SOURCES = ['manual', 'notification', 'sms', 'shortcut', 'import'] as const;
export type TransactionSource = (typeof TRANSACTION_SOURCES)[number];

export const accounts = sqliteTable('accounts', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  type: text('type', { enum: ACCOUNT_TYPES }).notNull(),
  institution: text('institution'),
  last4: text('last4'),
  // Signed. A credit card you owe ₹5,000 on starts at -500000.
  openingBalance: integer('opening_balance').notNull().default(0),
  currency: text('currency').notNull().default('INR'),
  creditLimit: integer('credit_limit'),
  statementDay: integer('statement_day'),
  dueDay: integer('due_day'),
  color: text('color').notNull(),
  icon: text('icon').notNull(),
  sortOrder: integer('sort_order').notNull().default(0),
  // Hide from net worth and home totals (e.g. a wallet you don't care about).
  excludeFromTotals: integer('exclude_from_totals', { mode: 'boolean' }).notNull().default(false),
  archivedAt: integer('archived_at'),
  createdAt: integer('created_at').notNull(),
  updatedAt: integer('updated_at').notNull(),
});

export const categories = sqliteTable(
  'categories',
  {
    id: text('id').primaryKey(),
    parentId: text('parent_id').references((): AnySQLiteColumn => categories.id),
    kind: text('kind', { enum: CATEGORY_KINDS }).notNull(),
    name: text('name').notNull(),
    icon: text('icon').notNull(),
    color: text('color').notNull(),
    sortOrder: integer('sort_order').notNull().default(0),
    archivedAt: integer('archived_at'),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at').notNull(),
  },
  (t) => [index('categories_parent_idx').on(t.parentId)],
);

export const transactions = sqliteTable(
  'transactions',
  {
    id: text('id').primaryKey(),
    type: text('type', { enum: TRANSACTION_TYPES }).notNull(),
    // Paise, always positive. The type decides the direction.
    amount: integer('amount').notNull(),
    accountId: text('account_id')
      .notNull()
      .references(() => accounts.id),
    toAccountId: text('to_account_id').references(() => accounts.id),
    // Null means "Uncategorised". Always null for transfers.
    categoryId: text('category_id').references(() => categories.id),
    payee: text('payee'),
    note: text('note'),
    occurredAt: integer('occurred_at').notNull(),
    source: text('source', { enum: TRANSACTION_SOURCES }).notNull().default('manual'),
    deletedAt: integer('deleted_at'),
    createdAt: integer('created_at').notNull(),
    updatedAt: integer('updated_at').notNull(),
  },
  (t) => [
    index('transactions_occurred_at_idx').on(t.occurredAt),
    index('transactions_account_occurred_at_idx').on(t.accountId, t.occurredAt),
    index('transactions_to_account_idx').on(t.toAccountId),
    index('transactions_category_idx').on(t.categoryId),
    index('transactions_type_occurred_at_idx').on(t.type, t.occurredAt),
    index('transactions_payee_idx').on(t.payee),
    check('transactions_amount_positive', sql`${t.amount} > 0`),
    check(
      'transactions_transfer_shape',
      sql`(${t.type} = 'transfer' AND ${t.toAccountId} IS NOT NULL AND ${t.toAccountId} <> ${t.accountId} AND ${t.categoryId} IS NULL)
        OR (${t.type} <> 'transfer' AND ${t.toAccountId} IS NULL)`,
    ),
  ],
);

export const settings = sqliteTable('settings', {
  key: text('key').primaryKey(),
  // JSON-encoded value.
  value: text('value').notNull(),
});

export type Account = typeof accounts.$inferSelect;
export type NewAccount = typeof accounts.$inferInsert;
export type Category = typeof categories.$inferSelect;
export type NewCategory = typeof categories.$inferInsert;
export type Transaction = typeof transactions.$inferSelect;
export type NewTransaction = typeof transactions.$inferInsert;
export type Setting = typeof settings.$inferSelect;
