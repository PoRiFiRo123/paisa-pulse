import { isLiquidGlassAvailable } from 'expo-glass-effect';
import { router } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { GlassButton } from './Glass';

/** Background for form sheets: transparent on iOS 26 so the system sheet's glass shows. */
export function useSheetBackground(): string {
  const { colors } = useTheme();
  return isLiquidGlassAvailable() ? 'transparent' : colors.background;
}

/** iOS 26 sheet toolbar: glass ✕, title, glass ✓ (Figma "Sheet Toolbar"). */
export function SheetHeader({ title, onSave, canSave = true }: { title: string; onSave?: () => void; canSave?: boolean }) {
  const { colors } = useTheme();
  return (
    <View style={styles.bar}>
      <GlassButton icon="xmark" accessibilityLabel="Cancel" onPress={() => router.back()} />
      <Text style={[type.headline, { color: colors.label }]} numberOfLines={1}>
        {title}
      </Text>
      {onSave ? (
        <GlassButton
          icon="checkmark"
          accessibilityLabel="Save"
          tint={canSave ? colors.accent : undefined}
          iconColor={canSave ? '#FFFFFF' : colors.secondary}
          onPress={onSave}
        />
      ) : (
        <View style={{ width: 44 }} />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  bar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingTop: 22, paddingBottom: 12 },
});
