import { router, useScrollToTop } from 'expo-router';
import { useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { AccountCard, CARD_HEIGHT, CARD_PEEK } from '@/features/accounts/AccountCard';
import { computeNetWorth } from '@/features/accounts/balance';
import { reorderAccounts } from '@/features/accounts/mutations';
import { accountIcon, daysUntilDay } from '@/features/accounts/presentation';
import { accountsWithBalance } from '@/features/accounts/queries';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { accountLabel } from '@/lib/format';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { EmptyState } from '@/ui/EmptyState';
import { GlassButton, GlassGroup } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { LargeTitle, TopBar, useBottomSpace, useScrollHeader, useTitleTop } from '@/ui/Screen';
import { SortableList } from '@/ui/SortableList';

export default function AccountsScreen() {
  const scrollRef = useRef<ScrollView>(null);
  useScrollToTop(scrollRef);
  const { colors } = useTheme();
  const money = useMoney();
  const { scrollY, onScroll } = useScrollHeader();
  const titleTop = useTitleTop();
  const bottom = useBottomSpace();
  const [reordering, setReordering] = useState(false);
  const { data: all, loaded } = useQuery(() => accountsWithBalance(appDb, { includeArchived: true }), [], []);

  const active = all.filter((a) => a.archivedAt === null);
  const archived = all.filter((a) => a.archivedAt !== null);
  const netWorth = computeNetWorth(active);
  const counted = active.filter((a) => !a.excludeFromTotals).length;
  const payFrom = active.find((a) => a.type === 'bank') ?? active.find((a) => a.type !== 'card');
  const bills = active
    .filter((a) => a.type === 'card' && a.dueDay && a.balance < 0)
    .map((a) => ({ account: a, ...daysUntilDay(a.dueDay!) }))
    .sort((x, y) => x.days - y.days);

  const open = (id: string) => router.push({ pathname: '/account/[id]', params: { id } });

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView
        ref={scrollRef}
        onScroll={onScroll}
        scrollEventThrottle={16}
        contentInsetAdjustmentBehavior="never"
        contentContainerStyle={{ paddingTop: titleTop, paddingBottom: bottom }}
      >
        <LargeTitle title="Accounts" />

        {loaded && active.length === 0 ? (
          <EmptyState
            icon="creditcard"
            title="No accounts yet"
            message="Add your bank accounts, cards, cash and wallets."
            actionLabel="Add Account"
            onAction={() => router.push('/account-form')}
          />
        ) : (
          <>
            <View style={[styles.netWorth, { backgroundColor: colors.card }]}>
              <Text style={[type.subhead, { color: colors.secondary }]}>Net worth</Text>
              <Text style={[type.amountMedium, { color: netWorth < 0 ? colors.expense : colors.label }]} adjustsFontSizeToFit numberOfLines={1}>
                {money.balance(netWorth)}
              </Text>
              <Text style={[type.footnote, { color: colors.secondary }]}>
                Across {counted} account{counted === 1 ? '' : 's'} · updated just now
              </Text>
            </View>

            {reordering ? (
              <View style={{ marginTop: 22 }}>
                <SortableList
                  data={active}
                  keyOf={(a) => a.id}
                  onReorder={(ids) => reorderAccounts(appDb, ids)}
                  renderRow={(a) => (
                    <View style={styles.sortRow}>
                      <CategoryIcon icon={accountIcon(a.type)} color={a.color} size={30} square />
                      <Text style={[type.body, { color: colors.label, flex: 1 }]} numberOfLines={1}>
                        {accountLabel(a.name, a.last4)}
                      </Text>
                    </View>
                  )}
                />
              </View>
            ) : (
              <View style={[styles.stack, { height: Math.max(0, active.length - 1) * CARD_PEEK + CARD_HEIGHT }]}>
                {active.map((a, i) => (
                  <View key={a.id} style={[styles.stacked, { top: i * CARD_PEEK }]}>
                    <AccountCard account={a} balance={a.balance} onPress={() => open(a.id)} showHeaderBalance={i < active.length - 1} />
                  </View>
                ))}
              </View>
            )}

            {bills.map(({ account, days }) => (
              <Pressable
                key={account.id}
                accessibilityRole="button"
                onPress={() =>
                  router.push({
                    pathname: '/add',
                    params: { type: 'transfer', from: payFrom?.id, to: account.id, amount: String(-account.balance) },
                  })
                }
                style={({ pressed }) => [styles.bill, { backgroundColor: colors.card, opacity: pressed ? 0.7 : 1 }]}
              >
                <CategoryIcon icon="bell.fill" color="#FF9500" size={32} />
                <View style={{ flex: 1 }}>
                  <Text style={[type.headline, { color: colors.label }]} numberOfLines={1}>
                    {account.name} bill {days === 0 ? 'due today' : `due in ${days} day${days === 1 ? '' : 's'}`}
                  </Text>
                  <Text style={[type.footnote, { color: colors.secondary }]} numberOfLines={1}>
                    {money.amount(-account.balance)}
                    {payFrom ? ` · Pay from ${accountLabel(payFrom.name, payFrom.last4)}` : ''}
                  </Text>
                </View>
                <Icon name="chevron.right" size={13} color={colors.secondary} weight="semibold" />
              </Pressable>
            ))}

            {archived.length ? (
              <>
                <GroupHeader title="Archived" style={{ marginTop: 12 }} />
                <InsetGroup dividerInset={58}>
                  {archived.map((a) => (
                    <GroupRow
                      key={a.id}
                      title={accountLabel(a.name, a.last4)}
                      value={money.balance(a.balance)}
                      leading={<CategoryIcon icon={accountIcon(a.type)} color={a.color} size={30} square />}
                      chevron
                      onPress={() => open(a.id)}
                    />
                  ))}
                </InsetGroup>
              </>
            ) : null}
          </>
        )}
      </ScrollView>

      <TopBar
        title="Accounts"
        scrollY={scrollY}
        trailing={
          <GlassGroup>
            {active.length > 1 ? (
              <GlassButton
                icon={reordering ? 'checkmark' : 'arrow.up.arrow.down'}
                tint={reordering ? colors.accent : undefined}
                accessibilityLabel={reordering ? 'Done reordering' : 'Reorder accounts'}
                onPress={() => setReordering(!reordering)}
              />
            ) : null}
            <GlassButton icon="plus" accessibilityLabel="Add account" onPress={() => router.push('/account-form')} />
          </GlassGroup>
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  netWorth: { marginHorizontal: 16, marginTop: 15, borderRadius: 22, padding: 18, gap: 2 },
  stack: { marginHorizontal: 16, marginTop: 22 },
  stacked: { position: 'absolute', left: 0, right: 0 },
  bill: {
    marginHorizontal: 16,
    marginTop: 18,
    borderRadius: 22,
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  sortRow: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12, paddingLeft: 16 },
});
