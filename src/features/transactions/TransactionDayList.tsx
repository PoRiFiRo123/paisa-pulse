import { FlashList } from '@shopify/flash-list';
import { startOfDay } from 'date-fns';
import * as Haptics from 'expo-haptics';
import { type ReactElement, useMemo } from 'react';
import { Pressable, StyleSheet, Text, View, type ViewStyle } from 'react-native';

import { useMoney } from '@/hooks/useMoney';
import { dayHeader } from '@/lib/format';
import { useSelection } from '@/stores/selection';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { Icon } from '@/ui/Icon';
import { Divider } from '@/ui/InsetGroup';
import { TransactionRow } from '@/ui/TransactionRow';

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
  selectable = false,
}: {
  items: TransactionItem[];
  header?: ReactElement;
  empty?: ReactElement | null;
  onScroll?: (e: { nativeEvent: { contentOffset: { y: number } } }) => void;
  style?: ViewStyle;
  contentBottom: number;
  /** Rows offer "Select", and render checkboxes while multi-select is active. */
  selectable?: boolean;
}) {
  const { colors } = useTheme();
  const money = useMoney();
  const selecting = useSelection((s) => selectable && s.active);
  const selectedIds = useSelection((s) => s.ids);
  const selected = useMemo(() => new Set(selecting ? selectedIds : []), [selecting, selectedIds]);
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
      extraData={selected}
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
            {selecting ? (
              <SelectableRow item={r.item} selected={selected.has(r.item.id)} />
            ) : (
              <TransactionListRow item={r.item} selectable={selectable} />
            )}
          </View>
        )
      }
    />
  );
}

function SelectableRow({ item, selected }: { item: TransactionItem; selected: boolean }) {
  const { colors } = useTheme();
  const toggle = useSelection((s) => s.toggle);
  return (
    <Pressable
      onPress={() => {
        Haptics.selectionAsync().catch(() => {});
        toggle(item.id);
      }}
      accessibilityRole="checkbox"
      accessibilityState={{ checked: selected }}
      style={[styles.selectable, { backgroundColor: selected ? colors.fill : colors.card }]}
    >
      <Icon
        name={selected ? 'checkmark.circle.fill' : 'circle'}
        size={24}
        color={selected ? colors.accent : colors.secondary}
        weight="regular"
      />
      <View style={{ flex: 1 }} pointerEvents="none">
        <TransactionRow item={item} />
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  selectable: { flexDirection: 'row', alignItems: 'center', paddingLeft: 16 },
  dayHeader: { flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 32, paddingTop: 18, paddingBottom: 6 },
  cardRow: { marginHorizontal: 16, overflow: 'hidden' },
  top: { borderTopLeftRadius: 22, borderTopRightRadius: 22 },
  bottom: { borderBottomLeftRadius: 22, borderBottomRightRadius: 22 },
});
