import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { appDb } from '@/db/client';
import { accountsWithBalance } from '@/features/accounts/queries';
import { categoriesByKind } from '@/features/categories/queries';
import { useQuery } from '@/hooks/useQuery';
import { accountLabel } from '@/lib/format';
import { monthAt } from '@/lib/months';
import { usePrefs } from '@/stores/prefs';
import { type ActivityFilters, useUi } from '@/stores/ui';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { AddButton } from '@/ui/AddButton';
import { EmptyState } from '@/ui/EmptyState';
import { GlassButton, GlassGroup } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { Menu, type MenuItem } from '@/ui/Menu';
import { LargeTitle, TopBar, useBottomSpace, useScrollHeader, useTitleTop } from '@/ui/Screen';

import { listTransactions } from './list';
import { TransactionDayList } from './TransactionDayList';

const EMPTY_FILTERS: ActivityFilters = { monthOffset: null, accountIds: [], categoryIds: [], types: [] };

export function ActivityScreen({ mode = 'activity' }: { mode?: 'activity' | 'search' }) {
  const { colors } = useTheme();
  const monthStartDay = usePrefs((s) => s.monthStartDay);
  const shared = useUi((s) => s.activity);
  const setShared = useUi((s) => s.setActivity);
  const [local, setLocal] = useState<ActivityFilters>(EMPTY_FILTERS);
  const filters = mode === 'activity' ? shared : local;
  const setFilters = (patch: Partial<ActivityFilters>) =>
    mode === 'activity' ? setShared(patch) : setLocal((f) => ({ ...f, ...patch }));

  const [query, setQuery] = useState('');
  const [search, setSearch] = useState('');
  useEffect(() => {
    const t = setTimeout(() => setSearch(query), 150);
    return () => clearTimeout(t);
  }, [query]);

  const { scrollY, onScroll } = useScrollHeader();
  const titleTop = useTitleTop();
  const bottom = useBottomSpace();

  const range = filters.monthOffset === null ? undefined : monthAt(filters.monthOffset, monthStartDay);
  const { data: items, loaded } = useQuery(
    () =>
      listTransactions(appDb, {
        range,
        accountIds: filters.accountIds,
        categoryIds: filters.categoryIds,
        types: filters.types,
        search,
      }),
    [range?.start, filters.accountIds, filters.categoryIds, filters.types, search],
    [],
  );
  const { data: accounts } = useQuery(() => accountsWithBalance(appDb, { includeArchived: true }), [], []);
  const { data: expenseCats } = useQuery(() => categoriesByKind(appDb, 'expense'), [], []);
  const { data: incomeCats } = useQuery(() => categoriesByKind(appDb, 'income'), [], []);


  const monthLabel = filters.monthOffset === null ? 'All time' : monthAt(filters.monthOffset, monthStartDay).label;
  const account = accounts.find((a) => a.id === filters.accountIds[0]);
  const allCats = [...expenseCats, ...incomeCats];
  const category = filters.categoryIds.length
    ? filters.categoryIds[0] === null
      ? 'Uncategorised'
      : (allCats.find((c) => c.id === filters.categoryIds[0])?.name ?? 'Category')
    : null;
  const typeLabel = filters.types.length ? { expense: 'Expenses', income: 'Income', transfer: 'Transfers' }[filters.types[0]] : null;

  const monthItems: MenuItem[] = [
    { title: 'All time', checked: filters.monthOffset === null, onPress: () => setFilters({ monthOffset: null }) },
    'separator',
    ...Array.from({ length: 12 }, (_, o) => ({
      title: monthAt(o, monthStartDay).label,
      checked: filters.monthOffset === o,
      onPress: () => setFilters({ monthOffset: o }),
    })),
  ];
  const accountItems: MenuItem[] = [
    { title: 'All accounts', checked: !filters.accountIds.length, onPress: () => setFilters({ accountIds: [] }) },
    'separator',
    ...accounts.map((a) => ({
      title: accountLabel(a.name, a.last4),
      checked: filters.accountIds[0] === a.id,
      onPress: () => setFilters({ accountIds: [a.id] }),
    })),
  ];
  const categoryItems: MenuItem[] = [
    { title: 'All categories', checked: !filters.categoryIds.length, onPress: () => setFilters({ categoryIds: [] }) },
    { title: 'Uncategorised', checked: filters.categoryIds[0] === null, onPress: () => setFilters({ categoryIds: [null] }) },
    'separator',
    ...allCats
      .filter((c) => !c.parentId)
      .map((c) => ({ title: c.name, checked: filters.categoryIds[0] === c.id, onPress: () => setFilters({ categoryIds: [c.id] }) })),
  ];
  const typeItems: MenuItem[] = [
    { title: 'All types', checked: !filters.types.length, onPress: () => setFilters({ types: [] }) },
    { title: 'Expenses', checked: filters.types[0] === 'expense', onPress: () => setFilters({ types: ['expense'] }) },
    { title: 'Income', checked: filters.types[0] === 'income', onPress: () => setFilters({ types: ['income'] }) },
    { title: 'Transfers', checked: filters.types[0] === 'transfer', onPress: () => setFilters({ types: ['transfer'] }) },
  ];
  const anyFilter = filters.accountIds.length || filters.categoryIds.length || filters.types.length;

  const header = (
    <View style={{ paddingTop: 6, paddingBottom: 8 }}>
      <LargeTitle title={mode === 'search' ? 'Search' : 'Activity'} style={{ paddingHorizontal: 20 }} />
      <View style={[styles.search, { backgroundColor: colors.fill }]}>
        <Icon name="magnifyingglass" size={17} color={colors.secondary} />
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search transactions"
          placeholderTextColor={colors.secondary}
          autoFocus={mode === 'search'}
          returnKeyType="search"
          clearButtonMode="while-editing"
          style={[type.body, styles.searchInput, { color: colors.label }]}
          accessibilityLabel="Search transactions"
        />
      </View>
      <View style={styles.chips}>
        <Menu items={monthItems}>{(open) => <FilterChip label={monthLabel} active={filters.monthOffset !== 0 && mode === 'activity'} onPress={open} />}</Menu>
        <Menu items={accountItems}>{(open) => <FilterChip label={account ? account.name : 'All accounts'} active={!!account} onPress={open} />}</Menu>
        <Menu items={categoryItems}>{(open) => <FilterChip label={category ?? 'All categories'} active={!!category} onPress={open} />}</Menu>
        <Menu items={typeItems}>{(open) => <FilterChip label={typeLabel ?? 'All types'} active={!!typeLabel} onPress={open} />}</Menu>
      </View>
    </View>
  );

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <TransactionDayList
        items={items}
        header={header}
        onScroll={onScroll}
        style={{ marginTop: titleTop - 6 }}
        contentBottom={bottom}
        empty={
          loaded ? (
            search || anyFilter ? (
              <EmptyState icon="magnifyingglass" title="No results" message="Try a different search or clear the filters." />
            ) : (
              <EmptyState icon="list.bullet.rectangle.portrait" title="Nothing here yet" message="Transactions you add show up here, grouped by day." />
            )
          ) : null
        }
      />
      <TopBar
        title={mode === 'search' ? 'Search' : 'Activity'}
        scrollY={scrollY}
        trailing={
          anyFilter ? (
            <GlassGroup>
              <GlassButton
                icon="line.3.horizontal.decrease"
                tint={colors.accent}
                accessibilityLabel="Clear filters"
                onPress={() => setFilters({ accountIds: [], categoryIds: [], types: [] })}
              />
            </GlassGroup>
          ) : null
        }
      />
      {mode === 'activity' ? <AddButton /> : null}
    </View>
  );
}

function FilterChip({ label, active, onPress }: { label: string; active?: boolean; onPress: () => void }) {
  const { colors } = useTheme();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      style={[styles.chip, { backgroundColor: active ? colors.accent : colors.card }]}
    >
      <Text style={[type.subhead, { color: active ? '#FFFFFF' : colors.label }]} numberOfLines={1}>
        {label}
      </Text>
      <Icon name="chevron.down" size={11} color={active ? '#FFFFFF' : colors.secondary} weight="bold" />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  search: {
    marginTop: 10,
    marginHorizontal: 16,
    height: 39,
    borderRadius: 12,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    gap: 6,
  },
  searchInput: { flex: 1, paddingVertical: 0 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, paddingHorizontal: 16, marginTop: 12 },
  chip: { height: 31, borderRadius: 16, paddingHorizontal: 12, flexDirection: 'row', alignItems: 'center', gap: 5 },
});
