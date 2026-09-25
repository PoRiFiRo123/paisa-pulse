import { StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { periodSummary } from '@/features/transactions/queries';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { GlassSurface } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';

type Month = { start: number; end: number; name: string };

/** Figma "Hero Card (Glass)": spent this month, trend vs previous month, income and saved. */
export function HeroCard({ month, previous, isCurrent }: { month: Month; previous: Month; isCurrent: boolean }) {
  const { colors, dark } = useTheme();
  const money = useMoney();
  const { data } = useQuery(
    () => Promise.all([periodSummary(appDb, month), periodSummary(appDb, previous)]),
    [month.start, previous.start],
    [
      { spent: 0, received: 0, net: 0 },
      { spent: 0, received: 0, net: 0 },
    ],
  );
  const [now, before] = data;
  const change = before.spent > 0 ? Math.round(((now.spent - before.spent) / before.spent) * 100) : null;
  const less = change !== null && change <= 0;
  const saved = now.net;

  return (
    <GlassSurface radius={30} style={styles.card}>
      <Text style={[type.subhead, styles.medium, { color: colors.glassLabelSecondary }]}>
        {isCurrent ? 'Spent this month' : `Spent in ${month.name}`}
      </Text>
      <Text style={[type.amount, { color: colors.label }]} adjustsFontSizeToFit numberOfLines={1} accessibilityRole="header">
        {money.amount(now.spent)}
      </Text>
      {change !== null ? (
        <View style={styles.trend}>
          <Icon name={less ? 'arrow.down.right' : 'arrow.up.right'} size={14} color={less ? colors.positiveTrend : colors.expense} weight="bold" />
          <Text style={[type.footnote, styles.medium, { color: less ? colors.positiveTrend : colors.expense }]}>
            {change === 0 ? `Same as ${previous.name}` : `${Math.abs(change)}% ${less ? 'less' : 'more'} than ${previous.name}`}
          </Text>
        </View>
      ) : (
        <View style={styles.trend} />
      )}
      <View style={[styles.divider, { backgroundColor: dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.12)' }]} />
      <View style={styles.stats}>
        <Stat icon="arrow.down.left" tint={colors.income} label="Income" value={money.amount(now.received)} />
        <Stat
          icon="checkmark.seal.fill"
          tint={saved < 0 ? colors.expense : colors.accent}
          label={saved < 0 ? 'Overspent' : 'Saved'}
          value={money.amount(Math.abs(saved))}
        />
      </View>
    </GlassSurface>
  );
}

function Stat({ icon, tint, label, value }: { icon: string; tint: string; label: string; value: string }) {
  const { colors } = useTheme();
  return (
    <View style={styles.stat}>
      <View style={[styles.statIcon, { backgroundColor: `${tint}2E` }]}>
        <Icon name={icon} size={16} color={tint} weight="bold" />
      </View>
      <View>
        <Text style={[type.caption, { color: colors.glassLabelSecondary }]}>{label}</Text>
        <Text style={[type.bodyAmount, { color: colors.label }]}>{value}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { paddingTop: 20, paddingBottom: 18, paddingHorizontal: 20, gap: 4 },
  medium: { fontWeight: '500' },
  trend: { flexDirection: 'row', alignItems: 'center', gap: 4, minHeight: 16 },
  divider: { height: StyleSheet.hairlineWidth, marginVertical: 10 },
  stats: { flexDirection: 'row', gap: 12 },
  stat: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 10 },
  statIcon: { width: 30, height: 30, borderRadius: 15, alignItems: 'center', justifyContent: 'center' },
});
