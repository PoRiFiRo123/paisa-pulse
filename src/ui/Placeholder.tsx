import type { ReactNode } from 'react';
import { ScrollView, StyleSheet, Text } from 'react-native';

import { useTheme } from '@/theme/useTheme';

/** Temporary screen body until the real screen is built from the Figma design. */
export function Placeholder({ title, children }: { title: string; children?: ReactNode }) {
  const { colors } = useTheme();
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: colors.background }}
      contentContainerStyle={styles.content}
    >
      <Text style={[styles.title, { color: colors.label }]}>{title}</Text>
      {children}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 64, gap: 8 },
  title: { fontSize: 34, fontWeight: '700' },
});
