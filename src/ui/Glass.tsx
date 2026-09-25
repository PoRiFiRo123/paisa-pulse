import { BlurView } from 'expo-blur';
import { GlassContainer, GlassView, isLiquidGlassAvailable } from 'expo-glass-effect';
import * as Haptics from 'expo-haptics';
import type { ReactNode } from 'react';
import {
  AccessibilityInfo,
  Platform,
  Pressable,
  type PressableProps,
  StyleSheet,
  View,
  type ViewStyle,
  type StyleProp,
} from 'react-native';
import { useEffect, useState } from 'react';

import { useTheme } from '@/theme/useTheme';

import { Icon } from './Icon';

const LIQUID_GLASS = isLiquidGlassAvailable();

/** Honour Reduce Transparency: glass becomes a solid surface. */
function useReduceTransparency(): boolean {
  const [reduce, setReduce] = useState(false);
  useEffect(() => {
    // iOS-only API; other platforms keep the default.
    if (Platform.OS !== 'ios') return;
    AccessibilityInfo.isReduceTransparencyEnabled().then(setReduce).catch(() => {});
    const sub = AccessibilityInfo.addEventListener('reduceTransparencyChanged', setReduce);
    return () => sub.remove();
  }, []);
  return reduce;
}

export type GlassSurfaceProps = {
  children?: ReactNode;
  style?: StyleProp<ViewStyle>;
  /** Corner radius; glass is always rounded. */
  radius: number;
  /** Tinted glass (e.g. the accent-coloured Add button). */
  tint?: string;
  interactive?: boolean;
};

/**
 * A floating control surface. Liquid Glass on iOS 26+, frosted blur on older iOS,
 * a tonal Material-style surface on Android, solid when Reduce Transparency is on.
 * Only use it for controls (buttons, bars, sheets, menus), never for content.
 */
export function GlassSurface({ children, style, radius, tint, interactive }: GlassSurfaceProps) {
  const { dark, colors } = useTheme();
  const reduce = useReduceTransparency();
  const shape: ViewStyle = { borderRadius: radius, overflow: 'hidden' };

  if (LIQUID_GLASS && !reduce) {
    return (
      <GlassView
        style={[shape, style]}
        glassEffectStyle="regular"
        tintColor={tint}
        isInteractive={interactive}
        colorScheme={dark ? 'dark' : 'light'}
      >
        {children}
      </GlassView>
    );
  }

  const rim = { borderWidth: StyleSheet.hairlineWidth * 1.5, borderColor: tint ? 'rgba(255,255,255,0.6)' : colors.glassBorder };
  if (tint || reduce || Platform.OS !== 'ios') {
    const fill = tint ?? (dark ? '#2C2C2E' : Platform.OS === 'android' ? '#FFFFFF' : '#F9F9FB');
    return <View style={[shape, rim, styles.shadow, { backgroundColor: fill }, style]}>{children}</View>;
  }
  return (
    <View style={[shape, rim, style]}>
      <BlurView
        style={StyleSheet.absoluteFill}
        tint={dark ? 'systemChromeMaterialDark' : 'systemChromeMaterialLight'}
        intensity={80}
      />
      <View style={[StyleSheet.absoluteFill, { backgroundColor: colors.glassFill }]} />
      {children}
    </View>
  );
}

/** Groups nearby glass controls so they merge like Apple's toolbar buttons. */
export function GlassGroup({ children, style, spacing = 10 }: { children: ReactNode; style?: StyleProp<ViewStyle>; spacing?: number }) {
  if (LIQUID_GLASS) {
    return (
      <GlassContainer spacing={spacing} style={[{ flexDirection: 'row', gap: spacing }, style]}>
        {children}
      </GlassContainer>
    );
  }
  return <View style={[{ flexDirection: 'row', gap: spacing }, style]}>{children}</View>;
}

export type GlassButtonProps = Omit<PressableProps, 'style' | 'children'> & {
  icon: string;
  size?: number;
  iconSize?: number;
  tint?: string;
  iconColor?: string;
  accessibilityLabel: string;
  style?: StyleProp<ViewStyle>;
};

/** Figma "Glass Button": circular 44pt glass control with an SF Symbol. */
export function GlassButton({ icon, size = 44, iconSize, tint, iconColor, style, onPress, ...rest }: GlassButtonProps) {
  const { colors } = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      hitSlop={6}
      onPress={(e) => {
        Haptics.selectionAsync().catch(() => {});
        onPress?.(e);
      }}
      style={({ pressed }) => [{ transform: [{ scale: pressed ? 0.94 : 1 }] }, style]}
      {...rest}
    >
      <GlassSurface radius={size / 2} tint={tint} interactive style={[styles.center, { width: size, height: size }]}>
        <Icon name={icon} size={iconSize ?? Math.round(size * 0.45)} color={iconColor ?? (tint ? '#FFFFFF' : colors.label)} weight="semibold" />
      </GlassSurface>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  center: { alignItems: 'center', justifyContent: 'center' },
  shadow: {
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 8 },
    elevation: 4,
  },
});
