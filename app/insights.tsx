import { format } from 'date-fns';
import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { biggestExpenses, categoryBreakdown, daysElapsed, monthlyTotals, percentChange } from '@/features/insights/insights';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { chartColor } from '@/lib/color';
import { formatINRAxis } from '@/lib/money';
import { monthAt } from '@/lib/months';
import { usePrefs } from '@/stores/prefs';
import { useUi } from '@/stores/ui';
import { UNCATEGORISED_COLOR } from '@/theme/tokens';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { BarChart } from '@/ui/charts/BarChart';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { GlassButton } from '@/ui/Glass';
import { Divider } from '@/ui/InsetGroup';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';
import { SegmentedControl } from '@/ui/SegmentedControl';

export default function InsightsScreen() {
  const { colors, dark } = useTheme();
  const money = useMoney();
  const monthStartDay = usePrefs((s) => s.monthStartDay);
  const setActivity = useUi((s) => s.setActivity);
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const [span, setSpan] = useState<'6' | '12'>('6');
  const [offset, setOffset] = useState(0);
  const [now] = useState(() => Date.now());

  const months = useMemo(
    () => Array.from({ length: Number(span) }, (_, i) => monthAt(Number(span) - 1 - i, monthStartDay)),
    [span, monthStartDay],
  );
  const { data: points } = useQuery(() => monthlyTotals(appDb, months), [months], []);
  const month = monthAt(offset, monthStartDay);
  const previous = monthAt(offset + 1, monthStartDay);
  const { data: breakdown } = useQuery(() => categoryBreakdown(appDb, month), [month.start], []);
  const { data: biggest } = useQuery(() => biggestExpenses(appDb, month), [month.start], []);
  const { data: prevPoint } = useQuery(() => monthlyTotals(appDb, [previous]), [previous.start], []);

  const current = points.find((p) => p.start === month.start) ?? { spent: 0, received: 0, net: 0 };
  const change = percentChange(current.spent, prevPoint[0]?.spent ?? 0);
  // Whole rupees: a per-day average doesn't need paise.
  const perDay = Math.round(current.spent / daysElapsed(month, now) / 100) * 100;

  const openCategory = (categoryId: string | null) => {
    setActivity({ monthOffset: offset, categoryIds: [categoryId], accountIds: [], types: [] });
    router.navigate('/activity');
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}>
        <LargeTitle title="Insights" />

        {/* Headline: a number, not a chart. */}
        <View style={[styles.card, { backgroundColor: colors.card, marginTop: 15 }]}>
          <Text style={[type.subhead, { color: colors.secondary }]}>Spent in {month.label}</Text>
          <Text style={[type.amount, { color: colors.label }]} adjustsFontSizeToFit numberOfLines={1}>
            {money.amount(current.spent)}
          </Text>
          <View style={styles.tiles}>
            <Tile label="Per day" value={money.amount(perDay)} />
            <Tile
              label={`vs ${previous.short}`}
              value={change === null ? '—' : `${change > 0 ? '+' : ''}${change}%`}
              tone={change === null ? undefined : change > 0 ? colors.expense : colors.positiveTrend}
            />
            <Tile label="Income" value={money.amount(current.received)} />
          </View>
        </View>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <View style={styles.cardHead}>
            <Text style={[type.headline, { color: colors.label, flex: 1 }]} accessibilityRole="header">
              Monthly spending
            </Text>
            <View style={{ width: 150 }}>
              <SegmentedControl
                value={span}
                onChange={setSpan}
                segments={[
                  { value: '6', label: '6M' },
                  { value: '12', label: '1Y' },
                ]}
              />
            </View>
          </View>
          <BarChart
            bars={points.map((p, i) => ({
              key: String(Number(span) - 1 - i),
              label: Number(span) > 6 ? p.short.slice(0, 1) : p.short,
              value: p.spent,
              accessibilityLabel: `${p.label}: spent ${money.amount(p.spent)}, income ${money.amount(p.received)}`,
            }))}
            color={colors.accent}
            selectedKey={String(offset)}
            onSelect={(k) => setOffset(Number(k))}
            formatTick={(v) => (money.hidden ? '' : formatINRAxis(v))}
          />
          <Text style={[type.footnote, { color: colors.secondary, marginTop: 8 }]}>
            Tap a month to see its breakdown. Transfers and card bill payments aren’t counted as spending.
          </Text>
        </View>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <Text style={[type.headline, { color: colors.label }]} accessibilityRole="header">
            Where it went · {month.short}
          </Text>
          {breakdown.length === 0 ? (
            <Text style={[type.subhead, { color: colors.secondary, marginTop: 8 }]}>No spending this month.</Text>
          ) : null}
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
      />
    </View>
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
  cardHead: { flexDirection: 'row', alignItems: 'center', marginBottom: 14, gap: 12 },
  tiles: { flexDirection: 'row', gap: 8, marginTop: 12 },
  tile: { flex: 1, borderRadius: 14, paddingVertical: 10, paddingHorizontal: 12, gap: 2 },
  breakRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 10 },
  breakLine: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  pct: { width: 38, textAlign: 'right', fontVariant: ['tabular-nums'] },
  track: { height: 8, borderRadius: 4, overflow: 'hidden' },
  fill: { height: '100%', borderRadius: 4 },
  bigRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 18, paddingVertical: 12 },
});
