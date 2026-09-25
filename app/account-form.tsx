import * as Haptics from 'expo-haptics';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, ScrollView, Switch, View } from 'react-native';

import { appDb } from '@/db/client';
import type { AccountType } from '@/db/schema';
import { AccountCard } from '@/features/accounts/AccountCard';
import { type AccountInput, createAccount, updateAccount } from '@/features/accounts/mutations';
import { accountIcon } from '@/features/accounts/presentation';
import { accountsWithBalance } from '@/features/accounts/queries';
import { formatINR, tryToPaise } from '@/lib/money';
import { useTheme } from '@/theme/useTheme';
import { ColorPicker } from '@/ui/ColorPicker';
import { FieldRow } from '@/ui/FieldRow';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { SegmentedControl } from '@/ui/SegmentedControl';
import { SheetHeader, useSheetBackground } from '@/ui/SheetHeader';

const DEFAULT_COLORS: Record<AccountType, string> = { bank: '#5E5CE6', card: '#FF2D55', cash: '#34C759', wallet: '#FF9500' };

function rupees(paise: number | null | undefined): string {
  return paise ? formatINR(paise, { symbol: false, decimals: 'auto' }).replace(/,/g, '') : '';
}

export default function AccountFormScreen() {
  const { id } = useLocalSearchParams<{ id?: string }>();
  const { colors } = useTheme();
  const background = useSheetBackground();
  const [kind, setKind] = useState<AccountType>('bank');
  const [name, setName] = useState('');
  const [institution, setInstitution] = useState('');
  const [last4, setLast4] = useState('');
  const [opening, setOpening] = useState('');
  const [limit, setLimit] = useState('');
  const [statementDay, setStatementDay] = useState('');
  const [dueDay, setDueDay] = useState('');
  const [color, setColor] = useState<string | null>(null);
  const [exclude, setExclude] = useState(false);
  const [currentBalance, setCurrentBalance] = useState<number | null>(null);

  useEffect(() => {
    if (!id) return;
    accountsWithBalance(appDb, { includeArchived: true }).then((rows) => {
      const a = rows.find((r) => r.id === id);
      if (!a) return;
      setKind(a.type);
      setName(a.name);
      setInstitution(a.institution ?? '');
      setLast4(a.last4 ?? '');
      // Cards: show the amount owed as a positive number.
      setOpening(rupees(a.type === 'card' ? -a.openingBalance : a.openingBalance));
      setLimit(rupees(a.creditLimit));
      setStatementDay(a.statementDay ? String(a.statementDay) : '');
      setDueDay(a.dueDay ? String(a.dueDay) : '');
      setColor(a.color);
      setExclude(a.excludeFromTotals);
      setCurrentBalance(a.balance);
    });
  }, [id]);

  const isCard = kind === 'card';
  const openingPaise = tryToPaise(opening || '0') ?? 0;
  const effectiveColor = color ?? DEFAULT_COLORS[kind];

  const save = async () => {
    const input: AccountInput = {
      name,
      type: kind,
      institution,
      last4,
      openingBalance: isCard ? -openingPaise : openingPaise,
      color: effectiveColor,
      icon: accountIcon(kind),
      creditLimit: isCard ? tryToPaise(limit || '0') || null : null,
      statementDay: isCard && statementDay ? Number(statementDay) : null,
      dueDay: isCard && dueDay ? Number(dueDay) : null,
      excludeFromTotals: exclude,
    };
    try {
      if (id) await updateAccount(appDb, id, input);
      else await createAccount(appDb, input);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      router.back();
    } catch (e) {
      Alert.alert('Can’t save', e instanceof Error ? e.message : String(e));
    }
  };

  const preview = {
    id: 'preview',
    name: name || 'Account name',
    type: kind,
    institution,
    last4: /^\d{4}$/.test(last4) ? last4 : null,
    openingBalance: 0,
    currency: 'INR',
    creditLimit: tryToPaise(limit || '0') || null,
    statementDay: null,
    dueDay: dueDay ? Number(dueDay) : null,
    color: effectiveColor,
    icon: accountIcon(kind),
    sortOrder: 0,
    excludeFromTotals: exclude,
    archivedAt: null,
    createdAt: 0,
    updatedAt: 0,
  };

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: background }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <SheetHeader title={id ? 'Edit Account' : 'New Account'} onSave={save} canSave={name.trim().length > 0} />
      <ScrollView contentContainerStyle={{ paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
        <View style={{ paddingHorizontal: 16 }}>
          <AccountCard account={preview} balance={currentBalance ?? (isCard ? -openingPaise : openingPaise)} showHeaderBalance={false} />
        </View>
        <View style={{ paddingHorizontal: 16, marginTop: 16 }}>
          <SegmentedControl
            value={kind}
            onChange={setKind}
            segments={[
              { value: 'bank', label: 'Bank' },
              { value: 'card', label: 'Card' },
              { value: 'cash', label: 'Cash' },
              { value: 'wallet', label: 'Wallet' },
            ]}
          />
        </View>
        <GroupHeader title="Details" />
        <InsetGroup dividerInset={16}>
          <FieldRow label="Name" value={name} onChangeText={setName} placeholder={isCard ? 'Axis MyZone' : 'Axis Bank'} autoFocus={!id} />
          {kind !== 'cash' ? <FieldRow label="Bank / provider" value={institution} onChangeText={setInstitution} placeholder="Optional" /> : null}
          {kind === 'bank' || isCard ? (
            <FieldRow label="Last 4 digits" value={last4} onChangeText={(t) => setLast4(t.replace(/\D/g, '').slice(0, 4))} placeholder="Optional" keyboardType="number-pad" />
          ) : null}
          <FieldRow
            label={isCard ? 'Amount owed now' : 'Opening balance'}
            value={opening}
            onChangeText={setOpening}
            placeholder="₹0"
            keyboardType="decimal-pad"
          />
        </InsetGroup>
        {isCard ? (
          <>
            <GroupHeader title="Credit card" />
            <InsetGroup dividerInset={16}>
              <FieldRow label="Credit limit" value={limit} onChangeText={setLimit} placeholder="Optional" keyboardType="decimal-pad" />
              <FieldRow label="Statement day" value={statementDay} onChangeText={(t) => setStatementDay(t.replace(/\D/g, '').slice(0, 2))} placeholder="1–31" keyboardType="number-pad" />
              <FieldRow label="Due day" value={dueDay} onChangeText={(t) => setDueDay(t.replace(/\D/g, '').slice(0, 2))} placeholder="1–31" keyboardType="number-pad" />
            </InsetGroup>
          </>
        ) : null}
        <GroupHeader title="Colour" />
        <ColorPicker value={effectiveColor} onChange={setColor} />
        <GroupHeader title="Totals" />
        <InsetGroup>
          <GroupRow title="Include in net worth" trailing={<Switch value={!exclude} onValueChange={(v) => setExclude(!v)} trackColor={{ true: colors.income }} />} />
        </InsetGroup>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
