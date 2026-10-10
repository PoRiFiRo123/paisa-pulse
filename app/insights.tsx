import { endOfDay, format, startOfDay } from 'date-fns';
import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { biggestExpenses, categoryBreakdown, daysElapsed, monthlyTotals, percentChange } from '@/features/insights/insights';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { chartColor } from '@/lib/color';
import { formatINRAxis } from '@/lib/money';
import { type Period, periodAt, type PeriodKind, previousRange, rangeLabel, TREND_LENGTH } from '@/lib/periods';
import { usePrefs } from '@/stores/prefs';
import { useUi } from '@/stores/ui';
import { UNCATEGORISED_COLOR } from '@/theme/tokens';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { BarChart } from '@/ui/charts/BarChart';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { DateTimeSheet, pickDateAndroid } from '@/ui/DateTimeSheet';
import { GlassButton } from '@/ui/Glass';
import { Divider } from '@/ui/InsetGroup';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';
import { SegmentedControl } from '@/ui/SegmentedControl';

type Kind = PeriodKind | 'custom';
const NOUN: Record<PeriodKind, string> = { week: 'Weekly', month: 'Monthly', quarter: 'Quarterly', year: 'Yearly' };

export default function InsightsScreen() {
  const { colors, dark } = useTheme();
  const money = useMoney();
  const monthStartDay = usePrefs((s) => s.monthStartDay);
  const weekStartDay = usePrefs((s) => s.weekStartDay);
  const setActivity = useUi((s) => s.setActivity);
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const [kind, setKind] = useState<Kind>('month');
  const [offset, setOffset] = useState(0);
  const [now] = useState(() => Date.now());
  const [custom, setCustom] = useState(() => ({ start: startOfDay(now - 29 * 86_400_000).getTime(), end: endOfDay(now).getTime() + 1 }));
  const [editing, setEditing] = useState<'start' | 'end' | null>(null);
  const prefs = useMemo(() => ({ monthStartDay, weekStartDay }), [monthStartDay, weekStartDay]);

  const trend: Period[] = useMemo(() => {
    if (kind === 'custom') return [];
    const n = TREND_LENGTH[kind];
    return Array.from({ length: n }, (_, i) => periodAt(kind, n - 1 - i, prefs, now));
  }, [kind, prefs, now]);
  const period: Period =
    kind === 'custom' ? { ...custom, label: rangeLabel(custom.start, custom.end), short: '' } : periodAt(kind, offset, prefs, now);
  const previous =
    kind === 'custom' ? { ...previousRange(custom), label: 'previous', short: 'previous' } : periodAt(kind, offset + 1, prefs, now);

  const { data: points } = useQuery(() => monthlyTotals(appDb, trend), [trend], []);
  const { data: currentPoint } = useQuery(() => monthlyTotals(appDb, [period]), [period.start, period.end], []);
  const { data: prevPoint } = useQuery(() => monthlyTotals(appDb, [previous]), [previous.start, previous.end], []);
  const { data: breakdown } = useQuery(() => categoryBreakdown(appDb, period), [period.start, period.end], []);
  const { data: biggest } = useQuery(() => biggestExpenses(appDb, period), [period.start, period.end], []);

  const current = currentPoint[0] ?? { spent: 0, received: 0, net: 0 };
  const change = percentChange(current.spent, prevPoint[0]?.spent ?? 0);
  // Whole rupees: a per-day average doesn't need paise.
  const perDay = Math.round(current.spent / daysElapsed(period, now) / 100) * 100;
  const kept = current.received - current.spent;
  const keptShare = current.received > 0 ? Math.round((kept / current.received) * 100) : null;
  const heading = kind === 'week' && offset === 0 ? 'Spent this week' : `Spent in ${period.label}`;

  const openCategory = (categoryId: string | null) => {
    const filters = { categoryIds: [categoryId], accountIds: [], types: [] };
    if (kind === 'month') setActivity({ ...filters, monthOffset: offset, range: null });
    else setActivity({ ...filters, range: { start: period.start, end: period.end, label: period.label } });
    router.navigate('/activity');
  };

  const pickDate = (which: 'start' | 'end') => {
    if (Platform.OS === 'ios') setEditing(which);
    else pickDateAndroid(which === 'start' ? custom.start : custom.end - 1, (ms) => pickDateApply(which, ms, setCustom), now);
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}>
        <LargeTitle title="Insights" />

        <View style={{ paddingHorizontal: 16, marginTop: 12 }}>
          <SegmentedControl
            value={kind}
            onChange={(k) => {
              setKind(k);
              setOffset(0);
            }}
            segments={[
              { value: 'week', label: 'Week' },
              { value: 'month', label: 'Month' },
              { value: 'quarter', label: 'Qtr' },
              { value: 'year', label: 'Year' },
              { value: 'custom', label: 'Custom' },
            ]}
          />
        </View>

        {kind === 'custom' ? (
          <View style={styles.rangeRow}>
            <DateChip label="From" value={custom.start} onPress={() => pickDate('start')} />
            <DateChip label="To" value={custom.end - 1} onPress={() => pickDate('end')} />
          </View>
        ) : null}

        {/* Headline: a number, not a chart. */}
        <View style={[styles.card, { backgroundColor: colors.card, marginTop: 15 }]}>
          <Text style={[type.subhead, { color: colors.secondary }]}>{heading}</Text>
          <Text style={[type.amount, { color: colors.label }]} adjustsFontSizeToFit numberOfLines={1}>
            {money.amount(current.spent)}
          </Text>
          <View style={styles.tiles}>
            <Tile label="Per day" value={money.amount(perDay)} />
            <Tile
              label={kind === 'custom' ? 'vs previous' : `vs ${previous.short}`}
              value={change === null ? '—' : `${change > 0 ? '+' : ''}${change}%`}
              tone={change === null ? undefined : change > 0 ? colors.expense : colors.positiveTrend}
            />
            <Tile label="Income" value={money.amount(current.received)} />
          </View>
          {current.received > 0 ? (
            <Text style={[type.footnote, { color: colors.secondary, marginTop: 10 }]}>
              {kept >= 0 ? `You kept ${money.amount(kept)}` : `You spent ${money.amount(-kept)} more than you earned`}
              {keptShare !== null && kept >= 0 ? ` · ${keptShare}% of income` : ''}
            </Text>
          ) : null}
        </View>

        {kind !== 'custom' ? (
          <View style={[styles.card, { backgroundColor: colors.card }]}>
            <Text style={[type.headline, { color: colors.label, marginBottom: 14 }]} accessibilityRole="header">
              {NOUN[kind]} spending
            </Text>
            <BarChart
              bars={points.map((p, i) => ({
                key: String(trend.length - 1 - i),
                label: p.short,
                value: p.spent,
                accessibilityLabel: `${p.label}: spent ${money.amount(p.spent)}, income ${money.amount(p.received)}`,
              }))}
              color={colors.accent}
              selectedKey={String(offset)}
              onSelect={(k) => setOffset(Number(k))}
              formatTick={(v) => (money.hidden ? '' : formatINRAxis(v))}
            />
            <Text style={[type.footnote, { color: colors.secondary, marginTop: 8 }]}>
              Tap a bar to see its breakdown. Transfers and card bill payments aren’t counted as spending.
            </Text>
          </View>
        ) : null}

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <Text style={[type.headline, { color: colors.label }]} accessibilityRole="header">
            Where it went · {kind === 'month' ? period.short : period.label}
          </Text>
          {breakdown.length === 0 ? <Text style={[type.subhead, { color: colors.secondary, marginTop: 8 }]}>No spending in this period.</Text> : null}
          {/* Each category is its own labelled row (icon + name + amount), so colour is never the only cue. */}
          {breakdown.map((b) => {
            const color = b.category?.color ?? UNCATEGORISED_COLOR;
            return (
              <Pressable
                key={b.categoryId ?? 'none'}
                onPress={() => openCategory(b.categoryId)}
                accessibilityRole="button"
                accessibilityLabel={`${b.category?.name ?? 'Uncategorised'}: ${money.amount(b.total)}, ${Math.round(b.share * 100)} percent`}
                style={styles.breakRow}
              >
                <CategoryIcon icon={b.category?.icon ?? 'questionmark'} color={color} size={30} />
                <View style={{ flex: 1, gap: 6 }}>
                  <View style={styles.breakLine}>
                    <Text style={[type.subhead, { color: colors.label, flex: 1 }]} numberOfLines={1}>
                      {b.category?.name ?? 'Uncategorised'}
                    </Text>
                    <Text style={[type.subheadAmount, { color: colors.label }]}>{money.amount(b.total)}</Text>
                    <Text style={[type.footnote, styles.pct, { color: colors.secondary }]}>{Math.round(b.share * 100)}%</Text>
                  </View>
                  <View style={[styles.track, { backgroundColor: colors.fill }]}>
                    <View style={[styles.fill, { width: `${Math.max(b.share * 100, 1.5)}%`, backgroundColor: chartColor(color, dark) }]} />
                  </View>
                </View>
              </Pressable>
            );
          })}
        </View>

        {biggest.length ? (
          <View style={[styles.card, { backgroundColor: colors.card, paddingHorizontal: 0 }]}>
            <Text style={[type.headline, { color: colors.label, paddingHorizontal: 18, marginBottom: 4 }]} accessibilityRole="header">
              Biggest expenses
            </Text>
            {biggest.map((t, i) => (
              <View key={t.id}>
                {i > 0 ? <Divider inset={18} /> : null}
                <Pressable onPress={() => router.push({ pathname: '/transaction/[id]', params: { id: t.id } })} style={styles.bigRow} accessibilityRole="button">
                  <Text style={[type.body, { color: colors.label, flex: 1 }]} numberOfLines={1}>
                    {t.payee ?? t.note ?? 'Expense'}
                  </Text>
                  <Text style={[type.footnote, { color: colors.secondary }]}>{format(t.occurredAt, 'd MMM')}</Text>
                  <Text style={[type.bodyAmount, { color: colors.label, minWidth: 90, textAlign: 'right' }]}>{money.signed(t.amount, 'expense')}</Text>
                </Pressable>
              </View>
            ))}
          </View>
        ) : null}
      </ScrollView>
      <TopBar
        title="Insights"
        scrollY={scrollY}
        leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />}
        trailing={<GlassButton icon="calendar" accessibilityLabel="Calendar" onPress={() => router.push('/calendar')} />}
      />
      <DateTimeSheet
        visible={editing !== null}
        mode="date"
        value={editing === 'end' ? custom.end - 1 : custom.start}
        onClose={() => setEditing(null)}
        onChange={(ms) => editing && pickDateApply(editing, ms, setCustom)}
      />
    </View>
  );
}

