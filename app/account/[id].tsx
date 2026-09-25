import { router, useLocalSearchParams } from 'expo-router';
import { Alert, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { AccountCard } from '@/features/accounts/AccountCard';
import { removeAccount, setAccountArchived } from '@/features/accounts/mutations';
import { accountsWithBalance } from '@/features/accounts/queries';
import { listTransactions } from '@/features/transactions/list';
import { TransactionDayList } from '@/features/transactions/TransactionDayList';
import { useQuery } from '@/hooks/useQuery';
import { useToast } from '@/stores/toast';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { EmptyState } from '@/ui/EmptyState';
import { GlassButton, GlassGroup } from '@/ui/Glass';
import { Menu } from '@/ui/Menu';
import { TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';

export default function AccountDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { colors } = useTheme();
  const toast = useToast((s) => s.show);
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const { data: accounts } = useQuery(() => accountsWithBalance(appDb, { includeArchived: true }), [], []);
  const { data: items, loaded } = useQuery(() => listTransactions(appDb, { accountIds: [id] }), [id], []);
  const account = accounts.find((a) => a.id === id);

  const remove = () =>
    Alert.alert(
      `Delete ${account?.name}?`,
      items.length ? 'This account has transactions, so it will be archived instead. You can restore it later.' : 'This can’t be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: items.length ? 'Archive' : 'Delete',
          style: 'destructive',
          onPress: async () => {
            const result = await removeAccount(appDb, id);
            toast({
              message: result === 'archived' ? 'Account archived' : 'Account deleted',
              ...(result === 'archived' ? { actionLabel: 'Undo', onAction: () => setAccountArchived(appDb, id, false) } : {}),
            });
            router.back();
          },
        },
      ],
    );

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      {account ? (
        <TransactionDayList
          items={items}
          onScroll={onScroll}
          contentBottom={60}
          header={
            <View style={{ paddingTop: top, paddingHorizontal: 16, paddingBottom: 6 }}>
              <AccountCard account={account} balance={account.balance} showHeaderBalance={false} />
              {account.archivedAt ? (
                <Text style={[type.footnote, { color: colors.secondary, marginTop: 10, textAlign: 'center' }]}>
                  Archived. Hidden from totals and pickers.
                </Text>
              ) : null}
            </View>
          }
          empty={loaded ? <EmptyState icon="list.bullet.rectangle.portrait" title="No transactions" message="Nothing has been added to this account yet." /> : null}
        />
      ) : null}
      <TopBar
        title={account?.name}
        scrollY={scrollY}
        leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />}
        trailing={
          account ? (
            <GlassGroup>
              <GlassButton icon="pencil" accessibilityLabel="Edit account" onPress={() => router.push({ pathname: '/account-form', params: { id } })} />
              <Menu
                items={[
                  {
                    title: 'Transfer From',
                    icon: 'arrow.up.right',
                    onPress: () => router.push({ pathname: '/add', params: { type: 'transfer', from: id } }),
                  },
                  {
                    title: 'Transfer To',
                    icon: 'arrow.down.left',
                    onPress: () => router.push({ pathname: '/add', params: { type: 'transfer', to: id } }),
                  },
                  'separator',
                  account.archivedAt
                    ? { title: 'Unarchive', icon: 'archivebox', onPress: () => setAccountArchived(appDb, id, false) }
                    : { title: 'Archive', icon: 'archivebox', onPress: () => setAccountArchived(appDb, id, true) },
                  { title: 'Delete Account', icon: 'trash', destructive: true, onPress: remove },
                ]}
              >
                {(open) => <GlassButton icon="ellipsis" accessibilityLabel="More" onPress={open} />}
              </Menu>
            </GlassGroup>
          ) : null
        }
      />
    </View>
  );
}
