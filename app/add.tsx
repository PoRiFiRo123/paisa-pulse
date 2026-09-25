import * as Haptics from 'expo-haptics';
import { isLiquidGlassAvailable } from 'expo-glass-effect';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withRepeat, withTiming } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { appDb } from '@/db/client';
import type { TransactionType } from '@/db/schema';
import { accountIcon } from '@/features/accounts/presentation';
import { accountsWithBalance } from '@/features/accounts/queries';
import { categoriesByKind } from '@/features/categories/queries';
import { listTransactions, recentCategoryIds } from '@/features/transactions/list';
import { createTransaction, updateTransaction } from '@/features/transactions/mutations';
import { TransactionValidationError } from '@/features/transactions/validation';
import { useQuery } from '@/hooks/useQuery';
import { accountLabel, dateTimeLabel } from '@/lib/format';
import { evaluateAmountExpression, formatINR } from '@/lib/money';
import { usePrefs } from '@/stores/prefs';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryChip } from '@/ui/CategoryCapsule';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { DateTimeSheet, pickDateTimeAndroid } from '@/ui/DateTimeSheet';
import { GlassButton } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { applyKey, Keypad } from '@/ui/Keypad';
import { Menu } from '@/ui/Menu';
import { SegmentedControl } from '@/ui/SegmentedControl';

type Params = { id?: string; type?: TransactionType; from?: string; to?: string; amount?: string };

/** "Swiggy · lunch with team" → payee "Swiggy", note "lunch with team". */
function splitPayeeNote(text: string): { payee: string | null; note: string | null } {
  const [payee, ...rest] = text.split('·');
  return { payee: payee.trim() || null, note: rest.join('·').trim() || null };
}

/** "125000+45.5" → "1,25,000+45.5" for the amount display. */
function groupExpression(expr: string): string {
  return expr.replace(/\d+(\.\d*)?/g, (num) => {
    const [whole, frac] = num.split('.');
    return Number(whole).toLocaleString('en-IN') + (frac !== undefined ? `.${frac}` : '');
  });
}

function paiseToExpr(paise: number): string {
  return formatINR(paise, { symbol: false, decimals: 'auto' }).replace(/,/g, '');
}

