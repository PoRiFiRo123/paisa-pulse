import { memo } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import type { TransactionItem } from '@/features/transactions/list';
import { useMoney } from '@/hooks/useMoney';
import { accountLabel, relativeWhen } from '@/lib/format';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { formatForeign } from '@/features/currency/currency';
import { matchBrand } from '@/features/merchants/brands';

import { CategoryIcon, transactionVisual } from './CategoryIcon';
import { BrandMark } from './MerchantIcon';

export function transactionTitle(t: TransactionItem): string {
  if (t.payee) return t.payee;
  if (t.type === 'transfer') return t.toAccountName ? `To ${t.toAccountName}` : 'Transfer';
  return t.categoryName ?? t.note ?? (t.type === 'income' ? 'Income' : 'Expense');
}

export function transactionSubtitle(t: TransactionItem, showTime = true): string {
  const parts: string[] = [];
  if (t.type === 'transfer') {
    parts.push(`${accountLabel(t.accountName, t.accountLast4)} → ${accountLabel(t.toAccountName, t.toAccountLast4)}`);
  } else {
    parts.push(t.categoryName ?? 'Uncategorised', accountLabel(t.accountName, t.accountLast4));
  }
  if (showTime) parts.push(relativeWhen(t.occurredAt));
  return parts.join(' · ');
}

/** Figma "Transaction Row": 61pt, icon, payee, "Category · Account · time", amount. */
export const TransactionRow = memo(function TransactionRow({ item, showTime = true }: { item: TransactionItem; showTime?: boolean }) {
  const { colors } = useTheme();
  const money = useMoney();
  const visual = transactionVisual(item);
  const brand = item.type === 'transfer' ? null : matchBrand(item.payee);
  const amountColor = item.type === 'income' ? colors.income : colors.label;
  return (
    <View style={[styles.row, { backgroundColor: colors.card }]}>
      {brand ? <BrandMark brand={brand} /> : <CategoryIcon icon={visual.icon} color={visual.color} />}
      <View style={styles.text}>
        <Text style={[type.body, { color: colors.label }]} numberOfLines={1}>
          {transactionTitle(item)}
        </Text>
        <Text style={[type.footnote, { color: colors.secondary }]} numberOfLines={1}>
          {transactionSubtitle(item, showTime)}
        </Text>
      </View>
      {item.currency && item.originalAmount ? (
        <View style={styles.amounts}>
          <Text style={[type.bodyAmount, { color: amountColor }]}>{money.signed(item.amount, item.type)}</Text>
          <Text style={[type.caption, { color: colors.secondary }]}>{money.hidden ? '••••' : formatForeign(item.originalAmount, item.currency)}</Text>
        </View>
      ) : (
        <Text style={[type.bodyAmount, { color: amountColor }]}>{money.signed(item.amount, item.type)}</Text>
      )}
    </View>
  );
});

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 11, minHeight: 61 },
  text: { flex: 1, gap: 2 },
  amounts: { alignItems: 'flex-end', gap: 1 },
});
