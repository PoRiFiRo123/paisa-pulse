import { Link } from 'expo-router';
import { memo, useRef } from 'react';
import { Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import ReanimatedSwipeable, { type SwipeableMethods } from 'react-native-gesture-handler/ReanimatedSwipeable';

import { useSelection } from '@/stores/selection';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { Icon } from '@/ui/Icon';
import { Menu } from '@/ui/Menu';
import { TransactionRow } from '@/ui/TransactionRow';

import type { TransactionItem } from './list';
import { useTransactionActions } from './useTransactionActions';

/**
 * A transaction row with native-feeling interactions:
 * swipe left → Delete, swipe right → Duplicate, tap → detail,
 * long-press → context menu (native with preview on iOS, glass menu on Android).
 */
export const TransactionListRow = memo(function TransactionListRow({
  item,
  showTime = true,
  selectable = false,
}: {
  item: TransactionItem;
  showTime?: boolean;
  /** Offer "Select" in the context menu to start multi-select (Activity only). */
  selectable?: boolean;
}) {
  const { colors } = useTheme();
  const actions = useTransactionActions();
  const swipe = useRef<SwipeableMethods>(null);

  const action = (label: string, icon: string, color: string, onPress: () => void) => (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={() => {
        swipe.current?.close();
        onPress();
      }}
      style={[styles.action, { backgroundColor: color }]}
    >
      <Icon name={icon} size={20} color="#FFFFFF" weight="semibold" />
      <Text style={[type.caption2, styles.actionText]}>{label}</Text>
    </Pressable>
  );

  const startSelection = useSelection((s) => s.start);

  // On iOS the Link handles the tap so the zoom transition can run.
  const row = (onLongPress?: () => void) => (
    <Pressable
      onPress={Platform.OS === 'ios' ? undefined : () => actions.open(item.id)}
      onLongPress={onLongPress}
      accessibilityRole="button"
      accessibilityHint="Swipe left to delete, right to duplicate"
      accessibilityActions={[
        { name: 'delete', label: 'Delete' },
        { name: 'duplicate', label: 'Duplicate' },
      ]}
      onAccessibilityAction={(e) =>
        e.nativeEvent.actionName === 'delete' ? actions.remove(item.id) : actions.duplicate(item.id)
      }
    >
      {({ pressed }) => (
        <>
          <TransactionRow item={item} showTime={showTime} />
          {pressed ? <View pointerEvents="none" style={[StyleSheet.absoluteFill, { backgroundColor: colors.fill }]} /> : null}
        </>
      )}
    </Pressable>
  );

  const content =
    Platform.OS === 'ios' ? (
      <Link href={{ pathname: '/transaction/[id]', params: { id: item.id } }} asChild>
        <Link.Trigger withAppleZoom>{row()}</Link.Trigger>
        <Link.Preview />
        <Link.Menu>
          {selectable ? <Link.MenuAction title="Select" icon="checkmark.circle" onPress={() => startSelection(item.id)} /> : null}
          <Link.MenuAction title="Edit" icon="pencil" onPress={() => actions.edit(item.id)} />
          <Link.MenuAction title="Duplicate" icon="doc.on.doc" onPress={() => actions.duplicate(item.id)} />
          {item.type !== 'transfer' ? (
            <Link.MenuAction title="Change Category" icon="tag" onPress={() => actions.changeCategory(item.id)} />
          ) : null}
          <Link.MenuAction title="Share" icon="square.and.arrow.up" onPress={() => actions.share(item)} />
          <Link.MenuAction title="Delete" icon="trash" destructive onPress={() => actions.remove(item.id)} />
        </Link.Menu>
      </Link>
    ) : (
      <Menu
        items={[
          ...(selectable ? [{ title: 'Select', icon: 'checkmark.circle', onPress: () => startSelection(item.id) }] : []),
          { title: 'Edit', icon: 'pencil', onPress: () => actions.edit(item.id) },
          { title: 'Duplicate', icon: 'doc.on.doc', onPress: () => actions.duplicate(item.id) },
          ...(item.type !== 'transfer'
            ? [{ title: 'Change Category', icon: 'tag', onPress: () => actions.changeCategory(item.id) }]
            : []),
          { title: 'Share', icon: 'square.and.arrow.up', onPress: () => actions.share(item) },
          'separator' as const,
          { title: 'Delete', icon: 'trash', destructive: true, onPress: () => actions.remove(item.id) },
        ]}
      >
        {(open) => row(open)}
      </Menu>
    );

  return (
    <ReanimatedSwipeable
      ref={swipe}
      friction={1.6}
      overshootFriction={8}
      rightThreshold={40}
      leftThreshold={40}
      renderRightActions={() => action('Delete', 'trash', colors.expense, () => actions.remove(item.id))}
      renderLeftActions={() => action('Duplicate', 'doc.on.doc', colors.accent, () => actions.duplicate(item.id))}
      containerStyle={{ backgroundColor: colors.card }}
    >
      {content}
    </ReanimatedSwipeable>
  );
});

const styles = StyleSheet.create({
  action: { width: 92, alignItems: 'center', justifyContent: 'center', gap: 4 },
  actionText: { color: '#FFFFFF', fontSize: 12 },
});
