import { Pressable, StyleSheet, Text, View } from 'react-native';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { CategoryIcon } from './CategoryIcon';

/** Figma "Category Capsule": solid chip with icon, name and amount (Home top categories). */
export function CategoryCapsule({
  name,
  icon,
  color,
  amount,
  onPress,
}: {
  name: string;
  icon?: string | null;
  color?: string | null;
  amount: string;
  onPress?: () => void;
}) {
  const { colors } = useTheme();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={`${name}, ${amount}`}
      style={({ pressed }) => [styles.capsule, { backgroundColor: colors.card, opacity: pressed ? 0.7 : 1 }]}
    >
      <CategoryIcon icon={icon} color={color} size={32} />
      <View>
        <Text style={[type.caption, { color: colors.secondary }]} numberOfLines={1}>
          {name}
        </Text>
        <Text style={[type.subheadAmount, { color: colors.label }]}>{amount}</Text>
      </View>
    </Pressable>
  );
}

/** Selectable chip for Quick Add (icon 24 + name). */
export function CategoryChip({
  name,
  icon,
  color,
  selected,
  onPress,
}: {
  name: string;
  icon?: string | null;
  color?: string | null;
  selected?: boolean;
  onPress: () => void;
}) {
  const { colors } = useTheme();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      style={[
        styles.chip,
        {
          backgroundColor: selected ? `${color ?? colors.accent}26` : colors.card,
          borderColor: selected ? (color ?? colors.accent) : 'transparent',
        },
      ]}
    >
      <CategoryIcon icon={icon} color={color} size={24} />
      <Text style={[type.subhead, { color: colors.label, fontWeight: selected ? '600' : '400' }]} numberOfLines={1}>
        {name}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  capsule: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingLeft: 8, paddingRight: 16, paddingVertical: 8, borderRadius: 999 },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingLeft: 6,
    paddingRight: 14,
    height: 36,
    borderRadius: 999,
    borderWidth: 1.5,
  },
});