export default function QuickAddScreen() {
  const params = useLocalSearchParams<Params>();
  const editing = Boolean(params.id);
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const lastAccountId = usePrefs((s) => s.lastAccountId);

  const [kind, setKind] = useState<TransactionType>(params.type ?? 'expense');
  const [expr, setExpr] = useState(params.amount ? paiseToExpr(Number(params.amount)) : '');
  const [text, setText] = useState('');
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [accountId, setAccountId] = useState<string | undefined>(params.from);
  const [toAccountId, setToAccountId] = useState<string | undefined>(params.to);
  const [occurredAt, setOccurredAt] = useState(() => Date.now());
  const [showAll, setShowAll] = useState(false);
  const [picking, setPicking] = useState(false);

  const { data: accounts } = useQuery(() => accountsWithBalance(appDb), [], []);
  const categoryKind = kind === 'income' ? 'income' : 'expense';
  const { data: categories } = useQuery(() => categoriesByKind(appDb, categoryKind), [categoryKind], []);
  const { data: recentIds } = useQuery(() => recentCategoryIds(appDb, categoryKind), [categoryKind], []);

  // Edit mode: load the transaction once.
  useEffect(() => {
    if (!params.id) return;
    listTransactions(appDb, { id: params.id }).then(([t]) => {
      if (!t) return;
      setKind(t.type);
      setExpr(paiseToExpr(t.amount));
      setText([t.payee, t.note].filter(Boolean).join(' · '));
      setCategoryId(t.categoryId);
      setAccountId(t.accountId);
      setToAccountId(t.toAccountId ?? undefined);
      setOccurredAt(t.occurredAt);
    });
  }, [params.id]);

  // Defaults are derived, not stored: last used account, and for transfers a card to pay.
  const fromId = accountId ?? accounts.find((a) => a.id === lastAccountId)?.id ?? accounts[0]?.id;
  const toId =
    toAccountId ??
    (kind === 'transfer'
      ? (accounts.find((a) => a.id !== fromId && a.type === 'card')?.id ?? accounts.find((a) => a.id !== fromId)?.id)
      : undefined);

  const amount = evaluateAmountExpression(expr);
  const hasOperator = /[+−×÷]/.test(expr);
  const kindColor = kind === 'expense' ? colors.expense : kind === 'income' ? colors.income : colors.accent;

  const chips = useMemo(() => {
    const byId = new Map(categories.map((c) => [c.id, c]));
    const recent = recentIds.map((id) => byId.get(id)).filter((c): c is NonNullable<typeof c> => Boolean(c));
    const rest = categories.filter((c) => !c.parentId && !recentIds.includes(c.id));
    const list = [...recent, ...rest];
    // Keep the selected category visible even if it is a subcategory.
    const selected = categoryId ? byId.get(categoryId) : undefined;
    if (selected && !list.includes(selected)) list.unshift(selected);
    return list;
  }, [categories, recentIds, categoryId]);

  const account = accounts.find((a) => a.id === fromId);
  const toAccount = accounts.find((a) => a.id === toId);

  const save = async () => {
    if (!amount || amount <= 0) {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error).catch(() => {});
      return;
    }
    if (!fromId) {
      Alert.alert('Add an account first', 'Transactions need an account.', [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Add Account', onPress: () => router.replace('/account-form') },
      ]);
      return;
    }
    const { payee, note } = splitPayeeNote(text);
    const input = {
      type: kind,
      amount,
      accountId: fromId,
      toAccountId: kind === 'transfer' ? toId : null,
      categoryId: kind === 'transfer' ? null : categoryId,
      payee,
      note,
      occurredAt,
    };
    try {
      if (params.id) await updateTransaction(appDb, params.id, input);
      else await createTransaction(appDb, input);
      usePrefs.getState().set('lastAccountId', fromId);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      router.back();
    } catch (e) {
      const message =
        e instanceof TransactionValidationError
          ? e.errors.map((x) => VALIDATION_MESSAGES[x.code]).join('\n')
          : String(e);
      Alert.alert('Can’t save', message);
    }
  };

  const title = `${editing ? 'Edit' : 'New'} ${kind === 'expense' ? 'Expense' : kind === 'income' ? 'Income' : 'Transfer'}`;
  const accountMenu = (select: (id: string) => void, exclude?: string) =>
    accounts
      .filter((a) => a.id !== exclude)
      .map((a) => ({ title: accountLabel(a.name, a.last4), icon: accountIcon(a.type), onPress: () => select(a.id) }));

  const onPickDate = () => (Platform.OS === 'ios' ? setPicking(true) : pickDateTimeAndroid(occurredAt, setOccurredAt));

  return (
    <View style={[styles.sheet, { backgroundColor: isLiquidGlassAvailable() ? 'transparent' : colors.background, paddingBottom: Math.max(insets.bottom, 16) }]}>
      <View style={styles.toolbar}>
        <GlassButton icon="xmark" accessibilityLabel="Cancel" onPress={() => router.back()} />
        <Text style={[type.headline, { color: colors.label }]}>{title}</Text>
        <GlassButton
          icon="checkmark"
          accessibilityLabel="Save"
          tint={amount && amount > 0 ? colors.accent : undefined}
          iconColor={amount && amount > 0 ? '#FFFFFF' : colors.secondary}
          onPress={save}
        />
      </View>

      <View style={styles.pad}>
        <SegmentedControl
          value={kind}
          onChange={(k) => {
            setKind(k);
            setCategoryId(null);
            setShowAll(false);
          }}
          segments={[
            { value: 'expense', label: 'Expense', color: colors.expense },
            { value: 'income', label: 'Income', color: colors.income },
            { value: 'transfer', label: 'Transfer', color: colors.accent },
          ]}
        />
      </View>

      <View style={styles.amountWrap} accessibilityLabel={`Amount ${amount ? formatINR(amount, { decimals: 'auto' }) : 'empty'}`}>
        <View style={styles.amountRow}>
          <Text style={[styles.rupee, { color: expr ? colors.label : colors.secondary }]}>₹</Text>
          <Text style={[styles.amount, { color: expr ? colors.label : colors.secondary }]} numberOfLines={1} adjustsFontSizeToFit>
            {expr ? groupExpression(expr) : '0'}
          </Text>
          <Caret color={kindColor} />
        </View>
        <Text style={[type.subhead, { color: colors.secondary, height: 20 }]}>
          {hasOperator && amount !== null ? `= ${formatINR(amount, { decimals: 'auto' })}` : ''}
        </Text>
      </View>

      <View style={[styles.note]}>
        <Icon name="pencil" size={14} color={colors.secondary} />
        <TextInput
          value={text}
          onChangeText={setText}
          placeholder={kind === 'transfer' ? 'Note' : 'Payee · note'}
          placeholderTextColor={colors.secondary}
          style={[type.subhead, styles.noteInput, { color: colors.label }]}
          returnKeyType="done"
          accessibilityLabel="Payee and note. Separate them with a dot."
        />
      </View>

      {kind !== 'transfer' ? (
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          style={styles.chipScroller}
          contentContainerStyle={styles.chips}
          keyboardShouldPersistTaps="handled"
        >
          {chips.map((c) => (
            <CategoryChip
              key={c.id}
              name={c.name}
              icon={c.icon}
              color={c.color}
              selected={c.id === categoryId}
              onPress={() => {
                Haptics.selectionAsync().catch(() => {});
                setCategoryId(c.id === categoryId ? null : c.id);
              }}
            />
          ))}
          <CategoryChip name={showAll ? 'Keypad' : 'All'} icon={showAll ? 'number' : 'square.grid.2x2'} color={colors.secondary} onPress={() => setShowAll(!showAll)} />
        </ScrollView>
      ) : null}

      <InsetGroup style={styles.group} dividerInset={54}>
        <Menu items={accountMenu(setAccountId)}>
          {(open) => (
            <GroupRow
              title={kind === 'transfer' ? 'From' : 'Account'}
              value={account ? accountLabel(account.name, account.last4) : 'Choose'}
              leading={<CategoryIcon icon={account ? accountIcon(account.type) : 'creditcard.fill'} color={account?.color ?? colors.secondary} size={28} square />}
              chevron
              height={48}
              onPress={accounts.length ? open : () => router.replace('/account-form')}
            />
          )}
        </Menu>
        {kind === 'transfer' ? (
          <Menu items={accountMenu(setToAccountId, fromId)}>
            {(open) => (
              <GroupRow
                title="To"
                value={toAccount ? accountLabel(toAccount.name, toAccount.last4) : 'Choose'}
                leading={<CategoryIcon icon={toAccount ? accountIcon(toAccount.type) : 'creditcard.fill'} color={toAccount?.color ?? colors.secondary} size={28} square />}
                chevron
                height={48}
                onPress={open}
              />
            )}
          </Menu>
        ) : null}
        <Menu
          items={[
            { title: 'Now', icon: 'clock', onPress: () => setOccurredAt(Date.now()) },
            { title: 'Yesterday', icon: 'calendar', onPress: () => setOccurredAt(Date.now() - 86_400_000) },
            { title: 'Pick Date & Time…', icon: 'calendar.badge.clock', onPress: onPickDate },
          ]}
        >
          {(open) => (
            <GroupRow
              title="Date"
              value={dateTimeLabel(occurredAt)}
              leading={<CategoryIcon icon="calendar" color="#FF3B30" size={28} square />}
              chevron
              height={48}
              onPress={open}
            />
          )}
        </Menu>
      </InsetGroup>

      <View style={[styles.pad, { flex: 1, justifyContent: 'flex-end' }]}>
        {showAll && kind !== 'transfer' ? (
          <CategoryGrid
            categories={categories}
            selected={categoryId}
            onSelect={(id) => {
              setCategoryId(id);
              setShowAll(false);
            }}
          />
        ) : (
          <Keypad onKey={(k) => setExpr((e) => applyKey(e, k))} />
        )}
      </View>

      <DateTimeSheet visible={picking} value={occurredAt} onClose={() => setPicking(false)} onChange={setOccurredAt} />
    </View>
  );
}

