import { Image } from 'expo-image';
import { useState } from 'react';
import { Text, View } from 'react-native';

import { type Brand, logoUrl, matchBrand, monogram, onColor } from '@/features/merchants/brands';
import { usePrefs } from '@/stores/prefs';

import { CategoryIcon } from './CategoryIcon';

/**
 * A recognised merchant's mark: its logo (if the user turned on merchant logos) or a
 * brand-coloured monogram. Unknown names fall back to the category icon.
 */
export function MerchantIcon({
  name,
  brand: given,
  fallbackIcon,
  fallbackColor,
  size = 38,
}: {
  name?: string | null;
  brand?: Brand | null;
  fallbackIcon?: string | null;
  fallbackColor?: string | null;
  size?: number;
}) {
  const brand = given ?? matchBrand(name);
  if (!brand) return <CategoryIcon icon={fallbackIcon ?? 'repeat'} color={fallbackColor} size={size} />;
  return <BrandMark brand={brand} size={size} />;
}

export function BrandMark({ brand, size = 38 }: { brand: Brand; size?: number }) {
  const logos = usePrefs((s) => s.merchantLogos);
  const [failed, setFailed] = useState(false);
  const url = logos && !failed ? logoUrl(brand) : null;
  return (
    <View
      accessible={false}
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        overflow: 'hidden',
        backgroundColor: url ? '#FFFFFF' : brand.color,
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      {url ? (
        <Image
          source={{ uri: url }}
          style={{ width: size * 0.66, height: size * 0.66 }}
          contentFit="contain"
          cachePolicy="disk"
          recyclingKey={brand.name}
          onError={() => setFailed(true)}
        />
      ) : (
        <Text style={{ color: onColor(brand.color), fontSize: size * 0.46, fontWeight: '700' }} allowFontScaling={false}>
          {monogram(brand.name)}
        </Text>
      )}
    </View>
  );
}
