import { differenceInCalendarDays, format } from 'date-fns';
import { eq } from 'drizzle-orm';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { categories, type RecurringRule } from '@/db/schema';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';

import { describeFrequency } from './recurring';

/** Home "Upcoming": the next occurrence of a recurring rule. */
export function UpcomingRow({ rule, onPress }: { rule: RecurringRule; onPress: () => void }) {
  const { colors } = useTheme();
  const money = useMoney();
  const { data: category } = useQuery(
    async () => (rule.categoryId ? ((await appDb.select().from(categories).where(eq(categories.id, rule.categoryId)).get()) ?? null) : null),
    [rule.categoryId],
    null,
  );
  const days = differenceInCalendarDays(rule.nextAt, new Date());
  const when = days <= 0 ? 'Today' : days === 1 ? 'Tomorrow' : days < 7 ? format(rule.nextAt, 'EEEE') : format(rule.nextAt, 'd MMM');
  return (
    <Pressable onPress={onPress} accessibilityRole="button" style={({ pressed }) => [styles.row, { backgroundColor: pressed ? colors.fill : colors.card }]}>
      <CategoryIcon icon={rule.type === 'transfer' ? 'arrow.left.arrow.right' : (category?.icon ?? 'repeat')} color={rule.type === 'transfer' ? '#8E8E93' : (category?.color ?? '#30B0C7')} />
      <View style={{ flex: 1, gap: 2 }}>
        <Text style={[type.body, { color: colors.label }]} numberOfLines={1}>
          {rule.payee ?? category?.name ?? 'Recurring'}
        </Text>
        <Text style={[type.footnote, { color: colors.secondary }]}>
          {when} · {describeFrequency(rule)}
        </Text>
      </View>
      <Text style={[type.bodyAmount, { color: rule.type === 'income' ? colors.income : colors.label }]}>{money.signed(rule.amount, rule.type)}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 11, minHeight: 61 },
});
