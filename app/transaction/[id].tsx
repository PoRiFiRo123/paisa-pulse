import { format, isToday } from 'date-fns';
import { Link, router, useLocalSearchParams } from 'expo-router';
import { Platform, ScrollView, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { listTransactions } from '@/features/transactions/list';
import { useTransactionActions } from '@/features/transactions/useTransactionActions';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { accountLabel, relativeWhen } from '@/lib/format';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon, transactionVisual } from '@/ui/CategoryIcon';
import { EmptyState } from '@/ui/EmptyState';
import { GlassButton, GlassGroup } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { Menu } from '@/ui/Menu';
import { TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';
import { transactionTitle } from '@/ui/TransactionRow';

const SOURCE_LABEL: Record<string, string> = {
  manual: 'Added manually',
  notification: 'Captured from a notification',
  sms: 'Captured from SMS',
  shortcut: 'Added with Shortcuts',
  import: 'Imported from a statement',
};

export default function TransactionDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { colors } = useTheme();
  const money = useMoney();
  const actions = useTransactionActions();
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const { data, loaded } = useQuery(() => listTransactions(appDb, { id }), [id], []);
  const t = data[0];

  const back = <GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />;

  if (!t) {
    return (
      <View style={[styles.fill, { backgroundColor: colors.background }]}>
        {loaded ? <EmptyState icon="trash" title="Transaction deleted" /> : null}
        <TopBar leading={back} />
      </View>
    );
  }

  const visual = transactionVisual(t);
  const typeColor = t.type === 'expense' ? colors.expense : t.type === 'income' ? colors.income : colors.accent;
  const typeName = { expense: 'Expense', income: 'Income', transfer: 'Transfer' }[t.type];
  const square = (icon: string, color: string) => <CategoryIcon icon={icon} color={color} size={30} square />;
  const edited = t.updatedAt - t.createdAt > 1000 ? ` · Edited ${relativeWhen(t.updatedAt).toLowerCase()}` : '';
  const remove = async () => {
    await actions.remove(t.id);
    router.back();
  };

  return (
    <View style={[styles.fill, { backgroundColor: colors.background }]}>
      <ScrollView
        onScroll={onScroll}
        scrollEventThrottle={16}
        contentInsetAdjustmentBehavior="never"
        contentContainerStyle={{ paddingTop: top + 10, paddingBottom: 60 }}
      >
        <View style={styles.hero}>
          {Platform.OS === 'ios' ? (
            // The tapped row zooms into this icon (iOS 18+).
            <Link.AppleZoomTarget>
              <CategoryIcon icon={visual.icon} color={visual.color} size={72} />
            </Link.AppleZoomTarget>
          ) : (
            <CategoryIcon icon={visual.icon} color={visual.color} size={72} />
          )}
          <Text style={[type.title2, { color: colors.label, marginTop: 14 }]} numberOfLines={2}>
            {transactionTitle(t)}
          </Text>
          <Text style={[type.amount, { color: t.type === 'income' ? colors.income : colors.label }]} adjustsFontSizeToFit numberOfLines={1}>
            {money.signed(t.amount, t.type)}
          </Text>
          <View style={[styles.pill, { backgroundColor: `${typeColor}1F` }]}>
            <View style={[styles.dot, { backgroundColor: typeColor }]} />
            <Text style={[type.footnote, { color: typeColor, fontWeight: '600' }]}>{typeName}</Text>
          </View>
        </View>

        <InsetGroup style={{ marginTop: 26 }} dividerInset={58}>
          {t.type === 'transfer' ? (
            <GroupRow title="From" value={accountLabel(t.accountName, t.accountLast4)} leading={square('arrow.up.right', colors.expense)} height={56} />
          ) : (
            <GroupRow
              title="Category"
              value={t.categoryName ? (t.parentCategoryName ? `${t.parentCategoryName} › ${t.categoryName}` : t.categoryName) : 'Uncategorised'}
              leading={square('tag.fill', visual.color)}
              height={56}
              onPress={() => actions.changeCategory(t.id)}
            />
          )}
          {t.type === 'transfer' ? (
            <GroupRow title="To" value={accountLabel(t.toAccountName, t.toAccountLast4)} leading={square('arrow.down.left', colors.income)} height={56} />
          ) : (
            <GroupRow title="Account" value={accountLabel(t.accountName, t.accountLast4)} leading={square('creditcard.fill', t.accountColor)} height={56} />
          )}
          <GroupRow title="Date" value={format(t.occurredAt, 'EEE, d MMM yyyy')} leading={square('calendar', '#FF3B30')} height={56} />
          <GroupRow title="Time" value={format(t.occurredAt, 'h:mm a')} leading={square('clock', '#FF9500')} height={56} />
          <GroupRow title="Note" value={t.note ?? '—'} leading={square('note.text', '#FFB800')} height={56} />
        </InsetGroup>
        <Text style={[type.footnote, styles.footnote, { color: colors.secondary }]}>
          {SOURCE_LABEL[t.source] ?? 'Added'} {isToday(t.createdAt) ? 'today' : `on ${format(t.createdAt, 'd MMM yyyy')}`}
          {edited}
        </Text>

        <InsetGroup style={{ marginTop: 22 }} dividerInset={48}>
          <GroupRow
            title="Duplicate"
            tinted
            leading={<Icon name="doc.on.doc" size={18} color={colors.accent} />}
            height={49}
            onPress={() => actions.duplicate(t.id)}
          />
          <GroupRow
            title="Delete Transaction"
            destructive
            leading={<Icon name="trash" size={18} color={colors.expense} />}
            height={49}
            onPress={remove}
          />
        </InsetGroup>
      </ScrollView>

      <TopBar
        title={transactionTitle(t)}
        scrollY={scrollY}
        leading={back}
        trailing={
          <GlassGroup>
            <GlassButton icon="pencil" accessibilityLabel="Edit" onPress={() => actions.edit(t.id)} />
            <GlassButton icon="square.and.arrow.up" accessibilityLabel="Share" onPress={() => actions.share(t)} />
            <Menu
              items={[
                { title: 'Edit', icon: 'pencil', onPress: () => actions.edit(t.id) },
                { title: 'Duplicate', icon: 'doc.on.doc', onPress: () => actions.duplicate(t.id) },
                ...(t.type !== 'transfer' ? [{ title: 'Change Category', icon: 'tag', onPress: () => actions.changeCategory(t.id) }] : []),
                { title: 'Share', icon: 'square.and.arrow.up', onPress: () => actions.share(t) },
                'separator',
                { title: 'Delete', icon: 'trash', destructive: true, onPress: remove },
              ]}
            >
              {(open) => <GlassButton icon="ellipsis" accessibilityLabel="More actions" onPress={open} />}
            </Menu>
          </GlassGroup>
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  hero: { alignItems: 'center', paddingHorizontal: 24, gap: 4 },
  pill: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 10, height: 26, borderRadius: 13, marginTop: 8 },
  dot: { width: 8, height: 8, borderRadius: 4 },
  footnote: { paddingHorizontal: 32, marginTop: 8 },
});
