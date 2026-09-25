import { router } from 'expo-router';
import * as Haptics from 'expo-haptics';
import { Platform, Pressable, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useTheme } from '@/theme/useTheme';

import { GlassSurface } from './Glass';
import { Icon } from './Icon';
import { Menu } from './Menu';

/**
 * Figma "Add Button": accent-tinted glass capsule floating above the tab bar.
 * Tap → Quick Add. Long-press → Expense / Income / Transfer.
 */
export function AddButton() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const open = (kind?: 'expense' | 'income' | 'transfer') =>
    router.push(kind ? { pathname: '/add', params: { type: kind } } : '/add');
  return (
    <View
      pointerEvents="box-none"
      style={[styles.wrap, { bottom: Platform.OS === 'ios' ? insets.bottom + 72 : 20 }]}
    >
      <Menu
        items={[
          { title: 'Expense', icon: 'arrow.up.right', onPress: () => open('expense') },
          { title: 'Income', icon: 'arrow.down.left', onPress: () => open('income') },
          { title: 'Transfer', icon: 'arrow.left.arrow.right', onPress: () => open('transfer') },
        ]}
      >
        {(openMenu) => (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Add transaction"
            accessibilityHint="Long-press to choose expense, income or transfer"
            onPress={() => {
              Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => {});
              open();
            }}
            onLongPress={openMenu}
            style={({ pressed }) => ({ transform: [{ scale: pressed ? 0.92 : 1 }] })}
          >
            <GlassSurface radius={28} tint={colors.accent} interactive style={styles.button}>
              <Icon name="plus" size={26} color="#FFFFFF" weight="semibold" />
            </GlassSurface>
          </Pressable>
        )}
      </Menu>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { position: 'absolute', right: 20 },
  button: { width: 56, height: 56, alignItems: 'center', justifyContent: 'center' },
});
