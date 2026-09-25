import { StyleSheet, View } from 'react-native';
import Animated, { useAnimatedStyle, withSpring } from 'react-native-reanimated';

import { useTheme } from '@/theme/useTheme';

/** Rounded progress bar; `marker` shows where spending "should" be (time elapsed). */
export function ProgressBar({ ratio, color, marker, height = 8 }: { ratio: number; color: string; marker?: number; height?: number }) {
  const { colors } = useTheme();
  const clamped = Math.min(Math.max(ratio, 0), 1);
  const fill = useAnimatedStyle(() => ({ width: withSpring(`${clamped * 100}%`, { damping: 20 }) }));
  return (
    <View
      style={[styles.track, { height, borderRadius: height / 2, backgroundColor: colors.fill }]}
      accessibilityRole="progressbar"
      accessibilityValue={{ min: 0, max: 100, now: Math.round(ratio * 100) }}
    >
      <Animated.View style={[styles.fill, { borderRadius: height / 2, backgroundColor: color }, fill]} />
      {marker !== undefined && marker > 0 && marker < 1 ? (
        <View style={[styles.marker, { left: `${marker * 100}%`, backgroundColor: colors.label }]} />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  track: { width: '100%', overflow: 'hidden' },
  fill: { height: '100%' },
  marker: { position: 'absolute', top: 0, bottom: 0, width: 2, marginLeft: -1, opacity: 0.35 },
});
