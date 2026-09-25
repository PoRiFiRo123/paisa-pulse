import { LinearGradient } from 'expo-linear-gradient';
import { StyleSheet, useWindowDimensions, View } from 'react-native';
import Svg, { Defs, Ellipse, RadialGradient, Stop } from 'react-native-svg';

import { useTheme } from '@/theme/useTheme';

/**
 * Home background (Figma "Aurora" + "Blob Warm" + "Blob Pink"): an accent gradient fading
 * into the page with two soft colour blobs, so the glass hero card has something to refract.
 */
export function Aurora({ height = 540 }: { height?: number }) {
  const { colors, dark } = useTheme();
  const { width } = useWindowDimensions();
  const scale = width / 402;
  const blobOpacity = dark ? 0.35 : 0.75;
  return (
    <View style={{ position: 'absolute', top: 0, left: 0, right: 0, height }} pointerEvents="none">
      <LinearGradient
        colors={[dark ? colors.aurora[0] : colors.accent, colors.aurora[1], colors.background]}
        locations={[0, 0.5, 1]}
        style={StyleSheet.absoluteFill}
      />
      <Svg width={width} height={height} style={StyleSheet.absoluteFill}>
        <Defs>
          <RadialGradient id="warm" cx="50%" cy="50%" r="50%">
            <Stop offset="0" stopColor="#FFB07A" stopOpacity={blobOpacity} />
            <Stop offset="1" stopColor="#FFB07A" stopOpacity={0} />
          </RadialGradient>
          <RadialGradient id="pink" cx="50%" cy="50%" r="50%">
            <Stop offset="0" stopColor="#FF6FB1" stopOpacity={blobOpacity} />
            <Stop offset="1" stopColor="#FF6FB1" stopOpacity={0} />
          </RadialGradient>
        </Defs>
        <Ellipse cx={330 * scale} cy={250} rx={200 * scale} ry={170} fill="url(#warm)" />
        <Ellipse cx={40 * scale} cy={320} rx={170 * scale} ry={150} fill="url(#pink)" />
      </Svg>
    </View>
  );
}