/** Apply a picked date to the custom range, keeping start before end. */
function pickDateApply(which: 'start' | 'end', ms: number, set: (f: (c: { start: number; end: number }) => { start: number; end: number }) => void) {
  set((c) => {
    if (which === 'start') {
      const start = startOfDay(ms).getTime();
      return start < c.end ? { ...c, start } : { start, end: endOfDay(ms).getTime() + 1 };
    }
    const end = endOfDay(ms).getTime() + 1;
    return c.start < end ? { ...c, end } : { start: startOfDay(ms).getTime(), end };
  });
}

function DateChip({ label, value, onPress }: { label: string; value: number; onPress: () => void }) {
  const { colors } = useTheme();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={`${label} ${format(value, 'd MMMM yyyy')}`}
      style={[styles.dateChip, { backgroundColor: colors.card }]}
    >
      <Text style={[type.caption, { color: colors.secondary }]}>{label}</Text>
      <Text style={[type.subhead, { color: colors.accent, fontWeight: '600' }]}>{format(value, 'd MMM yyyy')}</Text>
    </Pressable>
  );
}

function Tile({ label, value, tone }: { label: string; value: string; tone?: string }) {
  const { colors } = useTheme();
  return (
    <View style={[styles.tile, { backgroundColor: colors.fill }]}>
      <Text style={[type.caption, { color: colors.secondary }]}>{label}</Text>
      <Text style={[type.subheadAmount, { color: tone ?? colors.label }]} numberOfLines={1} adjustsFontSizeToFit>
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { marginHorizontal: 16, marginTop: 18, borderRadius: 22, padding: 18 },
  tiles: { flexDirection: 'row', gap: 8, marginTop: 12 },
  tile: { flex: 1, borderRadius: 14, paddingVertical: 10, paddingHorizontal: 12, gap: 2 },
  rangeRow: { flexDirection: 'row', gap: 10, paddingHorizontal: 16, marginTop: 12 },
  dateChip: { flex: 1, borderRadius: 14, paddingVertical: 10, paddingHorizontal: 14, gap: 2 },
  breakRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 10 },
  breakLine: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  pct: { width: 38, textAlign: 'right', fontVariant: ['tabular-nums'] },
  track: { height: 8, borderRadius: 4, overflow: 'hidden' },
  fill: { height: '100%', borderRadius: 4 },
  bigRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 18, paddingVertical: 12 },
});
