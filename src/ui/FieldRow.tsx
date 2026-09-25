import { StyleSheet, Text, TextInput, type TextInputProps, View } from 'react-native';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

/** Form row inside an InsetGroup: label on the left, text input on the right. */
export function FieldRow({ label, ...input }: { label: string } & TextInputProps) {
  const { colors } = useTheme();
  return (
    <View style={[styles.row, { backgroundColor: colors.card }]}>
      <Text style={[type.body, { color: colors.label }]}>{label}</Text>
      <TextInput
        placeholderTextColor={colors.secondary}
        accessibilityLabel={label}
        {...input}
        style={[type.body, styles.input, { color: colors.label }]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  row: { minHeight: 50, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, gap: 12 },
  input: { flex: 1, textAlign: 'right', paddingVertical: 12 },
});
