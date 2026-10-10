import { addMonths, format, isSameDay, isSameMonth } from 'date-fns';
import * as Haptics from 'expo-haptics';
import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';

import { appDb } from '@/db/client';
import { dailyTotals, dayKey, heat, monthGrid } from '@/features/calendar/calendar';
import { listTransactions } from '@/features/transactions/list';
import { TransactionListRow } from '@/features/transactions/TransactionListRow';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { MINUS } from '@/lib/format';
import { formatINRTiny } from '@/lib/money';
import { usePrefs } from '@/stores/prefs';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { GlassButton, GlassGroup } from '@/ui/Glass';
import { InsetGroup } from '@/ui/InsetGroup';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';

const WEEKDAYS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/** Month calendar: each day's net, a single-hue heat for spending, and the day's transactions below. */
export default function CalendarScreen() {
  const { colors } = useTheme();
  const money = useMoney();
  const weekStartDay = usePrefs((s) => s.weekStartDay);
  const { width } = useWindowDimensions();
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const [today] = useState(() => Date.now());
  const [month, setMonth] = useState(today);
  const [selected, setSelected] = useState(today);

  const grid = useMemo(() => monthGrid(month, weekStartDay), [month, weekStartDay]);
  const { data: totals } = useQuery(() => dailyTotals(appDb, { start: grid.cells[0].date, end: grid.cells[grid.cells.length - 1].date + 86_400_000 }), [grid], new Map());
  const dayStart = new Date(selected).setHours(0, 0, 0, 0);
  const { data: items } = useQuery(() => listTransactions(appDb, { range: { start: dayStart, end: dayStart + 86_400_000 } }), [dayStart], []);

  const inMonth = grid.cells.filter((c) => c.inMonth).map((c) => totals.get(c.key));
  const spent = inMonth.reduce((s, d) => s + (d?.spent ?? 0), 0);
  const received = inMonth.reduce((s, d) => s + (d?.received ?? 0), 0);
  const max = Math.max(0, ...inMonth.map((d) => d?.spent ?? 0));
  const selectedTotals = totals.get(dayKey(selected));
  const cell = Math.floor((width - 32) / 7);
  const weekdays = weekStartDay === 1 ? [...WEEKDAYS.slice(1), WEEKDAYS[0]] : WEEKDAYS;

  const shift = (n: number) => {
    const next = addMonths(month, n).getTime();
    setMonth(next);
    setSelected(isSameMonth(next, today) ? today : next);
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}>
        <LargeTitle title={format(month, 'MMMM yyyy')} />

        <View style={[styles.summary]}>
          <Stat label="Spent" value={money.amount(spent)} />
          <Stat label="Income" value={money.amount(received)} color={colors.income} />
          <Stat label="Net" value={money.hidden ? money.amount(0) : `${received - spent < 0 ? MINUS : '+'}${money.amount(Math.abs(received - spent))}`} />
        </View>

        <View style={[styles.calendar, { backgroundColor: colors.card }]}>
          <View style={styles.week}>
            {weekdays.map((d, i) => (
              <Text key={i} style={[type.caption, styles.weekday, { width: cell, color: colors.secondary }]}>
                {d}
              </Text>
            ))}
          </View>
          <View style={styles.cells}>
            {grid.cells.map((c) => {
              const t = totals.get(c.key);
              const h = c.inMonth ? heat(t?.spent ?? 0, max) : 0;
              const isSelected = isSameDay(c.date, selected);
              const isToday = isSameDay(c.date, today);
              const strong = h > 0.62;
              const net = (t?.received ?? 0) - (t?.spent ?? 0);
              const label = !t || money.hidden || net === 0 ? '' : `${net < 0 ? MINUS : '+'}${formatINRTiny(net)}`;
              return (
                <Pressable
                  key={c.key}
                  onPress={() => {
                    Haptics.selectionAsync().catch(() => {});
                    setSelected(c.date);
                    if (!c.inMonth) setMonth(c.date);
                  }}
                  accessibilityRole="button"
                  accessibilityState={{ selected: isSelected }}
                  accessibilityLabel={`${format(c.date, 'EEEE d MMMM')}${t ? `: spent ${money.amount(t.spent)}, income ${money.amount(t.received)}` : ', nothing recorded'}`}
                  style={[styles.cell, { width: cell, height: cell + 8 }]}
                >
                  <View
                    style={[
                      styles.cellInner,
                      { backgroundColor: h ? `${colors.accent}${Math.round(18 + h * 222).toString(16).padStart(2, '0')}` : 'transparent' },
                      isSelected && { borderColor: colors.label, borderWidth: 2 },
                    ]}
                  >
                    <Text
                      style={[
                        type.subhead,
                        { fontWeight: isToday ? '700' : '500', color: !c.inMonth ? colors.separator : strong ? '#FFFFFF' : isToday ? colors.accent : colors.label },
                      ]}
                    >
                      {format(c.date, 'd')}
                    </Text>
                    <Text
                      numberOfLines={1}
                      style={[styles.net, { color: strong ? '#FFFFFF' : net > 0 ? colors.income : colors.secondary }]}
                    >
                      {c.inMonth ? label : ''}
                    </Text>
                  </View>
                </Pressable>
              );
            })}
          </View>
          <Text style={[type.footnote, { color: colors.secondary, marginTop: 8, paddingHorizontal: 4 }]}>
            Darker days are bigger spending days. Numbers are each day’s net.
          </Text>
        </View>

        <View style={styles.dayHead}>
          <Text style={[type.headline, { color: colors.label, flex: 1 }]} accessibilityRole="header">
            {isSameDay(selected, today) ? 'Today' : format(selected, 'EEEE, d MMMM')}
          </Text>
          {selectedTotals?.spent ? <Text style={[type.subheadAmount, { color: colors.secondary }]}>{money.amount(selectedTotals.spent)} spent</Text> : null}
        </View>
        {items.length ? (
          <InsetGroup dividerInset={66}>
            {items.map((item) => (
              <TransactionListRow key={item.id} item={item} />
            ))}
          </InsetGroup>
        ) : (
          <Pressable
            onPress={() => router.push({ pathname: '/add', params: { at: String(new Date(selected).setHours(12, 0, 0, 0)) } })}
            accessibilityRole="button"
            style={[styles.emptyDay, { backgroundColor: colors.card }]}
          >
            <Text style={[type.subhead, { color: colors.secondary }]}>Nothing on this day.</Text>
            <Text style={[type.subhead, { color: colors.accent, fontWeight: '600' }]}>Add one</Text>
          </Pressable>
        )}
      </ScrollView>
      <TopBar
        title={format(month, 'MMMM yyyy')}
        scrollY={scrollY}
        leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />}
        trailing={
          <GlassGroup>
            <GlassButton icon="chevron.up" accessibilityLabel="Previous month" onPress={() => shift(-1)} />
            <GlassButton icon="chevron.down" accessibilityLabel="Next month" onPress={() => shift(1)} />
          </GlassGroup>
        }
      />
    </View>
  );
}

