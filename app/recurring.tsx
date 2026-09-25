import { format } from 'date-fns';
import { asc, eq } from 'drizzle-orm';
import { router } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { accounts, categories, recurringRules } from '@/db/schema';
import { deleteRecurring, describeFrequency, setRecurringPaused } from '@/features/recurring/recurring';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { useToast } from '@/stores/toast';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { EmptyState } from '@/ui/EmptyState';
import { GlassButton } from '@/ui/Glass';
import { InsetGroup } from '@/ui/InsetGroup';
import { Menu } from '@/ui/Menu';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';

export default function RecurringScreen() {
  const { colors } = useTheme();
  const money = useMoney();
  const toast = useToast((s) => s.show);
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const { data: rules, loaded } = useQuery(
    () =>
      appDb
        .select({ rule: recurringRules, category: categories, account: accounts })
        .from(recurringRules)
        .innerJoin(accounts, eq(accounts.id, recurringRules.accountId))
        .leftJoin(categories, eq(categories.id, recurringRules.categoryId))
        .orderBy(asc(recurringRules.nextAt)),
    [],
    [],
  );
  const edit = (id?: string) => router.push(id ? { pathname: '/recurring-form', params: { id } } : '/recurring-form');

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}>
        <LargeTitle title="Recurring" />
        <Text style={[type.subhead, { color: colors.secondary, paddingHorizontal: 20, marginTop: 4, marginBottom: 16 }]}>
          Added automatically on their date: rent, salary, SIPs, subscriptions.
        </Text>
        {loaded && !rules.length ? (
          <EmptyState icon="repeat" title="Nothing repeats yet" message="Add a rule here, or open a transaction and choose Repeat." actionLabel="Add Recurring" onAction={() => edit()} />
        ) : (
          <InsetGroup dividerInset={66}>
            {rules.map(({ rule, category, account }) => {
              const paused = rule.pausedAt !== null;
              const ended = rule.endAt !== null && rule.nextAt > rule.endAt;
              const icon = rule.type === 'transfer' ? 'arrow.left.arrow.right' : (category?.icon ?? 'questionmark');
              const color = rule.type === 'transfer' ? '#8E8E93' : (category?.color ?? '#8E8E93');
              return (
                <Menu
                  key={rule.id}
                  items={[
                    { title: 'Edit', icon: 'pencil', onPress: () => edit(rule.id) },
                    paused
                      ? { title: 'Resume', icon: 'play.circle', onPress: () => setRecurringPaused(appDb, rule.id, false) }
                      : { title: 'Pause', icon: 'pause.circle', onPress: () => setRecurringPaused(appDb, rule.id, true) },
                    'separator',
                    {
                      title: 'Delete Rule',
                      icon: 'trash',
                      destructive: true,
                      onPress: () => deleteRecurring(appDb, rule.id).then(() => toast({ message: 'Rule deleted. Past transactions stay.' })),
                    },
                  ]}
                >
                  {(open) => (
                    <Pressable
                      onPress={() => edit(rule.id)}
                      onLongPress={open}
                      accessibilityRole="button"
                      style={({ pressed }) => [styles.row, { backgroundColor: pressed ? colors.fill : colors.card, opacity: paused || ended ? 0.55 : 1 }]}
                    >
                      <CategoryIcon icon={icon} color={color} />
                      <View style={{ flex: 1, gap: 2 }}>
                        <Text style={[type.body, { color: colors.label }]} numberOfLines={1}>
                          {rule.payee ?? category?.name ?? (rule.type === 'transfer' ? 'Transfer' : 'Recurring')}
                        </Text>
                        <Text style={[type.footnote, { color: colors.secondary }]} numberOfLines={1}>
                          {describeFrequency(rule)} · {account.name} ·{' '}
                          {paused ? 'Paused' : ended ? 'Ended' : `next ${format(rule.nextAt, 'd MMM')}`}
                        </Text>
                      </View>
                      <Text style={[type.bodyAmount, { color: rule.type === 'income' ? colors.income : colors.label }]}>
                        {money.signed(rule.amount, rule.type)}
                      </Text>
                    </Pressable>
                  )}
                </Menu>
              );
            })}
          </InsetGroup>
        )}
      </ScrollView>
      <TopBar
        title="Recurring"
        scrollY={scrollY}
        leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />}
        trailing={<GlassButton icon="plus" accessibilityLabel="Add recurring" onPress={() => edit()} />}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 11, minHeight: 61 },
});
