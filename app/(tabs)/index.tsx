import { router, useScrollToTop } from 'expo-router';
import { useMemo, useRef } from 'react';
import { FlatList, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';

import { appDb } from '@/db/client';
import { HeroCard } from '@/features/home/HeroCard';
import { listTransactions, topCategories } from '@/features/transactions/list';
import { TransactionListRow } from '@/features/transactions/TransactionListRow';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { monthAt } from '@/lib/months';
import { usePrefs } from '@/stores/prefs';
import { useUi } from '@/stores/ui';
import { UNCATEGORISED_COLOR } from '@/theme/tokens';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { AddButton } from '@/ui/AddButton';
import { Aurora } from '@/ui/Aurora';
import { CategoryCapsule } from '@/ui/CategoryCapsule';
import { EmptyState } from '@/ui/EmptyState';
import { GlassButton, GlassGroup } from '@/ui/Glass';
import { InsetGroup } from '@/ui/InsetGroup';
import { Menu, type MenuItem } from '@/ui/Menu';
import { LargeTitle, TopBar, useBottomSpace, useScrollHeader, useTitleTop } from '@/ui/Screen';

const MONTHS_BACK = 12;

export default function HomeScreen() {
  const scrollRef = useRef<ScrollView>(null);
  useScrollToTop(scrollRef);
  const { colors, dark } = useTheme();
  const money = useMoney();
  const { width } = useWindowDimensions();
  const monthStartDay = usePrefs((s) => s.monthStartDay);
  const offset = useUi((s) => s.homeMonthOffset);
  const setOffset = useUi((s) => s.setHomeMonthOffset);
  const setActivity = useUi((s) => s.setActivity);
  const { scrollY, onScroll } = useScrollHeader();
  const titleTop = useTitleTop();
  const bottom = useBottomSpace();
  const pager = useRef<FlatList<number>>(null);

  // Pages run oldest → newest so swiping right goes back in time, like Wallet.
  const pages = useMemo(() => Array.from({ length: MONTHS_BACK }, (_, i) => MONTHS_BACK - 1 - i), []);
  const month = monthAt(offset, monthStartDay);

  const { data: top } = useQuery(() => topCategories(appDb, month), [month.start], []);
  const { data: recent, loaded } = useQuery(() => listTransactions(appDb, { limit: 5 }), [], []);

  const jumpTo = (o: number) => {
    setOffset(o);
    pager.current?.scrollToIndex({ index: MONTHS_BACK - 1 - o, animated: true });
  };
  const monthItems: MenuItem[] = pages
    .slice()
    .reverse()
    .map((o) => ({ title: monthAt(o, monthStartDay).label, checked: o === offset, onPress: () => jumpTo(o) }));

  const openCategory = (categoryId: string | null) => {
    setActivity({ monthOffset: offset, categoryIds: [categoryId], accountIds: [], types: [] });
    router.navigate('/activity');
  };

  const titleColor = dark ? colors.label : '#FFFFFF';

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView
        ref={scrollRef}
        onScroll={onScroll}
        scrollEventThrottle={16}
        contentInsetAdjustmentBehavior="never"
        contentContainerStyle={{ paddingTop: titleTop, paddingBottom: bottom }}
      >
        <Aurora />
        <Menu items={monthItems}>
          {(open) => <LargeTitle title={month.name} color={titleColor} chevron onPress={open} />}
        </Menu>

        <FlatList
          ref={pager}
          horizontal
          pagingEnabled
          data={pages}
          keyExtractor={(o) => String(o)}
          showsHorizontalScrollIndicator={false}
          initialScrollIndex={MONTHS_BACK - 1 - offset}
          getItemLayout={(_, index) => ({ length: width, offset: width * index, index })}
          onMomentumScrollEnd={(e) => {
            const index = Math.round(e.nativeEvent.contentOffset.x / width);
            setOffset(MONTHS_BACK - 1 - index);
          }}
          style={{ marginTop: 15 }}
          renderItem={({ item: o }) => (
            // Bottom padding keeps the card's shadow inside the pager, which clips its children.
            <View style={{ width, paddingHorizontal: 16, paddingBottom: 18 }}>
              <HeroCard month={monthAt(o, monthStartDay)} previous={monthAt(o + 1, monthStartDay)} isCurrent={o === 0} />
            </View>
          )}
        />
        <MonthDots count={MONTHS_BACK} active={MONTHS_BACK - 1 - offset} color={titleColor} />

        {loaded && recent.length === 0 ? (
          <EmptyState
            icon="indianrupeesign.circle.fill"
            title="No transactions yet"
            message="Log your first spend. It takes three taps."
            actionLabel="Add your first expense"
            onAction={() => router.push('/add')}
          />
        ) : (
          <>
            <SectionHeader title="Top categories" detail={offset === 0 ? 'This month' : month.name} />
            {top.length ? (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0 }} contentContainerStyle={styles.capsules}>
                {top.map((t) => (
                  <CategoryCapsule
                    key={t.categoryId ?? 'none'}
                    name={t.category?.name ?? 'Uncategorised'}
                    icon={t.category?.icon ?? 'questionmark'}
                    color={t.category?.color ?? UNCATEGORISED_COLOR}
                    amount={money.amount(t.total)}
                    onPress={() => openCategory(t.categoryId)}
                  />
                ))}
              </ScrollView>
            ) : (
              <Text style={[type.subhead, styles.muted, { color: colors.secondary }]}>No spending in {month.name} yet.</Text>
            )}

            <SectionHeader title="Recent" action="See all" onAction={() => router.navigate('/activity')} />
            <InsetGroup dividerInset={66}>
              {recent.map((t) => (
                <TransactionListRow key={t.id} item={t} />
              ))}
            </InsetGroup>
          </>
        )}
      </ScrollView>

      <TopBar
        title={month.name}
        scrollY={scrollY}
        trailing={
          <GlassGroup>
            <Menu items={monthItems}>
              {(open) => <GlassButton icon="calendar" accessibilityLabel="Choose month" onPress={open} />}
            </Menu>
            <Menu
              items={[
                { title: 'Categories', icon: 'tag', onPress: () => router.push('/categories') },
                { title: 'Add Account', icon: 'creditcard', onPress: () => router.push('/account-form') },
                { title: 'Transfer', icon: 'arrow.left.arrow.right', onPress: () => router.push({ pathname: '/add', params: { type: 'transfer' } }) },
                'separator',
                { title: money.hidden ? 'Show Amounts' : 'Hide Amounts', icon: 'eye.slash.fill', onPress: () => usePrefs.getState().set('hideAmounts', !money.hidden) },
              ]}
            >
              {(open) => <GlassButton icon="ellipsis" accessibilityLabel="More" onPress={open} />}
            </Menu>
          </GlassGroup>
        }
      />
      <AddButton />
    </View>
  );
}

