import RNDateTimePicker, { DateTimePickerAndroid } from '@react-native-community/datetimepicker';
import { useState } from 'react';
import { Modal, Platform, Pressable, StyleSheet, Text, View } from 'react-native';

import { maxOccurredAt } from '@/lib/dates';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { GlassSurface } from './Glass';

/** Opens the platform date + time picker. Android uses the system dialogs. */
export function pickDateTimeAndroid(value: number, onChange: (ms: number) => void) {
  DateTimePickerAndroid.open({
    value: new Date(value),
    mode: 'date',
    maximumDate: new Date(maxOccurredAt()),
    onChange: (e, date) => {
      if (e.type !== 'set' || !date) return;
      DateTimePickerAndroid.open({
        value: date,
        mode: 'time',
        onChange: (e2, time) => onChange((e2.type === 'set' && time ? time : date).getTime()),
      });
    },
  });
}

/** iOS: inline calendar + time on a glass sheet. */
export function DateTimeSheet({
  visible,
  value,
  onClose,
  onChange,
}: {
  visible: boolean;
  value: number;
  onClose: () => void;
  onChange: (ms: number) => void;
}) {
  const { colors, dark } = useTheme();
  const [draft, setDraft] = useState(value);
  if (Platform.OS !== 'ios') return null;
  return (
    <Modal visible={visible} transparent animationType="fade" onShow={() => setDraft(value)} onRequestClose={onClose}>
      <Pressable style={[StyleSheet.absoluteFill, styles.backdrop]} onPress={onClose} />
      <View style={styles.center} pointerEvents="box-none">
        <GlassSurface radius={28} style={styles.panel}>
          <RNDateTimePicker
            value={new Date(draft)}
            mode="datetime"
            display="inline"
            maximumDate={new Date(maxOccurredAt())}
            themeVariant={dark ? 'dark' : 'light'}
            accentColor={colors.accent}
            onChange={(_, d) => d && setDraft(d.getTime())}
          />
          <Pressable
            accessibilityRole="button"
            onPress={() => {
              onChange(draft);
              onClose();
            }}
            style={[styles.done, { backgroundColor: colors.accent }]}
          >
            <Text style={[type.headline, { color: '#FFFFFF' }]}>Done</Text>
          </Pressable>
        </GlassSurface>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { backgroundColor: 'rgba(0,0,0,0.25)' },
  center: { flex: 1, justifyContent: 'center', padding: 16 },
  panel: { padding: 12, gap: 8 },
  done: { height: 48, borderRadius: 24, alignItems: 'center', justifyContent: 'center' },
});
