import { eq } from 'drizzle-orm';
import * as Haptics from 'expo-haptics';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, ScrollView, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { budgets, type Category } from '@/db/schema';
import { budgetableCategories, deleteBudget, setBudget } from '@/features/budgets/budgets';
import { useQuery } from '@/hooks/useQuery';
import { formatINR, tryToPaise } from '@/lib/money';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { FieldRow } from '@/ui/FieldRow';
import { GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { Menu } from '@/ui/Menu';
import { SheetHeader, useSheetBackground } from '@/ui/SheetHeader';

export default function BudgetFormScreen() {
  const { id } = useLocalSearchParams<{ id?: string }>();
  const { colors } = useTheme();
  const background = useSheetBackground();
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [amount, setAmount] = useState('');
  const [existingCategory, setExistingCategory] = useState<Category | null>(null);
  const { data: options } = useQuery(() => budgetableCategories(appDb), [], []);

  useEffect(() => {
    if (!id) return;
    (async () => {
      const b = await appDb.select().from(budgets).where(eq(budgets.id, id)).get();
      if (!b) return;
      setCategoryId(b.categoryId);
      setAmount(formatINR(b.amount, { symbol: false, decimals: 'auto' }).replace(/,/g, ''));
      if (b.categoryId) setExistingCategory((await appDb.query.categories.findFirst({ where: (c, { eq: e }) => e(c.id, b.categoryId!) })) ?? null);
    })();
  }, [id]);

  const choices = existingCategory ? [existingCategory, ...options] : options;
  const selected = choices.find((c) => c.id === categoryId) ?? null;
  const paise = tryToPaise(amount || '0') ?? 0;

  const save = async () => {
    try {
      await setBudget(appDb, categoryId, paise);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      router.back();
    } catch (e) {
      Alert.alert('Can’t save', e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: background }}>
      <SheetHeader title={id ? 'Edit Budget' : 'New Budget'} onSave={save} canSave={paise > 0} />
      <ScrollView keyboardShouldPersistTaps="handled">
        <InsetGroup dividerInset={16}>
          <Menu
            items={[
              { title: 'All spending', checked: categoryId === null, onPress: () => setCategoryId(null) },
              'separator',
              ...choices.map((c) => ({ title: c.parentId ? `  ${c.name}` : c.name, icon: c.icon, checked: c.id === categoryId, onPress: () => setCategoryId(c.id) })),
            ]}
          >
            {(open) => (
              <GroupRow
                title="For"
                value={selected?.name ?? 'All spending'}
                leading={<CategoryIcon icon={selected?.icon ?? 'chart.pie.fill'} color={selected?.color ?? colors.accent} size={28} />}
                chevron
                onPress={id ? undefined : open}
              />
            )}
          </Menu>
          <FieldRow label="Monthly limit" value={amount} onChangeText={setAmount} placeholder="₹0" keyboardType="decimal-pad" autoFocus />
        </InsetGroup>
        <Text style={[type.footnote, { color: colors.secondary, paddingHorizontal: 32, paddingTop: 8 }]}>
          Budgets reset at the start of each month (Settings › Month starts on). A category budget includes its subcategories.
        </Text>
        {id ? (
          <InsetGroup style={{ marginTop: 12 }}>
            <GroupRow
              title="Delete Budget"
              destructive
              onPress={async () => {
                await deleteBudget(appDb, id);
                router.back();
              }}
            />
          </InsetGroup>
        ) : null}
      </ScrollView>
    </View>
  );
}
