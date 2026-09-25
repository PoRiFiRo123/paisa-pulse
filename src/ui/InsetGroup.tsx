import { Children, Fragment, type ReactNode } from 'react';
import { Pressable, StyleSheet, Text, View, type StyleProp, type ViewStyle } from 'react-native';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { Icon } from './Icon';

/** iOS inset grouped card: solid content surface with hairline dividers between rows. */
export function InsetGroup({
  children,
  style,
  dividerInset = 58,
}: {
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
  dividerInset?: number;
}) {
  const { colors } = useTheme();
  const rows = Children.toArray(children).filter(Boolean);
  return (
    <View style={[styles.group, { backgroundColor: colors.card }, style]}>
      {rows.map((row, i) => (
        <Fragment key={i}>
          {i > 0 ? <Divider inset={dividerInset} /> : null}
          {row}
        </Fragment>
      ))}
    </View>
  );
}

export function Divider({ inset = 0 }: { inset?: number }) {
  const { colors } = useTheme();
  return (
    <View style={{ paddingLeft: inset, backgroundColor: colors.card }}>
      <View style={{ height: StyleSheet.hairlineWidth, backgroundColor: colors.rowDivider }} />
    </View>
  );
}

export function GroupHeader({ title, style }: { title: string; style?: StyleProp<ViewStyle> }) {
  const { colors } = useTheme();
  return (
    <Text style={[type.sectionHeader, { color: colors.secondary, paddingHorizontal: 32, paddingTop: 18, paddingBottom: 6 }, style]}>
      {title}
    </Text>
  );
}

export type GroupRowProps = {
  title: string;
  value?: string;
  /** Left accessory, e.g. a CategoryIcon. */
  leading?: ReactNode;
  /** Right accessory replacing value/chevron, e.g. a Switch. */
  trailing?: ReactNode;
  chevron?: boolean;
  destructive?: boolean;
  tinted?: boolean;
  height?: number;
  onPress?: () => void;
  onLongPress?: () => void;
  accessibilityHint?: string;
};

/** Figma "Settings Row" / detail row: 50–56pt, icon, label, value, chevron. */
export function GroupRow({
  title,
  value,
  leading,
  trailing,
  chevron,
  destructive,
  tinted,
  height = 50,
  onPress,
  onLongPress,
  accessibilityHint,
}: GroupRowProps) {
  const { colors } = useTheme();
  const titleColor = destructive ? colors.expense : tinted ? colors.accent : colors.label;
  return (
    <Pressable
      disabled={!onPress && !onLongPress}
      onPress={onPress}
      onLongPress={onLongPress}
      accessibilityRole={onPress ? 'button' : undefined}
      accessibilityHint={accessibilityHint}
      style={({ pressed }) => [styles.row, { minHeight: height, backgroundColor: pressed ? colors.fill : colors.card }]}
    >
      {leading ? <View style={styles.leading}>{leading}</View> : null}
      <Text style={[type.body, { color: titleColor, flexShrink: 1 }]} numberOfLines={1}>
        {title}
      </Text>
      <View style={styles.spacer} />
      {trailing ?? (
        <>
          {value ? (
            <Text style={[type.body, { color: colors.secondary, flexShrink: 1, textAlign: 'right' }]} numberOfLines={1}>
              {value}
            </Text>
          ) : null}
          {chevron ? <Icon name="chevron.right" size={13} color={colors.secondary} weight="semibold" /> : null}
        </>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  group: { borderRadius: 22, overflow: 'hidden', marginHorizontal: 16 },
  row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, gap: 8 },
  leading: { marginRight: 4 },
  spacer: { flex: 1, minWidth: 8 },
});
