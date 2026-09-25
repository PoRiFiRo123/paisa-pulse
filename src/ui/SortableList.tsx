import * as Haptics from 'expo-haptics';
import { type ReactNode, useEffect } from 'react';
import { StyleSheet, View } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, {
  type SharedValue,
  useAnimatedReaction,
  useAnimatedStyle,
  useSharedValue,
  withSpring,
} from 'react-native-reanimated';
import { scheduleOnRN } from 'react-native-worklets';

import { useTheme } from '@/theme/useTheme';

import { Icon } from './Icon';

type Positions = Record<string, number>;

function toPositions(keys: string[]): Positions {
  return Object.fromEntries(keys.map((k, i) => [k, i]));
}

/**
 * Drag-to-reorder list with fixed-height rows, in an inset grouped card.
 * Drag a row by its handle; VoiceOver users get "Move up" / "Move down" actions.
 */
export function SortableList<T>({
  data,
  keyOf,
  rowHeight = 56,
  renderRow,
  onReorder,
}: {
  data: T[];
  keyOf: (item: T) => string;
  rowHeight?: number;
  renderRow: (item: T) => ReactNode;
  onReorder: (keys: string[]) => void;
}) {
  const { colors } = useTheme();
  const keys = data.map(keyOf);
  const positions = useSharedValue<Positions>(toPositions(keys));
  const keyString = keys.join('|');

  // Resync when the data changes from outside (e.g. after the reorder is saved).
  useEffect(() => {
    positions.set(toPositions(keyString ? keyString.split('|') : []));
  }, [keyString, positions]);

  const commit = (next: Positions) => {
    const ordered = Object.keys(next).sort((a, b) => next[a] - next[b]);
    if (ordered.join('|') !== keyString) onReorder(ordered);
  };
  const moveBy = (key: string, delta: number) => {
    const from = positions.get()[key];
    const to = Math.min(Math.max(from + delta, 0), keys.length - 1);
    if (from === to) return;
    const next = { ...positions.get() };
    for (const k of Object.keys(next)) if (next[k] === to) next[k] = from;
    next[key] = to;
    positions.set(next);
    commit(next);
  };

  return (
    <View style={[styles.card, { height: keys.length * rowHeight, backgroundColor: colors.card }]}>
      {data.map((item) => {
        const key = keyOf(item);
        return (
          <SortableRow
            key={key}
            id={key}
            count={keys.length}
            rowHeight={rowHeight}
            positions={positions}
            onDrop={commit}
            onMove={(d) => moveBy(key, d)}
          >
            {renderRow(item)}
          </SortableRow>
        );
      })}
    </View>
  );
}

function SortableRow({
  id,
  count,
  rowHeight,
  positions,
  onDrop,
  onMove,
  children,
}: {
  id: string;
  count: number;
  rowHeight: number;
  positions: SharedValue<Positions>;
  onDrop: (p: Positions) => void;
  onMove: (delta: number) => void;
  children: ReactNode;
}) {
  const { colors } = useTheme();
  const dragging = useSharedValue(false);
  const top = useSharedValue((positions.get()[id] ?? 0) * rowHeight);
  const startTop = useSharedValue(0);

  // Follow position changes when this row isn't the one being dragged.
  useAnimatedReaction(
    () => positions.get()[id],
    (index) => {
      if (!dragging.get() && index !== undefined) top.set(withSpring(index * rowHeight, { damping: 20, stiffness: 220 }));
    },
  );

  const tick = () => Haptics.selectionAsync().catch(() => {});
  const pickUp = () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => {});

  const pan = Gesture.Pan()
    .onStart(() => {
      dragging.set(true);
      startTop.set(top.get());
      scheduleOnRN(pickUp);
    })
    .onUpdate((e) => {
      top.set(Math.min(Math.max(startTop.get() + e.translationY, 0), (count - 1) * rowHeight));
      const to = Math.round(top.get() / rowHeight);
      const from = positions.get()[id];
      if (to !== from) {
        const next = { ...positions.get() };
        for (const k of Object.keys(next)) if (next[k] === to) next[k] = from;
        next[id] = to;
        positions.set(next);
        scheduleOnRN(tick);
      }
    })
    .onFinalize(() => {
      dragging.set(false);
      top.set(withSpring(positions.get()[id] * rowHeight, { damping: 20, stiffness: 220 }));
      scheduleOnRN(onDrop, positions.get());
    });

  const style = useAnimatedStyle(() => ({
    top: top.get(),
    zIndex: dragging.get() ? 10 : 0,
    transform: [{ scale: withSpring(dragging.get() ? 1.03 : 1) }],
    shadowOpacity: withSpring(dragging.get() ? 0.18 : 0),
  }));
  const dividerStyle = useAnimatedStyle(() => ({ opacity: positions.get()[id] === 0 || dragging.get() ? 0 : 1 }));

  return (
    <Animated.View
      style={[styles.row, { height: rowHeight, backgroundColor: colors.card }, style]}
      accessible
      accessibilityActions={[
        { name: 'moveUp', label: 'Move up' },
        { name: 'moveDown', label: 'Move down' },
      ]}
      onAccessibilityAction={(e) => onMove(e.nativeEvent.actionName === 'moveUp' ? -1 : 1)}
    >
      <Animated.View style={[styles.divider, { backgroundColor: colors.rowDivider }, dividerStyle]} />
      <View style={{ flex: 1 }}>{children}</View>
      <GestureDetector gesture={pan}>
        <View style={styles.handle} hitSlop={8} accessibilityLabel="Drag to reorder">
          <Icon name="line.3.horizontal" size={20} color={colors.secondary} />
        </View>
      </GestureDetector>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  card: { marginHorizontal: 16, borderRadius: 22 },
  row: {
    position: 'absolute',
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 22,
    shadowColor: '#000',
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
  },
  divider: { position: 'absolute', top: 0, left: 58, right: 0, height: StyleSheet.hairlineWidth },
  handle: { width: 52, height: '100%', alignItems: 'center', justifyContent: 'center' },
});