function CategoryGrid({
  categories,
  selected,
  onSelect,
}: {
  categories: { id: string; name: string; icon: string; color: string; parentId: string | null }[];
  selected: string | null;
  onSelect: (id: string) => void;
}) {
  const { colors } = useTheme();
  const parents = categories.filter((c) => !c.parentId);
  return (
    <ScrollView style={{ maxHeight: 300 }} contentContainerStyle={styles.grid}>
      {parents.flatMap((p) => [p, ...categories.filter((c) => c.parentId === p.id)]).map((c) => (
        <Pressable
          key={c.id}
          onPress={() => onSelect(c.id)}
          accessibilityRole="button"
          accessibilityState={{ selected: c.id === selected }}
          style={[styles.gridItem, c.id === selected && { backgroundColor: `${c.color}26` }]}
        >
          <CategoryIcon icon={c.icon} color={c.color} size={40} />
          <Text style={[type.caption, { color: colors.label, textAlign: 'center' }]} numberOfLines={2}>
            {c.name}
          </Text>
        </Pressable>
      ))}
    </ScrollView>
  );
}

function Caret({ color }: { color: string }) {
  const opacity = useSharedValue(1);
  useEffect(() => {
    opacity.value = withRepeat(withTiming(0, { duration: 530 }), -1, true);
  }, [opacity]);
  const style = useAnimatedStyle(() => ({ opacity: opacity.value }));
  return <Animated.View style={[styles.caret, { backgroundColor: color }, style]} />;
}

