import * as Haptics from 'expo-haptics';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

export type Segment<T extends string> = { value: T; label: string; color?: string };

/** iOS-style segmented control; the selected segment can be colour-coded. */
export function SegmentedControl<T extends string>({
  segments,
  value,
  onChange,
}: {
  segments: Segment<T>[];
  value: T;
  onChange: (value: T) => void;
}) {
  const { colors, dark } = useTheme();
  return (
    <View style={[styles.track, { backgroundColor: colors.fill }]} accessibilityRole="tablist">
      {segments.map((s) => {
        const selected = s.value === value;
        return (
          <Pressable
            key={s.value}
            accessibilityRole="tab"
            accessibilityState={{ selected }}
            onPress={() => {
              if (selected) return;
              Haptics.selectionAsync().catch(() => {});
              onChange(s.value);
            }}
            style={[styles.segment, selected && [styles.selected, { backgroundColor: dark ? '#636366' : '#FFFFFF' }]]}
          >
            <Text style={[type.subhead, { fontWeight: selected ? '600' : '500', color: selected ? (s.color ?? colors.label) : colors.label }]}>
              {s.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  track: { flexDirection: 'row', borderRadius: 19, padding: 3, height: 38 },
  segment: { flex: 1, alignItems: 'center', justifyContent: 'center', borderRadius: 16 },
  selected: {
    shadowColor: '#000',
    shadowOpacity: 0.12,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
  },
});
