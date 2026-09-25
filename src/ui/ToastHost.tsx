import { Pressable, StyleSheet, Text } from 'react-native';
import Animated, { FadeInDown, FadeOutDown } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useToast } from '@/stores/toast';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { GlassSurface } from './Glass';

/** Floating glass capsule above the tab bar: "Transaction deleted · Undo". */
export function ToastHost() {
  const toast = useToast((s) => s.toast);
  const hide = useToast((s) => s.hide);
  const undo = useToast((s) => s.undo);
  const insets = useSafeAreaInsets();
  const { colors } = useTheme();
  if (!toast) return null;
  return (
    <Animated.View
      key={toast.id}
      entering={FadeInDown.springify().damping(18)}
      exiting={FadeOutDown}
      style={[styles.wrap, { bottom: insets.bottom + 96 }]}
      pointerEvents="box-none"
    >
      <GlassSurface radius={26} style={styles.toast}>
        <Text style={[type.subhead, { color: colors.label, flex: 1 }]} numberOfLines={1} accessibilityLiveRegion="polite">
          {toast.message}
        </Text>
        {toast.actionLabel ? (
          <Pressable
            hitSlop={10}
            accessibilityRole="button"
            onPress={() => {
              if (toast.actionLabel === 'Undo') undo();
              else {
                toast.onAction?.();
                hide();
              }
            }}
          >
            <Text style={[type.headline, { color: colors.accent }]}>{toast.actionLabel}</Text>
          </Pressable>
        ) : null}
      </GlassSurface>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  wrap: { position: 'absolute', left: 16, right: 16, alignItems: 'center' },
  toast: {
    minHeight: 52,
    maxWidth: 420,
    width: '100%',
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    gap: 16,
  },
});
