import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useMoney } from '@/hooks/useMoney';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { ProgressBar } from '@/ui/ProgressBar';

import type { BudgetProgress } from './budgets';

/** Budget with a progress bar: "₹1,000 left of ₹6,000" and a pace marker. */
export function BudgetRow({ progress, onPress }: { progress: BudgetProgress; onPress?: () => void }) {
  const { colors } = useTheme();
  const money = useMoney();
  const { category, budget, spent, remaining, ratio, elapsed, status } = progress;
  const color =
    status === 'over' ? colors.expense : status === 'warning' ? '#FF9500' : status === 'ahead' ? '#FFB800' : (category?.color ?? colors.accent);
  const detail =
    remaining >= 0 ? `${money.amount(remaining)} left of ${money.amount(budget.amount)}` : `${money.amount(-remaining)} over ${money.amount(budget.amount)}`;
  const hint = status === 'ahead' ? ' · spending fast' : '';
  return (
    <Pressable
      onPress={onPress}
      disabled={!onPress}
      accessibilityRole="button"
      accessibilityLabel={`${category?.name ?? 'Overall budget'}: ${money.amount(spent)} spent, ${detail}`}
      style={({ pressed }) => [styles.row, { backgroundColor: pressed ? colors.fill : colors.card }]}
    >
      <CategoryIcon icon={category?.icon ?? 'chart.pie.fill'} color={category?.color ?? colors.accent} size={34} />
      <View style={styles.body}>
        <View style={styles.line}>
          <Text style={[type.body, { color: colors.label, flex: 1 }]} numberOfLines={1}>
            {category?.name ?? 'All spending'}
          </Text>
          <Text style={[type.bodyAmount, { color: status === 'over' ? colors.expense : colors.label }]}>{money.amount(spent)}</Text>
        </View>
        <ProgressBar ratio={ratio} color={color} marker={elapsed} />
        <Text style={[type.footnote, { color: status === 'over' ? colors.expense : colors.secondary }]} numberOfLines={1}>
          {detail}
          {hint}
        </Text>
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 12 },
  body: { flex: 1, gap: 6 },
  line: { flexDirection: 'row', alignItems: 'center', gap: 8 },
});
