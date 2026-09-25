import { useState } from 'react';
import { KeyboardAvoidingView, Modal, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { GlassSurface } from './Glass';

/** Cross-platform text prompt (Alert.prompt is iOS-only). */
export function NamePrompt({
  visible,
  title,
  initial = '',
  placeholder,
  confirmLabel = 'Save',
  onCancel,
  onConfirm,
}: {
  visible: boolean;
  title: string;
  initial?: string;
  placeholder?: string;
  confirmLabel?: string;
  onCancel: () => void;
  onConfirm: (value: string) => void;
}) {
  const { colors } = useTheme();
  const [value, setValue] = useState(initial);
  return (
    <Modal visible={visible} transparent animationType="fade" onShow={() => setValue(initial)} onRequestClose={onCancel}>
      <KeyboardAvoidingView style={styles.center} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <Pressable style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(0,0,0,0.25)' }]} onPress={onCancel} />
        <GlassSurface radius={26} style={styles.panel}>
          <Text style={[type.headline, { color: colors.label, textAlign: 'center' }]}>{title}</Text>
          <TextInput
            value={value}
            onChangeText={setValue}
            placeholder={placeholder}
            placeholderTextColor={colors.secondary}
            autoFocus
            returnKeyType="done"
            onSubmitEditing={() => value.trim() && onConfirm(value)}
            style={[type.body, styles.input, { color: colors.label, backgroundColor: colors.fill }]}
            accessibilityLabel={title}
          />
          <View style={styles.buttons}>
            <Pressable onPress={onCancel} style={[styles.button, { backgroundColor: colors.fill }]} accessibilityRole="button" accessibilityLabel="Cancel">
              <Text style={[type.headline, { color: colors.label }]}>Cancel</Text>
            </Pressable>
            <Pressable
              disabled={!value.trim()}
              onPress={() => onConfirm(value)}
              style={[styles.button, { backgroundColor: colors.accent, opacity: value.trim() ? 1 : 0.4 }]}
              accessibilityRole="button"
              accessibilityLabel={confirmLabel}
            >
              <Text style={[type.headline, { color: '#FFFFFF' }]}>{confirmLabel}</Text>
            </Pressable>
          </View>
        </GlassSurface>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', padding: 24 },
  panel: { padding: 20, gap: 14 },
  input: { height: 44, borderRadius: 12, paddingHorizontal: 12 },
  buttons: { flexDirection: 'row', gap: 10 },
  button: { flex: 1, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
});
