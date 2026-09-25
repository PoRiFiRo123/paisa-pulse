import * as Haptics from 'expo-haptics';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { appDb } from '@/db/client';
import type { CategoryKind } from '@/db/schema';
import { CATEGORY_ICONS } from '@/features/categories/icons';
import { createCategory, updateCategory } from '@/features/categories/mutations';
import { categoriesByKind } from '@/features/categories/queries';
import { useQuery } from '@/hooks/useQuery';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { ColorPicker } from '@/ui/ColorPicker';
import { FieldRow } from '@/ui/FieldRow';
import { Icon } from '@/ui/Icon';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { Menu } from '@/ui/Menu';
import { SheetHeader, useSheetBackground } from '@/ui/SheetHeader';

export default function CategoryFormScreen() {
  const params = useLocalSearchParams<{ id?: string; kind?: CategoryKind; parentId?: string }>();
  const { colors } = useTheme();
  const background = useSheetBackground();
  const [kind, setKind] = useState<CategoryKind>(params.kind ?? 'expense');
  const [name, setName] = useState('');
  const [icon, setIcon] = useState('tag.fill');
  const [color, setColor] = useState('#5E5CE6');
  const [parentId, setParentId] = useState<string | null>(params.parentId ?? null);
  const { data: siblings } = useQuery(() => categoriesByKind(appDb, kind), [kind], []);

  useEffect(() => {
    if (!params.id) return;
    appDb.query.categories.findFirst({ where: (c, { eq }) => eq(c.id, params.id!) }).then((c) => {
      if (!c) return;
      setKind(c.kind);
      setName(c.name);
      setIcon(c.icon);
      setColor(c.color);
      setParentId(c.parentId);
    });
  }, [params.id]);

  const parents = siblings.filter((c) => !c.parentId && c.id !== params.id);
  const parent = parents.find((p) => p.id === parentId);

  const save = async () => {
    try {
      if (params.id) await updateCategory(appDb, params.id, { name, icon, color, parentId });
      else await createCategory(appDb, { kind, name, icon, color, parentId });
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      router.back();
    } catch (e) {
      Alert.alert('Can’t save', e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: background }}>
      <SheetHeader title={params.id ? 'Edit Category' : 'New Category'} onSave={save} canSave={name.trim().length > 0} />
      <ScrollView contentContainerStyle={{ paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
        <View style={{ alignItems: 'center', marginVertical: 8 }}>
          <CategoryIcon icon={icon} color={color} size={72} />
        </View>
        <InsetGroup dividerInset={16}>
          <FieldRow label="Name" value={name} onChangeText={setName} placeholder="Category name" autoFocus={!params.id} />
          <Menu
            items={[
              { title: 'None (top level)', checked: !parentId, onPress: () => setParentId(null) },
              'separator',
              ...parents.map((p) => ({ title: p.name, checked: p.id === parentId, onPress: () => setParentId(p.id) })),
            ]}
          >
            {(open) => <GroupRow title="Parent" value={parent?.name ?? 'None'} chevron onPress={open} />}
          </Menu>
        </InsetGroup>
        <GroupHeader title="Colour" />
        <ColorPicker value={color} onChange={setColor} />
        <GroupHeader title="Icon" />
        <View style={[styles.icons, { backgroundColor: colors.card }]}>
          {CATEGORY_ICONS.map((name) => (
            <Pressable
              key={name}
              accessibilityRole="radio"
              accessibilityState={{ checked: name === icon }}
              accessibilityLabel={name}
              onPress={() => {
                Haptics.selectionAsync().catch(() => {});
                setIcon(name);
              }}
              style={[styles.icon, { backgroundColor: name === icon ? color : colors.fill }]}
            >
              <Icon name={name} size={20} color={name === icon ? '#FFFFFF' : colors.label} />
            </Pressable>
          ))}
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  icons: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, padding: 16, marginHorizontal: 16, borderRadius: 22 },
  icon: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
});
