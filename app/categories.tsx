import { router } from 'expo-router';
import { useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import type { Category, CategoryKind } from '@/db/schema';
import { mergeCategory, reorderCategories, setCategoryArchived } from '@/features/categories/mutations';
import { categoriesByKind } from '@/features/categories/queries';
import { useQuery } from '@/hooks/useQuery';
import { useToast } from '@/stores/toast';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { GlassButton, GlassGroup } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { Menu, type MenuItem } from '@/ui/Menu';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';
import { SegmentedControl } from '@/ui/SegmentedControl';
import { SortableList } from '@/ui/SortableList';

export default function CategoriesScreen() {
  const { colors } = useTheme();
  const toast = useToast((s) => s.show);
  const [kind, setKind] = useState<CategoryKind>('expense');
  const [reordering, setReordering] = useState(false);
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const { data: all } = useQuery(() => categoriesByKind(appDb, kind, { includeArchived: true }), [kind], []);
  const active = all.filter((c) => !c.archivedAt);
  const archived = all.filter((c) => c.archivedAt);
  const parents = active.filter((c) => !c.parentId);

  const edit = (c: Category) => router.push({ pathname: '/category-form', params: { id: c.id } });
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
  const menu = (c: Category): MenuItem[] => [
    { title: 'Edit', icon: 'pencil', onPress: () => edit(c) },
    ...(!c.parentId ? [{ title: 'Add Subcategory', icon: 'plus', onPress: () => router.push({ pathname: '/category-form', params: { kind, parentId: c.id } }) }] : []),
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

  const sortRow = (c: Category) => (
    <View style={styles.sortRow}>
      <CategoryIcon icon={c.icon} color={c.color} size={30} />
      <Text style={[type.body, { color: colors.label, flex: 1 }]} numberOfLines={1}>
        {c.name}
      </Text>
    </View>
  );

  const row = (c: Category, child = false) => (
    <Menu key={c.id} items={menu(c)}>
      {(open) => (
        <GroupRow
          title={child ? `   ${c.name}` : c.name}
          leading={<CategoryIcon icon={c.icon} color={c.color} size={child ? 26 : 30} />}
          onPress={() => edit(c)}
          onLongPress={open}
          accessibilityHint="Long-press for more: add subcategory, merge, archive"
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
        {reordering ? (
          <>
            <GroupHeader title="Categories" />
            <SortableList data={parents} keyOf={(c) => c.id} onReorder={(ids) => reorderCategories(appDb, ids)} renderRow={sortRow} />
            {parents
              .filter((p) => active.some((c) => c.parentId === p.id))
              .map((p) => (
                <View key={p.id}>
                  <GroupHeader title={p.name} />
                  <SortableList
                    data={active.filter((c) => c.parentId === p.id)}
                    keyOf={(c) => c.id}
                    onReorder={(ids) => reorderCategories(appDb, ids)}
                    renderRow={sortRow}
                  />
                </View>
              ))}
          </>
        ) : (
          <InsetGroup dividerInset={58}>
            {parents.flatMap((p) => [row(p), ...active.filter((c) => c.parentId === p.id).map((c) => row(c, true))])}
          </InsetGroup>
        )}
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
        trailing={
          <GlassGroup>
            <GlassButton
              icon={reordering ? 'checkmark' : 'arrow.up.arrow.down'}
              tint={reordering ? colors.accent : undefined}
              accessibilityLabel={reordering ? 'Done reordering' : 'Reorder categories'}
              onPress={() => setReordering(!reordering)}
            />
            {!reordering ? (
              <GlassButton icon="plus" accessibilityLabel="New category" onPress={() => router.push({ pathname: '/category-form', params: { kind } })} />
            ) : null}
          </GlassGroup>
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  sortRow: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12, paddingLeft: 16 },
});
