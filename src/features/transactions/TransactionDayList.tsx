import { FlashList } from '@shopify/flash-list';
import { startOfDay } from 'date-fns';
import { type ReactElement, useMemo } from 'react';
import { StyleSheet, Text, View, type ViewStyle } from 'react-native';

import { useMoney } from '@/hooks/useMoney';
import { dayHeader } from '@/lib/format';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { Divider } from '@/ui/InsetGroup';

import type { TransactionItem } from './list';
import { TransactionListRow } from './TransactionListRow';

type Row =
  | { kind: 'header'; key: string; title: string; total: number }
  | { kind: 'row'; key: string; item: TransactionItem; first: boolean; last: boolean };

/** Group newest-first transactions into day headers + rows. Day total = income − expenses. */
export function toRows(items: TransactionItem[]): { rows: Row[]; sticky: number[] } {
  const rows: Row[] = [];
  const sticky: number[] = [];
  let day = -1;
  let header: Extract<Row, { kind: 'header' }> | null = null;
  items.forEach((item, i) => {
    const d = startOfDay(item.occurredAt).getTime();
    if (d !== day) {
      day = d;
      header = { kind: 'header', key: `h${d}`, title: dayHeader(item.occurredAt), total: 0 };
      sticky.push(rows.length);
      rows.push(header);
    }
    if (item.type === 'expense') header!.total -= item.amount;
    if (item.type === 'income') header!.total += item.amount;
    const next = items[i + 1];
    rows.push({
      kind: 'row',
      key: item.id,
      item,
      first: rows[rows.length - 1]?.kind === 'header',
      last: !next || startOfDay(next.occurredAt).getTime() !== d,
    });
  });
  return { rows, sticky };
}

/** Transactions grouped by day in inset cards, with sticky day headers showing the day's net. */
export function TransactionDayList({
  items,
  header,
  empty,
  onScroll,
  style,
  contentBottom,
}: {
  items: TransactionItem[];
  header?: ReactElement;
  empty?: ReactElement | null;
  onScroll?: (e: { nativeEvent: { contentOffset: { y: number } } }) => void;
  style?: ViewStyle;
  contentBottom: number;
}) {
  const { colors } = useTheme();
  const money = useMoney();
  const { rows, sticky } = useMemo(() => toRows(items), [items]);
  return (
    <FlashList
      data={rows}
      keyExtractor={(r) => r.key}
      getItemType={(r) => r.kind}
      stickyHeaderIndices={sticky}
      style={style}
      onScroll={onScroll}
      scrollEventThrottle={16}
      keyboardDismissMode="on-drag"
      contentInsetAdjustmentBehavior="never"
      contentContainerStyle={{ paddingBottom: contentBottom }}
      ListHeaderComponent={header}
      ListEmptyComponent={empty}
      renderItem={({ item: r }) =>
        r.kind === 'header' ? (
          <View style={[styles.dayHeader, { backgroundColor: colors.background }]}>
            <Text style={[type.sectionHeader, { color: colors.secondary }]}>{r.title}</Text>
            <Text style={[type.footnote, { color: colors.secondary, fontVariant: ['tabular-nums'] }]}>
              {r.total === 0 ? '' : money.balance(r.total)}
            </Text>
          </View>
        ) : (
          <View style={[styles.cardRow, { backgroundColor: colors.card }, r.first && styles.top, r.last && styles.bottom]}>
            {!r.first ? <Divider inset={66} /> : null}
            <TransactionListRow item={r.item} />
          </View>
        )
      }
    />
  );
}

const styles = StyleSheet.create({
  dayHeader: { flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 32, paddingTop: 18, paddingBottom: 6 },
  cardRow: { marginHorizontal: 16, overflow: 'hidden' },
  top: { borderTopLeftRadius: 22, borderTopRightRadius: 22 },
  bottom: { borderBottomLeftRadius: 22, borderBottomRightRadius: 22 },
});
