import { format } from 'date-fns';
import { eq } from 'drizzle-orm';
import * as Haptics from 'expo-haptics';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, ScrollView, View } from 'react-native';

import { appDb } from '@/db/client';
import { type RecurringFrequency, recurringRules, type TransactionType } from '@/db/schema';
import { accountIcon } from '@/features/accounts/presentation';
import { accountsWithBalance } from '@/features/accounts/queries';
import { categoriesByKind } from '@/features/categories/queries';
import { createRecurring, deleteRecurring, describeFrequency, type RecurringInput, updateRecurring } from '@/features/recurring/recurring';
import { listTransactions } from '@/features/transactions/list';
import { useQuery } from '@/hooks/useQuery';
import { accountLabel } from '@/lib/format';
import { formatINR, tryToPaise } from '@/lib/money';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { DateTimeSheet, pickDateTimeAndroid } from '@/ui/DateTimeSheet';
import { FieldRow } from '@/ui/FieldRow';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { Menu } from '@/ui/Menu';
import { SegmentedControl } from '@/ui/SegmentedControl';
import { SheetHeader, useSheetBackground } from '@/ui/SheetHeader';

const FREQUENCIES: RecurringFrequency[] = ['daily', 'weekly', 'monthly', 'yearly'];
const UNIT: Record<RecurringFrequency, string> = { daily: 'day', weekly: 'week', monthly: 'month', yearly: 'year' };

function rupees(paise: number) {
  return formatINR(paise, { symbol: false, decimals: 'auto' }).replace(/,/g, '');
}

