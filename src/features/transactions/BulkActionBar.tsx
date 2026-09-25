import * as Haptics from 'expo-haptics';
import { Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, { FadeInDown, FadeOutDown } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { appDb } from '@/db/client';
import { accountIcon } from '@/features/accounts/presentation';
import { accountsWithBalance } from '@/features/accounts/queries';
import { categoriesByKind } from '@/features/categories/queries';
import { useQuery } from '@/hooks/useQuery';
import { accountLabel } from '@/lib/format';
import { useSelection } from '@/stores/selection';
import { useToast } from '@/stores/toast';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { GlassSurface } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { Menu, type MenuItem } from '@/ui/Menu';

import { type BulkSnapshot, bulkDelete, bulkSetAccount, bulkSetCategory, restoreSnapshot } from './bulk';

/** Floating glass bar for multi-select: change category, move account, delete (all undoable). */
export function BulkActionBar() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const ids = useSelection((s) => s.ids);
  const clear = useSelection((s) => s.clear);
  const toast = useToast((s) => s.show);
  const { data } = useQuery(
    async () => ({
      accounts: await accountsWithBalance(appDb),
      expense: await categoriesByKind(appDb, 'expense'),
      income: await categoriesByKind(appDb, 'income'),
    }),
    [],
    { accounts: [], expense: [], income: [] },
  );

  const run = async (task: Promise<{ undo: BulkSnapshot; count: number }>, message: (n: number) => string, warn = false) => {
    const { undo, count } = await task;
    Haptics.notificationAsync(warn ? Haptics.NotificationFeedbackType.Warning : Haptics.NotificationFeedbackType.Success).catch(() => {});
    clear();
    toast(
      count
        ? { message: message(count), actionLabel: 'Undo', onAction: () => restoreSnapshot(appDb, undo) }
        : { message: 'Nothing to change for these transactions' },
    );
  };
  const plural = (n: number) => `${n} transaction${n === 1 ? '' : 's'}`;
  const setCategory = (id: string | null, name: string) =>
    run(bulkSetCategory(appDb, ids, id), (n) => `${plural(n)} moved to ${name}`);

  const categoryItems: MenuItem[] = [
    ...data.expense.filter((c) => !c.parentId).map((c) => ({ title: c.name, icon: c.icon, onPress: () => setCategory(c.id, c.name) })),
    'separator',
    ...data.income.filter((c) => !c.parentId).map((c) => ({ title: c.name, icon: c.icon, onPress: () => setCategory(c.id, c.name) })),
    'separator',
    { title: 'Uncategorised', icon: 'questionmark', onPress: () => setCategory(null, 'Uncategorised') },
  ];
  const accountItems: MenuItem[] = data.accounts.map((a) => ({
    title: accountLabel(a.name, a.last4),
    icon: accountIcon(a.type),
    onPress: () => run(bulkSetAccount(appDb, ids, a.id), (n) => `${plural(n)} moved to ${a.name}`),
  }));

  const disabled = ids.length === 0;
  const action = (icon: string, label: string, onPress: () => void, color = colors.accent) => (
    <Pressable
      disabled={disabled}
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={label}
      style={[styles.action, { opacity: disabled ? 0.35 : 1 }]}
    >
      <Icon name={icon} size={20} color={color} weight="semibold" />
      <Text style={[type.caption2, { color }]}>{label}</Text>
    </Pressable>
  );

  return (
    <Animated.View
      entering={FadeInDown.springify().damping(18)}
      exiting={FadeOutDown}
      style={[styles.wrap, { bottom: Platform.OS === 'ios' ? insets.bottom + 72 : 20 }]}
    >
      <GlassSurface radius={30} style={styles.bar}>
        <Text style={[type.headline, { color: colors.label, flex: 1 }]} accessibilityLiveRegion="polite">
          {ids.length ? `${ids.length} selected` : 'Select items'}
        </Text>
        <View style={styles.actions}>
          <Menu items={categoryItems}>{(open) => action('tag', 'Category', open)}</Menu>
          <Menu items={accountItems}>{(open) => action('creditcard', 'Account', open)}</Menu>
          {action('trash', 'Delete', () => run(bulkDelete(appDb, ids), (n) => `${plural(n)} deleted`, true), colors.expense)}
        </View>
      </GlassSurface>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  wrap: { position: 'absolute', left: 16, right: 16 },
  bar: { height: 60, flexDirection: 'row', alignItems: 'center', paddingLeft: 20, paddingRight: 8 },
  actions: { flexDirection: 'row', gap: 4 },
  action: { width: 64, height: 52, alignItems: 'center', justifyContent: 'center', gap: 2 },
});
