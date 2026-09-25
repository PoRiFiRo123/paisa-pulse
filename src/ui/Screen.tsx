import type { ReactNode } from 'react';
import { Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, { interpolate, type SharedValue, useAnimatedStyle, useSharedValue } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { LinearGradient } from 'expo-linear-gradient';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { Icon } from './Icon';

/** Space below content so it clears the floating tab bar and Add button. */
export function useBottomSpace(extra = 0): number {
  const insets = useSafeAreaInsets();
  return (Platform.OS === 'ios' ? insets.bottom + 96 : 96) + extra;
}

/** Scroll position for collapsing large titles. Pass `onScroll` to any scroll view. */
export function useScrollHeader() {
  const scrollY = useSharedValue(0);
  return {
    scrollY,
    onScroll: (e: { nativeEvent: { contentOffset: { y: number } } }) => {
      scrollY.value = e.nativeEvent.contentOffset.y;
    },
  };
}

/**
 * Floating top bar: scroll-edge fade, a compact title that appears once the large title
 * scrolls away, and glass toolbar buttons (leading and trailing).
 */
export function TopBar({
  title,
  scrollY,
  leading,
  trailing,
  alwaysShowTitle,
  transparent,
}: {
  title?: string;
  scrollY?: SharedValue<number>;
  leading?: ReactNode;
  trailing?: ReactNode;
  alwaysShowTitle?: boolean;
  /** No scroll-edge background (e.g. over the Home aurora). */
  transparent?: boolean;
}) {
  const insets = useSafeAreaInsets();
  const { colors } = useTheme();
  const titleStyle = useAnimatedStyle(() => ({
    opacity: alwaysShowTitle ? 1 : interpolate(scrollY?.value ?? 0, [30, 60], [0, 1], 'clamp'),
  }));
  const edgeStyle = useAnimatedStyle(() => ({
    opacity: transparent ? 0 : interpolate(scrollY?.value ?? 0, [0, 30], [0, 1], 'clamp'),
  }));
  return (
    <View pointerEvents="box-none" style={[styles.bar, { paddingTop: insets.top + 4 }]}>
      <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { height: insets.top + 90 }, edgeStyle]}>
        <LinearGradient colors={[colors.background, `${colors.background}00`]} locations={[0.55, 1]} style={StyleSheet.absoluteFill} />
      </Animated.View>
      <View style={styles.row} pointerEvents="box-none">
        <View style={styles.side}>{leading}</View>
        <Animated.Text numberOfLines={1} style={[type.headline, styles.title, { color: colors.label }, titleStyle]}>
          {title}
        </Animated.Text>
        <View style={[styles.side, styles.trailing]}>{trailing}</View>
      </View>
    </View>
  );
}

/** In-content large title (34pt bold), optionally tappable with a chevron for a menu. */
export function LargeTitle({
  title,
  color,
  onPress,
  chevron,
  style,
}: {
  title: string;
  color?: string;
  onPress?: () => void;
  chevron?: boolean;
  style?: object;
}) {
  const { colors } = useTheme();
  const content = (
    <View style={styles.largeTitleRow}>
      <Text style={[type.largeTitle, { color: color ?? colors.label }]} accessibilityRole="header" numberOfLines={1}>
        {title}
      </Text>
      {chevron ? <Icon name="chevron.down" size={18} color={color ?? colors.label} weight="bold" /> : null}
    </View>
  );
  return (
    <View style={[{ paddingHorizontal: 20 }, style]}>
      {onPress ? (
        <Pressable onPress={onPress} accessibilityRole="button" hitSlop={8}>
          {content}
        </Pressable>
      ) : (
        content
      )}
    </View>
  );
}

/** Top padding so the large title sits below the toolbar buttons (Figma y≈100–108). */
export function useTitleTop(): number {
  return useSafeAreaInsets().top + 52;
}

const styles = StyleSheet.create({
  bar: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 10 },
  row: { height: 48, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16 },
  side: { flex: 1, flexDirection: 'row', alignItems: 'center' },
  trailing: { justifyContent: 'flex-end' },
  title: { flex: 2, textAlign: 'center' },
  largeTitleRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
});
