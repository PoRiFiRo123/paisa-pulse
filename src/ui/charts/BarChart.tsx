import * as Haptics from 'expo-haptics';
import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Line, Path } from 'react-native-svg';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

export type Bar = { key: string; label: string; value: number; accessibilityLabel: string };

/** 1, 2, 5 × 10^k at or above `v`, for axis maxima. */
export function niceCeil(v: number): number {
  if (v <= 0) return 1;
  const exp = 10 ** Math.floor(Math.log10(v));
  const f = v / exp;
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * exp;
}

/** Bar with a 4pt radius on the data end, square on the baseline. */
function barPath(x: number, w: number, top: number, base: number): string {
  const h = base - top;
  if (h <= 0) return '';
  const r = Math.min(4, w / 2, h);
  return `M${x} ${base} V${top + r} Q${x} ${top} ${x + r} ${top} H${x + w - r} Q${x + w} ${top} ${x + w} ${top + r} V${base} Z`;
}

/**
 * Single-series vertical bar chart (one hue). Tap a column to select it; the rest recede.
 * Gridlines and labels stay recessive; values are shown by the caller for the selection.
 */
export function BarChart({
  bars,
  color,
  selectedKey,
  onSelect,
  formatTick,
  height = 180,
}: {
  bars: Bar[];
  color: string;
  selectedKey?: string;
  onSelect?: (key: string) => void;
  formatTick: (v: number) => string;
  height?: number;
}) {
  const { colors } = useTheme();
  const [width, setWidth] = useState(0);
  const axisW = 48;
  const labelH = 22;
  const plotW = Math.max(0, width - axisW);
  const plotH = height - labelH;
  const max = niceCeil(Math.max(...bars.map((b) => b.value), 0));
  const ticks = [0, max / 2, max];
  const band = bars.length ? plotW / bars.length : 0;
  const barW = Math.min(28, band * 0.56);
  const y = (v: number) => plotH - (v / max) * (plotH - 8);

  return (
    <View style={{ height }} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
      {width > 0 ? (
        <>
          <Svg width={width} height={plotH} style={StyleSheet.absoluteFill}>
            {ticks.map((t) => (
              <Line key={t} x1={axisW} x2={width} y1={y(t)} y2={y(t)} stroke={colors.separator} strokeWidth={t === 0 ? 1 : 0.5} />
            ))}
            {bars.map((b, i) => {
              const x = axisW + i * band + (band - barW) / 2;
              const dim = selectedKey !== undefined && b.key !== selectedKey;
              return <Path key={b.key} d={barPath(x, barW, y(b.value), y(0))} fill={color} opacity={dim ? 0.35 : 1} />;
            })}
          </Svg>
          {ticks.slice(1).map((t) => (
            <Text key={t} style={[type.caption, styles.tick, { top: y(t) - 8, color: colors.secondary }]}>
              {formatTick(t)}
            </Text>
          ))}
          {bars.map((b, i) => (
            <Pressable
              key={b.key}
              accessibilityRole="button"
              accessibilityLabel={b.accessibilityLabel}
              accessibilityState={{ selected: b.key === selectedKey }}
              onPress={() => {
                Haptics.selectionAsync().catch(() => {});
                onSelect?.(b.key);
              }}
              style={[styles.hit, { left: axisW + i * band, width: band, height }]}
            >
              <Text
                style={[
                  type.caption,
                  styles.label,
                  { color: b.key === selectedKey ? colors.label : colors.secondary, fontWeight: b.key === selectedKey ? '600' : '400' },
                ]}
              >
                {b.label}
              </Text>
            </Pressable>
          ))}
        </>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  tick: { position: 'absolute', left: 0, width: 44, fontVariant: ['tabular-nums'] },
  hit: { position: 'absolute', top: 0, justifyContent: 'flex-end', alignItems: 'center' },
  label: { height: 18 },
});
