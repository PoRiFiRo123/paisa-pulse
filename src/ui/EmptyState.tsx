import { Pressable, StyleSheet, Text, View } from 'react-native';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { GlassSurface } from './Glass';
import { Icon } from './Icon';

export function EmptyState({
  icon,
  title,
  message,
  actionLabel,
  onAction,
}: {
  icon: string;
  title: string;
  message?: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  const { colors } = useTheme();
  return (
    <View style={styles.wrap}>
      <Icon name={icon} size={48} color={colors.secondary} weight="regular" />
      <Text style={[type.title3, { color: colors.label, textAlign: 'center' }]}>{title}</Text>
      {message ? <Text style={[type.subhead, { color: colors.secondary, textAlign: 'center' }]}>{message}</Text> : null}
      {actionLabel && onAction ? (
        <Pressable onPress={onAction} accessibilityRole="button" style={{ marginTop: 8 }}>
          <GlassSurface radius={24} tint={colors.accent} interactive style={styles.button}>
            <Icon name="plus" size={16} color="#FFFFFF" weight="bold" />
            <Text style={[type.headline, { color: '#FFFFFF' }]}>{actionLabel}</Text>
          </GlassSurface>
        </Pressable>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { alignItems: 'center', paddingVertical: 40, paddingHorizontal: 32, gap: 8 },
  button: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 20, height: 48 },
});