export default function RecurringFormScreen() {
  const params = useLocalSearchParams<{ id?: string; fromTransaction?: string }>();
  const { colors } = useTheme();
  const background = useSheetBackground();
  const [kind, setKind] = useState<TransactionType>('expense');
  const [amount, setAmount] = useState('');
  const [payee, setPayee] = useState('');
  const [note, setNote] = useState('');
  const [accountId, setAccountId] = useState<string | undefined>();
  const [toAccountId, setToAccountId] = useState<string | undefined>();
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [frequency, setFrequency] = useState<RecurringFrequency>('monthly');
  const [interval, setInterval] = useState(1);
  const [startAt, setStartAt] = useState(() => Date.now());
  const [endAt, setEndAt] = useState<number | null>(null);
  const [picking, setPicking] = useState<'start' | 'end' | null>(null);

  const { data: accounts } = useQuery(() => accountsWithBalance(appDb), [], []);
  const catKind = kind === 'income' ? 'income' : 'expense';
  const { data: cats } = useQuery(() => categoriesByKind(appDb, catKind), [catKind], []);

  useEffect(() => {
    (async () => {
      if (params.id) {
        const r = await appDb.select().from(recurringRules).where(eq(recurringRules.id, params.id)).get();
        if (!r) return;
        setKind(r.type);
        setAmount(rupees(r.amount));
        setPayee(r.payee ?? '');
        setNote(r.note ?? '');
        setAccountId(r.accountId);
        setToAccountId(r.toAccountId ?? undefined);
        setCategoryId(r.categoryId);
        setFrequency(r.frequency);
        setInterval(r.interval);
        setStartAt(r.startAt);
        setEndAt(r.endAt);
      } else if (params.fromTransaction) {
        const [t] = await listTransactions(appDb, { id: params.fromTransaction });
        if (!t) return;
        setKind(t.type);
        setAmount(rupees(t.amount));
        setPayee(t.payee ?? '');
        setNote(t.note ?? '');
        setAccountId(t.accountId);
        setToAccountId(t.toAccountId ?? undefined);
        setCategoryId(t.categoryId);
        setStartAt(t.occurredAt);
      }
    })();
  }, [params.id, params.fromTransaction]);

  const fromId = accountId ?? accounts[0]?.id;
  const account = accounts.find((a) => a.id === fromId);
  const toAccount = accounts.find((a) => a.id === toAccountId);
  const category = cats.find((c) => c.id === categoryId);
  const paise = tryToPaise(amount || '0') ?? 0;

  const save = async () => {
    if (!fromId) return Alert.alert('Add an account first');
    const input: RecurringInput = {
      type: kind,
      amount: paise,
      accountId: fromId,
      toAccountId: kind === 'transfer' ? toAccountId : null,
      categoryId: kind === 'transfer' ? null : categoryId,
      payee,
      note,
      frequency,
      interval,
      startAt,
      endAt,
    };
    try {
      if (params.id) await updateRecurring(appDb, params.id, input);
      else await createRecurring(appDb, input, { firstAlreadyAdded: Boolean(params.fromTransaction) });
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      router.back();
    } catch (e) {
      Alert.alert('Can’t save', e instanceof Error ? e.message : String(e));
    }
  };

  const pickDate = (which: 'start' | 'end') => {
    const current = which === 'start' ? startAt : (endAt ?? startAt);
    const apply = (ms: number) => (which === 'start' ? setStartAt(ms) : setEndAt(ms));
    if (Platform.OS === 'ios') setPicking(which);
    else pickDateTimeAndroid(current, apply);
  };
  const accountItems = (select: (id: string) => void, exclude?: string) =>
    accounts.filter((a) => a.id !== exclude).map((a) => ({ title: accountLabel(a.name, a.last4), icon: accountIcon(a.type), onPress: () => select(a.id) }));
  const square = (icon: string, color: string) => <CategoryIcon icon={icon} color={color} size={28} square />;

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: background }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <SheetHeader title={params.id ? 'Edit Recurring' : 'New Recurring'} onSave={save} canSave={paise > 0} />
      <ScrollView contentContainerStyle={{ paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
        <View style={{ paddingHorizontal: 16 }}>
          <SegmentedControl
            value={kind}
            onChange={(k) => {
              setKind(k);
              setCategoryId(null);
            }}
            segments={[
              { value: 'expense', label: 'Expense', color: colors.expense },
              { value: 'income', label: 'Income', color: colors.income },
              { value: 'transfer', label: 'Transfer', color: colors.accent },
            ]}
          />
        </View>
        <GroupHeader title="Details" />
        <InsetGroup dividerInset={16}>
          <FieldRow label="Amount" value={amount} onChangeText={setAmount} placeholder="₹0" keyboardType="decimal-pad" autoFocus={!params.id && !params.fromTransaction} />
          <FieldRow label="Payee" value={payee} onChangeText={setPayee} placeholder={kind === 'income' ? 'Employer' : 'Landlord, Netflix…'} />
          <FieldRow label="Note" value={note} onChangeText={setNote} placeholder="Optional" />
        </InsetGroup>
        <View style={{ height: 18 }} />
        <InsetGroup dividerInset={54}>
          <Menu items={accountItems(setAccountId)}>
            {(open) => (
              <GroupRow
                title={kind === 'transfer' ? 'From' : 'Account'}
                value={account ? accountLabel(account.name, account.last4) : 'Choose'}
                leading={square(account ? accountIcon(account.type) : 'creditcard.fill', account?.color ?? colors.secondary)}
                chevron
                onPress={open}
              />
            )}
          </Menu>
          {kind === 'transfer' ? (
            <Menu items={accountItems(setToAccountId, fromId)}>
              {(open) => (
                <GroupRow
                  title="To"
                  value={toAccount ? accountLabel(toAccount.name, toAccount.last4) : 'Choose'}
                  leading={square(toAccount ? accountIcon(toAccount.type) : 'creditcard.fill', toAccount?.color ?? colors.secondary)}
                  chevron
                  onPress={open}
                />
              )}
            </Menu>
          ) : (
            <Menu
              items={[
                { title: 'Uncategorised', checked: !categoryId, onPress: () => setCategoryId(null) },
                'separator',
                ...cats.map((c) => ({ title: c.parentId ? `  ${c.name}` : c.name, icon: c.icon, checked: c.id === categoryId, onPress: () => setCategoryId(c.id) })),
              ]}
            >
              {(open) => (
                <GroupRow
                  title="Category"
                  value={category?.name ?? 'Uncategorised'}
                  leading={square(category?.icon ?? 'questionmark', category?.color ?? '#8E8E93')}
                  chevron
                  onPress={open}
                />
              )}
            </Menu>
          )}
        </InsetGroup>
        <GroupHeader title="Schedule" />
        <InsetGroup dividerInset={54}>
          <Menu
            items={FREQUENCIES.map((f) => ({
              title: describeFrequency({ frequency: f, interval: 1 }),
              checked: f === frequency,
              onPress: () => setFrequency(f),
            }))}
          >
            {(open) => <GroupRow title="Repeats" value={describeFrequency({ frequency, interval: 1 })} leading={square('repeat', '#30B0C7')} chevron onPress={open} />}
          </Menu>
          <Menu
            items={Array.from({ length: 12 }, (_, i) => ({
              title: i === 0 ? `Every ${UNIT[frequency]}` : `Every ${i + 1} ${UNIT[frequency]}s`,
              checked: interval === i + 1,
              onPress: () => setInterval(i + 1),
            }))}
          >
            {(open) => (
              <GroupRow
                title="Every"
                value={interval === 1 ? UNIT[frequency] : `${interval} ${UNIT[frequency]}s`}
                leading={square('arrow.clockwise', '#5E5CE6')}
                chevron
                onPress={open}
              />
            )}
          </Menu>
          <GroupRow title={params.fromTransaction ? 'First (already added)' : 'Starts'} value={format(startAt, 'd MMM yyyy')} leading={square('calendar', '#FF3B30')} chevron onPress={() => pickDate('start')} />
          <Menu
            items={[
              { title: 'Never', checked: endAt === null, onPress: () => setEndAt(null) },
              { title: 'Pick End Date…', icon: 'calendar', onPress: () => pickDate('end') },
            ]}
          >
            {(open) => <GroupRow title="Ends" value={endAt ? format(endAt, 'd MMM yyyy') : 'Never'} leading={square('calendar.badge.clock', '#FF9500')} chevron onPress={open} />}
          </Menu>
        </InsetGroup>
        {params.id ? (
          <InsetGroup style={{ marginTop: 24 }}>
            <GroupRow
              title="Delete Rule"
              destructive
              onPress={() =>
                Alert.alert('Delete this rule?', 'Transactions it already added stay.', [
                  { text: 'Cancel', style: 'cancel' },
                  { text: 'Delete', style: 'destructive', onPress: () => deleteRecurring(appDb, params.id!).then(() => router.back()) },
                ])
              }
            />
          </InsetGroup>
        ) : null}
      </ScrollView>
      <DateTimeSheet
        visible={picking !== null}
        value={picking === 'end' ? (endAt ?? startAt) : startAt}
        onClose={() => setPicking(null)}
        onChange={(ms) => (picking === 'end' ? setEndAt(ms) : setStartAt(ms))}
      />
    </KeyboardAvoidingView>
  );
}
