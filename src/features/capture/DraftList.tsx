import { format, isToday, isYesterday } from 'date-fns';
import * as Haptics from 'expo-haptics';
import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { accountIcon } from '@/features/accounts/presentation';
import { useMoney } from '@/hooks/useMoney';
import { tryToPaise } from '@/lib/money';
import { TRANSFER_COLOR, UNCATEGORISED_COLOR } from '@/theme/tokens';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { Icon } from '@/ui/Icon';
import { InsetGroup } from '@/ui/InsetGroup';
import { Menu, type MenuItem } from '@/ui/Menu';
import { MerchantIcon } from '@/ui/MerchantIcon';
import { NamePrompt } from '@/ui/NamePrompt';

import type { CaptureAccount, CaptureCategory, CaptureDraft } from './drafts';

function when(ms: number): string {
  if (isToday(ms)) return `Today, ${format(ms, 'h:mm a')}`;
  if (isYesterday(ms)) return 'Yesterday';
  return format(ms, 'd MMM');
}

/** Review list for captured drafts: tick to include, tap for category/account/amount/type edits. */
export function DraftList({
  drafts,
  accounts,
  categories,
  onChange,
}: {
  drafts: CaptureDraft[];
  accounts: CaptureAccount[];
  categories: (CaptureCategory & { icon: string; color: string })[];
  onChange: (key: string, patch: Partial<CaptureDraft>) => void;
}) {
  const [prompt, setPrompt] = useState<{ key: string; field: 'amount' | 'payee' | 'note'; value: string } | null>(null);
  if (!drafts.length) return null;
  return (
    <>
      <InsetGroup dividerInset={64}>
        {drafts.map((d) => (
          <DraftRow
            key={d.key}
            d={d}
            accounts={accounts}
            categories={categories}
            onChange={(p) => onChange(d.key, p)}
            onPrompt={(field, value) => setPrompt({ key: d.key, field, value })}
          />
        ))}
      </InsetGroup>
      <NamePrompt
        visible={prompt !== null}
        title={prompt?.field === 'amount' ? 'Amount (₹)' : prompt?.field === 'payee' ? 'Payee' : 'Note'}
        initial={prompt?.value ?? ''}
        keyboardType={prompt?.field === 'amount' ? 'decimal-pad' : 'default'}
        onCancel={() => setPrompt(null)}
        onConfirm={(v) => {
          if (!prompt) return;
          if (prompt.field === 'amount') {
            const paise = tryToPaise(v.replace(/[₹,\s]/g, ''));
            if (paise && paise > 0) onChange(prompt.key, { amount: paise });
          } else onChange(prompt.key, { [prompt.field]: v.trim() || null });
          setPrompt(null);
        }}
      />
    </>
  );
}

function DraftRow({
  d,
  accounts,
  categories,
  onChange,
  onPrompt,
}: {
  d: CaptureDraft;
  accounts: CaptureAccount[];
  categories: (CaptureCategory & { icon: string; color: string })[];
  onChange: (patch: Partial<CaptureDraft>) => void;
  onPrompt: (field: 'amount' | 'payee' | 'note', value: string) => void;
}) {
  const { colors } = useTheme();
  const money = useMoney();
  const category = categories.find((c) => c.id === d.categoryId);
  const account = accounts.find((a) => a.id === d.accountId);
  const to = accounts.find((a) => a.id === d.toAccountId);
  const title = d.payee ?? d.note ?? category?.name ?? (d.type === 'transfer' ? 'Transfer' : d.type === 'income' ? 'Income' : 'Expense');
  const subtitle = [
    d.type === 'transfer' ? `${account?.name ?? '?'} → ${to?.name ?? '?'}` : (category?.name ?? 'Uncategorised'),
    d.type === 'transfer' ? null : account?.name,
    when(d.occurredAt),
  ]
    .filter(Boolean)
    .join(' · ');
  const kind = d.type === 'income' ? 'income' : 'expense';
  const parents = categories.filter((c) => c.kind === kind && !c.parentId);

  const items: MenuItem[] = [
    { title: 'Edit Amount', icon: 'indianrupeesign', onPress: () => onPrompt('amount', String(d.amount / 100)) },
    ...(d.type !== 'transfer' ? [{ title: 'Edit Payee', icon: 'person.crop.circle', onPress: () => onPrompt('payee', d.payee ?? '') }] : []),
    { title: 'Edit Note', icon: 'note.text', onPress: () => onPrompt('note', d.note ?? '') },
    'separator',
    ...(d.type !== 'transfer'
      ? [
          { title: 'Uncategorised', checked: !d.categoryId, onPress: () => onChange({ categoryId: null }) },
          ...parents.flatMap((p) => [p, ...categories.filter((c) => c.parentId === p.id)]).map((c) => ({
            title: c.parentId ? `   ${c.name}` : c.name,
            icon: c.icon,
            checked: c.id === d.categoryId,
            onPress: () => onChange({ categoryId: c.id }),
          })),
          'separator' as const,
        ]
      : []),
    ...accounts
      .filter((a) => a.id !== d.toAccountId)
      .map((a) => ({ title: d.type === 'transfer' ? `From ${a.name}` : a.name, icon: accountIcon(a.type), checked: a.id === d.accountId, onPress: () => onChange({ accountId: a.id }) })),
    'separator',
    ...(['expense', 'income'] as const)
      .filter((t) => t !== d.type)
      .map((t) => ({ title: t === 'income' ? 'Make it Income' : 'Make it an Expense', icon: t === 'income' ? 'arrow.down.left' : 'arrow.up.right', onPress: () => onChange({ type: t, categoryId: null, toAccountId: null }) })),
  ];

  return (
    <View style={[styles.row, { backgroundColor: colors.card, opacity: d.include ? 1 : 0.5 }]}>
      <Pressable
        onPress={() => {
          Haptics.selectionAsync().catch(() => {});
          onChange({ include: !d.include });
        }}
        hitSlop={8}
        accessibilityRole="checkbox"
        accessibilityState={{ checked: d.include }}
        accessibilityLabel={`Include ${title}`}
      >
        <Icon name={d.include ? 'checkmark.circle.fill' : 'circle'} size={24} color={d.include ? colors.accent : colors.secondary} />
      </Pressable>
      <View style={{ flex: 1 }}>
        <Menu items={items}>
          {(open) => (
            <Pressable onPress={open} style={styles.body} accessibilityRole="button" accessibilityHint="Change amount, category, account or type">
              {d.type === 'transfer' ? (
                <CategoryIcon icon="arrow.left.arrow.right" color={TRANSFER_COLOR} size={34} />
              ) : (
                <MerchantIcon name={d.payee} fallbackIcon={category?.icon ?? (account ? accountIcon(account.type) : 'questionmark')} fallbackColor={category?.color ?? UNCATEGORISED_COLOR} size={34} />
              )}
              <View style={{ flex: 1, gap: 2 }}>
                <Text style={[type.body, { color: colors.label }]} numberOfLines={1}>
                  {title}
                </Text>
                <Text style={[type.footnote, { color: colors.secondary }]} numberOfLines={1}>
                  {subtitle}
                </Text>
                {d.warning ? (
                  <Text style={[type.footnote, { color: '#FF9500' }]} numberOfLines={2}>
                    {d.warning}
                  </Text>
                ) : null}
              </View>
              <Text style={[type.bodyAmount, { color: d.type === 'income' ? colors.income : colors.label }]}>{money.signed(d.amount, d.type)}</Text>
            </Pressable>
          )}
        </Menu>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingLeft: 16, paddingRight: 16, paddingVertical: 10, minHeight: 62 },
  body: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12 },
});
