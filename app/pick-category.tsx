import * as Haptics from 'expo-haptics';
import { router, useLocalSearchParams } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { categoriesByKind } from '@/features/categories/queries';
import { listTransactions } from '@/features/transactions/list';
import { setTransactionCategory } from '@/features/transactions/mutations';
import { useQuery } from '@/hooks/useQuery';
import { UNCATEGORISED_COLOR } from '@/theme/tokens';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { SheetHeader, useSheetBackground } from '@/ui/SheetHeader';

/** "Change Category" sheet: a grid of the transaction's categories, one tap to apply. */
export default function PickCategoryScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { colors } = useTheme();
  const background = useSheetBackground();
  const { data } = useQuery(
    async () => {
      const [t] = await listTransactions(appDb, { id });
      const cats = t ? await categoriesByKind(appDb, t.type === 'income' ? 'income' : 'expense') : [];
      return { t: t as typeof t | undefined, cats };
    },
    [id],
    { t: undefined, cats: [] },
  );

  const pick = async (categoryId: string | null) => {
    await setTransactionCategory(appDb, id, categoryId);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
    router.back();
  };

  const parents = data.cats.filter((c) => !c.parentId);
  const ordered = parents.flatMap((p) => [p, ...data.cats.filter((c) => c.parentId === p.id)]);
  const items = [...ordered.map((c) => ({ id: c.id as string | null, name: c.name, icon: c.icon, color: c.color })), { id: null, name: 'Uncategorised', icon: 'questionmark', color: UNCATEGORISED_COLOR }];

  return (
    <View style={{ flex: 1, backgroundColor: background }}>
      <SheetHeader title="Change Category" />
      <ScrollView contentContainerStyle={styles.grid}>
        {items.map((c) => {
          const selected = data.t?.categoryId === c.id;
          return (
            <Pressable
              key={c.id ?? 'none'}
              onPress={() => pick(c.id)}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              style={[styles.item, selected && { backgroundColor: `${c.color}26` }]}
            >
              <CategoryIcon icon={c.icon} color={c.color} size={48} />
              <Text style={[type.caption, { color: colors.label, textAlign: 'center' }]} numberOfLines={2}>
                {c.name}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  grid: { flexDirection: 'row', flexWrap: 'wrap', paddingHorizontal: 12, paddingBottom: 40 },
  item: { width: '25%', alignItems: 'center', gap: 6, paddingVertical: 12, borderRadius: 16 },
});
