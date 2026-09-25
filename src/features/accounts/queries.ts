import { asc, getTableColumns, isNull, sql } from 'drizzle-orm';

import { accounts, transactions } from '@/db/schema';
import type { DB } from '@/db/types';

/**
 * Per-account balance computed in SQL. Mirrors `balanceEffect` in ./balance.ts:
 * money leaves `accountId` (expense, transfer out) and arrives at `toAccountId`
 * (transfer in); income arrives at `accountId`.
 *
 * The outer column is written table-qualified on purpose: Drizzle renders `${accounts.id}`
 * as a bare "id" when selecting from one table, which inside the subquery would bind to t.id.
 */
const accountId = sql.raw('"accounts"."id"');
const balanceSql = sql<number>`${accounts.openingBalance} + coalesce((
  select sum(case
    when t.to_account_id = ${accountId} then t.amount
    when t.type = 'income' then t.amount
    else -t.amount
  end)
  from ${transactions} t
  where t.deleted_at is null
    and (t.account_id = ${accountId} or t.to_account_id = ${accountId})
), 0)`;

/** Accounts with live balances, in the user's order. Pass `includeArchived` for Settings. */
export function accountsWithBalance(db: DB, { includeArchived = false } = {}) {
  const query = db
    .select({ ...getTableColumns(accounts), balance: balanceSql.mapWith(Number).as('balance') })
    .from(accounts)
    .orderBy(asc(accounts.sortOrder), asc(accounts.createdAt));
  return includeArchived ? query : query.where(isNull(accounts.archivedAt));
}