const VALIDATION_MESSAGES: Record<string, string> = {
  amount_not_positive: 'Enter an amount above zero.',
  amount_not_integer: 'That amount has too many decimals.',
  account_required: 'Choose an account.',
  to_account_required: 'Choose the account the money goes to.',
  same_account_transfer: 'A transfer needs two different accounts.',
  to_account_not_allowed: 'Only transfers have a destination account.',
  category_not_allowed: 'Transfers don’t have a category.',
  date_too_far_in_future: 'The date can’t be more than a year ahead.',
};

const styles = StyleSheet.create({
  sheet: { flex: 1, paddingTop: 22 },
  toolbar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16 },
  pad: { paddingHorizontal: 16, marginTop: 14 },
  amountWrap: { alignItems: 'center', marginTop: 12 },
  amountRow: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 24 },
  rupee: { ...type.amount, fontSize: 34, fontWeight: '600', letterSpacing: 0, lineHeight: 44 },
  amount: { ...type.amount, fontSize: 60, lineHeight: 72, flexShrink: 1 },
  caret: { width: 3, height: 54, borderRadius: 2 },
  note: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingHorizontal: 40 },
  noteInput: { minWidth: 120, maxWidth: 280, paddingVertical: 4, textAlign: 'center' },
  // ScrollView grows by default; keep the chip row its natural height so the keypad fits.
  chipScroller: { flexGrow: 0, flexShrink: 0, marginTop: 14 },
  chips: { paddingHorizontal: 16, gap: 8 },
  group: { marginTop: 14 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 4, paddingBottom: 8 },
  gridItem: { width: '23.5%', alignItems: 'center', gap: 4, paddingVertical: 8, borderRadius: 14 },
});
