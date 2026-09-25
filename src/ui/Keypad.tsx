import * as Haptics from 'expo-haptics';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { applyKey, OPERATORS } from '@/lib/keypad';

import { Icon } from './Icon';

export { applyKey };

const ROWS = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['.', '0', '⌫'],
];

/** Figma "Keypad Key" grid with an operator strip for quick maths. */
export function Keypad({ onKey }: { onKey: (key: string) => void }) {
  const { colors } = useTheme();
  const press = (k: string) => {
    Haptics.selectionAsync().catch(() => {});
    onKey(k);
  };
  return (
    <View style={styles.pad}>
      <View style={styles.row}>
        {OPERATORS.map((op) => (
          <Pressable
            key={op}
            accessibilityLabel={{ '+': 'plus', '−': 'minus', '×': 'times', '÷': 'divided by' }[op]}
            onPress={() => press(op)}
            style={({ pressed }) => [styles.op, { backgroundColor: pressed ? colors.separator : colors.fill }]}
          >
            <Text style={[type.title3, { color: colors.accent, fontWeight: '600' }]}>{op}</Text>
          </Pressable>
        ))}
      </View>
      {ROWS.map((row) => (
        <View key={row.join('')} style={styles.row}>
          {row.map((k) => (
            <Pressable
              key={k}
              accessibilityRole="keyboardkey"
              accessibilityLabel={k === '⌫' ? 'Delete' : k === '.' ? 'Decimal point' : k}
              onPress={() => press(k)}
              onLongPress={k === '⌫' ? () => press('C') : undefined}
              style={({ pressed }) => [styles.key, { backgroundColor: pressed ? colors.separator : colors.card }]}
            >
              {k === '⌫' ? (
                <Icon name="delete.left" size={22} color={colors.label} />
              ) : (
                <Text style={[styles.digit, { color: colors.label }]}>{k}</Text>
              )}
            </Pressable>
          ))}
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  pad: { gap: 8 },
  row: { flexDirection: 'row', gap: 9 },
  key: { flex: 1, height: 50, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  op: { flex: 1, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  digit: { fontSize: 26, fontWeight: '500' },
});
