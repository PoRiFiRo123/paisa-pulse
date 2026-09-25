import { View } from 'react-native';

import { TRANSFER_COLOR, UNCATEGORISED_COLOR } from '@/theme/tokens';

import { Icon } from './Icon';

/** Coloured circle with a white SF Symbol (Figma Transaction Row > Icon). */
export function CategoryIcon({
  icon,
  color,
  size = 38,
  square = false,
}: {
  icon?: string | null;
  color?: string | null;
  size?: number;
  /** Rounded square, as in Settings rows. */
  square?: boolean;
}) {
  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: square ? size * 0.23 : size / 2,
        backgroundColor: color ?? UNCATEGORISED_COLOR,
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <Icon name={icon ?? 'questionmark'} size={Math.round(size * 0.5)} color="#FFFFFF" weight="semibold" />
    </View>
  );
}

export function transactionVisual(t: { type: string; categoryIcon: string | null; categoryColor: string | null }) {
  if (t.type === 'transfer') return { icon: 'arrow.left.arrow.right', color: TRANSFER_COLOR };
  return { icon: t.categoryIcon ?? 'questionmark', color: t.categoryColor ?? UNCATEGORISED_COLOR };
}
