import * as Haptics from 'expo-haptics';
import { type ReactNode, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';

import { useTheme } from '@/theme/useTheme';
import { type } from '@/theme/typography';

import { GlassSurface } from './Glass';
import { Icon } from './Icon';

export type MenuAction = {
  title: string;
  icon?: string;
  destructive?: boolean;
  checked?: boolean;
  disabled?: boolean;
  onPress: () => void;
};
export type MenuItem = MenuAction | 'separator';

const WIDTH = 250;
const ROW = 44;

/**
 * Pull-down / context menu on a glass panel (Figma "Context Menu (Glass)").
 * Works on both platforms. Usage: <Menu items={...}>{(open) => <Button onPress={open} />}</Menu>
 */
export function Menu({ items, children }: { items: MenuItem[]; children: (open: () => void) => ReactNode }) {
  const [anchor, setAnchor] = useState<View | null>(null);
  const [frame, setFrame] = useState<{ x: number; y: number; w: number; h: number } | null>(null);
  const open = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
    anchor?.measureInWindow((x, y, w, h) => setFrame({ x, y, w, h }));
  };
  return (
    <>
      <View ref={setAnchor} collapsable={false}>
        {children(open)}
      </View>
      <MenuPopover items={items} frame={frame} onClose={() => setFrame(null)} />
    </>
  );
}

export function MenuPopover({
  items,
  frame,
  onClose,
}: {
  items: MenuItem[];
  frame: { x: number; y: number; w: number; h: number } | null;
  onClose: () => void;
}) {
  const { colors } = useTheme();
  const screen = useWindowDimensions();
  if (!frame) return null;

  const height = Math.min(
    items.reduce((h, i) => h + (i === 'separator' ? 6 : ROW), 12),
    screen.height * 0.6,
  );
  const alignRight = frame.x + frame.w / 2 > screen.width / 2;
  const left = alignRight
    ? Math.max(8, frame.x + frame.w - WIDTH)
    : Math.min(frame.x, screen.width - WIDTH - 8);
  const below = frame.y + frame.h + 8;
  const top = below + height > screen.height - 24 ? Math.max(48, frame.y - height - 8) : below;

  return (
    <Modal transparent animationType="fade" onRequestClose={onClose} statusBarTranslucent>
      <Pressable style={StyleSheet.absoluteFill} onPress={onClose} accessibilityLabel="Close menu" />
      <GlassSurface radius={20} style={[styles.panel, { left, top, maxHeight: height }]}>
        <ScrollView bounces={false} contentContainerStyle={{ paddingVertical: 6 }}>
          {items.map((item, i) =>
            item === 'separator' ? (
              <View key={`sep${i}`} style={{ height: 6, backgroundColor: colors.fill }} />
            ) : (
              <Pressable
                key={item.title}
                disabled={item.disabled}
                accessibilityRole="menuitem"
                onPress={() => {
                  onClose();
                  Haptics.selectionAsync().catch(() => {});
                  // Let the popover fade before the action navigates or opens another modal.
                  setTimeout(item.onPress, 120);
                }}
                style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.fill }]}
              >
                <View style={styles.check}>
                  {item.checked ? <Icon name="checkmark" size={14} color={colors.label} weight="semibold" /> : null}
                </View>
                <Text
                  numberOfLines={1}
                  style={[
                    type.body,
                    { flex: 1, color: item.destructive ? colors.expense : colors.label },
                    item.disabled && { opacity: 0.4 },
                  ]}
                >
                  {item.title}
                </Text>
                {item.icon ? (
                  <Icon name={item.icon} size={18} color={item.destructive ? colors.expense : colors.label} />
                ) : null}
              </Pressable>
            ),
          )}
        </ScrollView>
      </GlassSurface>
    </Modal>
  );
}

const styles = StyleSheet.create({
  panel: { position: 'absolute', width: WIDTH },
  row: { height: ROW, flexDirection: 'row', alignItems: 'center', paddingRight: 18, gap: 4 },
  check: { width: 28, alignItems: 'center' },
});
