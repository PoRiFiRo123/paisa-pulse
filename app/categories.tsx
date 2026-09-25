import { router } from 'expo-router';
import { useState } from 'react';
import { Alert, ScrollView, View } from 'react-native';

import { appDb } from '@/db/client';
import type { Category, CategoryKind } from '@/db/schema';
import { mergeCategory, reorderCategories, setCategoryArchived } from '@/features/categories/mutations';
import { categoriesByKind } from '@/features/categories/queries';
import { useQuery } from '@/hooks/useQuery';
import { useToast } from '@/stores/toast';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { GlassButton } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { Menu, type MenuItem } from '@/ui/Menu';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';
import { SegmentedControl } from '@/ui/SegmentedControl';

export default function CategoriesScreen() {
  const { colors } = useTheme();
  const toast = useToast((s) => s.show);
  const [kind, setKind] = useState<CategoryKind>('expense');
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const { data: all } = useQuery(() => categoriesByKind(appDb, kind, { includeArchived: true }), [kind], []);
  const active = all.filter((c) => !c.archivedAt);
  const archived = all.filter((c) => c.archivedAt);
  const parents = active.filter((c) => !c.parentId);

  const edit = (c: Category) => router.push({ pathname: '/category-form', params: { id: c.id } });
  const move = (siblings: Category[], index: number, delta: number) => {
    const ids = siblings.map((c) => c.id);
    const [id] = ids.splice(index, 1);
    ids.splice(index + delta, 0, id);
    reorderCategories(appDb, ids);
  };
  const merge = (from: Category) => {
    const targets = active.filter((c) => c.id !== from.id && c.parentId !== from.id);
    Alert.alert(`Merge “${from.name}” into…`, 'All its transactions move to the category you pick, and it gets archived.', [
      ...targets.slice(0, 8).map((to) => ({
        text: to.name,
        onPress: () =>
          mergeCategory(appDb, from.id, to.id)
            .then(() => toast({ message: `Merged into ${to.name}` }))
            .catch((e: Error) => Alert.alert('Can’t merge', e.message)),
      })),
      { text: 'Cancel', style: 'cancel' as const },
    ]);
  };
  const menu = (c: Category, siblings: Category[], index: number): MenuItem[] => [
    { title: 'Edit', icon: 'pencil', onPress: () => edit(c) },
    ...(!c.parentId ? [{ title: 'Add Subcategory', icon: 'plus', onPress: () => router.push({ pathname: '/category-form', params: { kind, parentId: c.id } }) }] : []),
    { title: 'Move Up', icon: 'arrow.up', disabled: index === 0, onPress: () => move(siblings, index, -1) },
    { title: 'Move Down', icon: 'arrow.down', disabled: index === siblings.length - 1, onPress: () => move(siblings, index, 1) },
    { title: 'Merge Into…', icon: 'arrow.triangle.merge', onPress: () => merge(c) },
    'separator',
    {
      title: 'Archive',
      icon: 'archivebox',
      destructive: true,
      onPress: () =>
        setCategoryArchived(appDb, c.id, true).then(() =>
          toast({ message: `${c.name} archived`, actionLabel: 'Undo', onAction: () => setCategoryArchived(appDb, c.id, false) }),
        ),
    },
  ];

  const row = (c: Category, siblings: Category[], index: number, child = false) => (
    <Menu key={c.id} items={menu(c, siblings, index)}>
      {(open) => (
        <GroupRow
          title={child ? `   ${c.name}` : c.name}
          leading={<CategoryIcon icon={c.icon} color={c.color} size={child ? 26 : 30} />}
          onPress={() => edit(c)}
          onLongPress={open}
          accessibilityHint="Long-press for reorder, merge and archive"
          trailing={<Icon name="ellipsis" size={16} color={colors.secondary} />}
        />
      )}
    </Menu>
  );

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}>
        <LargeTitle title="Categories" />
        <View style={{ paddingHorizontal: 16, marginTop: 14 }}>
          <SegmentedControl
            value={kind}
            onChange={setKind}
            segments={[
              { value: 'expense', label: 'Expense' },
              { value: 'income', label: 'Income' },
            ]}
          />
        </View>
        <View style={{ height: 14 }} />
        <InsetGroup dividerInset={58}>
          {parents.flatMap((p, i) => {
            const children = active.filter((c) => c.parentId === p.id);
            return [row(p, parents, i), ...children.map((c, j) => row(c, children, j, true))];
          })}
        </InsetGroup>
        {archived.length ? (
          <>
            <GroupHeader title="Archived" />
            <InsetGroup dividerInset={58}>
              {archived.map((c) => (
                <GroupRow
                  key={c.id}
                  title={c.name}
                  leading={<CategoryIcon icon={c.icon} color={c.color} size={30} />}
                  value="Restore"
                  onPress={() => setCategoryArchived(appDb, c.id, false)}
                />
              ))}
            </InsetGroup>
          </>
        ) : null}
      </ScrollView>
      <TopBar
        title="Categories"
        scrollY={scrollY}
        leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />}
        trailing={<GlassButton icon="plus" accessibilityLabel="New category" onPress={() => router.push({ pathname: '/category-form', params: { kind } })} />}
      />
    </View>
  );
}