function Stat({ label, value, color }: { label: string; value: string; color?: string }) {
  const { colors } = useTheme();
  return (
    <View style={[styles.stat, { backgroundColor: colors.card }]}>
      <Text style={[type.caption, { color: colors.secondary }]}>{label}</Text>
      <Text style={[type.subheadAmount, { color: color ?? colors.label }]} numberOfLines={1} adjustsFontSizeToFit>
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  summary: { flexDirection: 'row', gap: 8, paddingHorizontal: 16, marginTop: 14 },
  stat: { flex: 1, borderRadius: 14, paddingVertical: 10, paddingHorizontal: 12, gap: 2 },
  calendar: { marginHorizontal: 16, marginTop: 14, borderRadius: 22, paddingVertical: 12 },
  week: { flexDirection: 'row' },
  weekday: { textAlign: 'center', marginBottom: 6 },
  cells: { flexDirection: 'row', flexWrap: 'wrap' },
  cell: { padding: 2 },
  cellInner: { flex: 1, borderRadius: 12, alignItems: 'center', justifyContent: 'center', gap: 1 },
  net: { fontSize: 10, lineHeight: 12, fontWeight: '600', fontVariant: ['tabular-nums'] },
  dayHead: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20, marginTop: 22, marginBottom: 8 },
  emptyDay: { marginHorizontal: 16, borderRadius: 16, padding: 16, flexDirection: 'row', justifyContent: 'space-between' },
});
