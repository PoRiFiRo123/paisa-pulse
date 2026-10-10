import { router } from 'expo-router';
import { ScrollView, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { BudgetRow } from '@/features/budgets/BudgetRow';
import { budgetProgress, type BudgetProgress } from '@/features/budgets/budgets';
import { useQuery } from '@/hooks/useQuery';
import { weekRange } from '@/lib/dates';
import { monthAt } from '@/lib/months';
import { usePrefs } from '@/stores/prefs';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { EmptyState } from '@/ui/EmptyState';
import { GlassButton } from '@/ui/Glass';
import { GroupHeader, InsetGroup } from '@/ui/InsetGroup';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';

export default function BudgetsScreen() {
  const { colors } = useTheme();
  const monthStartDay = usePrefs((s) => s.monthStartDay);
  const weekStartDay = usePrefs((s) => s.weekStartDay);
  const month = monthAt(0, monthStartDay);
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const { data, loaded } = useQuery(
    () => budgetProgress(appDb, month, Date.now(), weekRange(Date.now(), weekStartDay)),
    [month.start, weekStartDay],
    [],
  );
  const monthly = data.filter((p) => p.budget.period === 'monthly');
  const weekly = data.filter((p) => p.budget.period === 'weekly');
  const edit = (id?: string) => router.push(id ? { pathname: '/budget-form', params: { id } } : '/budget-form');

  const section = (title: string | null, rows: BudgetProgress[]) =>
    rows.length ? (
      <>
        {title ? <GroupHeader title={title} /> : null}
        <InsetGroup dividerInset={62}>
          {rows.map((p) => (
            <BudgetRow key={p.budget.id} progress={p} onPress={() => edit(p.budget.id)} />
          ))}
        </InsetGroup>
      </>
    ) : null;

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}>
        <LargeTitle title="Budgets" />
        <Text style={[type.subhead, { color: colors.secondary, paddingHorizontal: 20, marginTop: 4, marginBottom: 16 }]}>
          {month.label} · resets on the {monthStartDay === 1 ? '1st' : `${monthStartDay}th`}
        </Text>
        {loaded && !data.length ? (
          <EmptyState
            icon="chart.pie.fill"
            title="No budgets yet"
            message="Set a weekly or monthly limit for all spending or for a category like Food."
            actionLabel="Add Budget"
            onAction={() => edit()}
          />
        ) : (
          <>
            {section(weekly.length ? 'This month' : null, monthly)}
            {section(`This week · resets ${weekStartDay === 1 ? 'Monday' : 'Sunday'}`, weekly)}
          </>
        )}
      </ScrollView>
      <TopBar
        title="Budgets"
        scrollY={scrollY}
        leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />}
        trailing={<GlassButton icon="plus" accessibilityLabel="Add budget" onPress={() => edit()} />}
      />
    </View>
  );
}
