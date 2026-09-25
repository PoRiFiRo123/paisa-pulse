import * as Haptics from 'expo-haptics';
import { Pressable, StyleSheet, View } from 'react-native';

import { PALETTE } from '@/theme/tokens';
import { useTheme } from '@/theme/useTheme';

import { Icon } from './Icon';

export function ColorPicker({ value, onChange, colors: options = PALETTE }: { value: string; onChange: (c: string) => void; colors?: string[] }) {
  const { colors } = useTheme();
  return (
    <View style={[styles.wrap, { backgroundColor: colors.card }]}>
      {options.map((c) => (
        <Pressable
          key={c}
          accessibilityRole="radio"
          accessibilityState={{ checked: c === value }}
          accessibilityLabel={`Colour ${c}`}
          onPress={() => {
            Haptics.selectionAsync().catch(() => {});
            onChange(c);
          }}
          style={[styles.swatch, { backgroundColor: c }, c === value && { borderColor: colors.label }]}
        >
          {c === value ? <Icon name="checkmark" size={14} color="#FFFFFF" weight="bold" /> : null}
        </Pressable>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 12, padding: 16, borderRadius: 22, marginHorizontal: 16 },
  swatch: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center', borderWidth: 2, borderColor: 'transparent' },
});