function SectionHeader({ title, detail, action, onAction }: { title: string; detail?: string; action?: string; onAction?: () => void }) {
  const { colors } = useTheme();
  return (
    <View style={styles.sectionHeader}>
      <Text style={[type.title3, { color: colors.label }]} accessibilityRole="header">
        {title}
      </Text>
      {action ? (
        <Text onPress={onAction} accessibilityRole="button" style={[type.subhead, { color: colors.accent }]}>
          {action}
        </Text>
      ) : (
        <Text style={[type.subhead, { color: colors.secondary }]}>{detail}</Text>
      )}
    </View>
  );
}

/** Page indicator under the hero card, windowed to 5 dots. */
function MonthDots({ count, active, color }: { count: number; active: number; color: string }) {
  const windowSize = Math.min(5, count);
  const first = Math.min(Math.max(active - windowSize + 1, 0), count - windowSize);
  return (
    <View style={styles.dots} accessibilityElementsHidden>
      {Array.from({ length: windowSize }, (_, i) => (
        <View key={i} style={[styles.dot, { backgroundColor: color, opacity: first + i === active ? 0.9 : 0.35 }]} />
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  capsules: { paddingHorizontal: 16, gap: 10 },
  muted: { paddingHorizontal: 20 },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    marginTop: 26,
    marginBottom: 12,
  },
  dots: { flexDirection: 'row', gap: 6, alignSelf: 'center', marginTop: -6 },
  dot: { width: 6, height: 6, borderRadius: 3 },
});
