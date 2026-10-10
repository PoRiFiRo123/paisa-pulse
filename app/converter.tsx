import { formatDistanceToNow } from 'date-fns';
import * as Haptics from 'expo-haptics';
import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';

import { appDb } from '@/db/client';
import { CURRENCIES, currencyInfo, formatForeign, minorDigits } from '@/features/currency/currency';
import { getRates, type RatesCache } from '@/features/currency/rates';
import { formatINR } from '@/lib/money';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { GlassButton } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { Divider } from '@/ui/InsetGroup';
import { Menu } from '@/ui/Menu';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';

const QUICK = ['USD', 'EUR', 'GBP', 'AED', 'SGD', 'THB', 'JPY'];

/** Format any currency, INR with lakh/crore grouping. */
function show(value: number, code: string): string {
  if (!Number.isFinite(value)) return '—';
  if (code === 'INR') return formatINR(Math.round(value * 100), { decimals: 'auto' });
  return formatForeign(Math.round(value * 10 ** minorDigits(code)), code);
}

/** Currency converter on the cached exchange rates (refreshed every 12 hours when online). */
export default function ConverterScreen() {
  const { colors } = useTheme();
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const [rates, setRates] = useState<RatesCache | null>(null);
  const [loading, setLoading] = useState(true);
  const [input, setInput] = useState('100');
  const [from, setFrom] = useState('USD');
  const [to, setTo] = useState('INR');

  const load = (force: boolean) =>
    getRates(appDb, { force })
      .then(setRates)
      .finally(() => setLoading(false));
  const refresh = () => {
    setLoading(true);
    load(true);
  };
  useEffect(() => {
    load(false);
  }, []);

  const inrPer = (code: string) => (code === 'INR' ? 1 : (rates?.inrPer[code] ?? NaN));
  const value = Number(input.replace(/,/g, '')) || 0;
  const convert = (amount: number, a: string, b: string) => (amount * inrPer(a)) / inrPer(b);
  const result = convert(value, from, to);
  const menu = (selected: string, onPick: (c: string) => void) =>
    CURRENCIES.map((c) => ({ title: `${c.flag}  ${c.code} · ${c.name}`, checked: c.code === selected, onPress: () => onPick(c.code) }));
  const others = (from === 'INR' ? QUICK : ['INR', ...QUICK.filter((c) => c !== from)]).filter((c) => c !== to).slice(0, 6);

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView
        onScroll={onScroll}
        scrollEventThrottle={16}
        keyboardShouldPersistTaps="handled"
        contentInsetAdjustmentBehavior="never"
        contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}
      >
        <LargeTitle title="Converter" />

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <View style={styles.line}>
            <Menu items={menu(from, setFrom)}>
              {(open) => <CurrencyButton code={from} onPress={open} />}
            </Menu>
            <TextInput
              value={input}
              onChangeText={setInput}
              keyboardType="decimal-pad"
              selectTextOnFocus
              style={[type.amount, styles.input, { color: colors.label }]}
              accessibilityLabel={`Amount in ${currencyInfo(from).name}`}
            />
          </View>
          <View style={styles.swapRow}>
            <Divider />
            <Pressable
              onPress={() => {
                Haptics.selectionAsync().catch(() => {});
                setFrom(to);
                setTo(from);
              }}
              accessibilityRole="button"
              accessibilityLabel="Swap currencies"
              style={[styles.swap, { backgroundColor: colors.fill }]}
            >
              <Icon name="arrow.up.arrow.down" size={16} color={colors.accent} />
            </Pressable>
          </View>
          <View style={styles.line}>
            <Menu items={menu(to, setTo)}>
              {(open) => <CurrencyButton code={to} onPress={open} />}
            </Menu>
            <Text style={[type.amount, styles.input, { color: colors.label }]} numberOfLines={1} adjustsFontSizeToFit accessibilityLiveRegion="polite">
              {rates ? show(result, to) : loading ? '…' : '—'}
            </Text>
          </View>
          {rates && from !== to ? (
            <Text style={[type.footnote, { color: colors.secondary, marginTop: 6 }]}>
              1 {from} = {show(convert(1, from, to), to)} · 1 {to} = {show(convert(1, to, from), from)}
            </Text>
          ) : null}
        </View>

        {rates ? (
          <View style={[styles.card, { backgroundColor: colors.card, paddingVertical: 6 }]}>
            {others.map((c, i) => (
              <View key={c}>
                {i > 0 ? <Divider /> : null}
                <Pressable onPress={() => setTo(c)} style={styles.otherRow} accessibilityRole="button">
                  <Text style={{ fontSize: 22 }}>{currencyInfo(c).flag}</Text>
                  <Text style={[type.body, { color: colors.label, flex: 1 }]}>{currencyInfo(c).name}</Text>
                  <Text style={[type.bodyAmount, { color: colors.label }]}>{show(convert(value, from, c), c)}</Text>
                </Pressable>
              </View>
            ))}
          </View>
        ) : null}

        <Text style={[type.footnote, styles.footnote, { color: colors.secondary }]}>
          {rates
            ? `Mid-market rates from ${rates.source}, updated ${formatDistanceToNow(rates.at, { addSuffix: true })}. Banks and forex cards add a markup, so your statement may differ slightly.`
            : loading
              ? 'Loading rates…'
              : 'Rates need an internet connection the first time. Only currency codes are requested.'}
        </Text>
        <Pressable onPress={refresh} accessibilityRole="button" style={styles.refresh}>
          <Text style={[type.subhead, { color: colors.accent, fontWeight: '600' }]}>{loading ? 'Refreshing…' : 'Refresh Rates'}</Text>
        </Pressable>
      </ScrollView>
      <TopBar title="Converter" scrollY={scrollY} leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />} />
    </View>
  );
}

function CurrencyButton({ code, onPress }: { code: string; onPress: () => void }) {
  const { colors } = useTheme();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={`${currencyInfo(code).name}. Change`}
      style={[styles.currency, { backgroundColor: colors.fill }]}
    >
      <Text style={{ fontSize: 20 }}>{currencyInfo(code).flag}</Text>
      <Text style={[type.headline, { color: colors.label }]}>{code}</Text>
      <Icon name="chevron.up.chevron.down" size={12} color={colors.secondary} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: { marginHorizontal: 16, marginTop: 16, borderRadius: 22, padding: 16 },
  line: { flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 64 },
  input: { flex: 1, minWidth: 0, textAlign: 'right', padding: 0, fontSize: 34, lineHeight: 42, minHeight: 48 },
  swapRow: { justifyContent: 'center', marginVertical: 4 },
  swap: { position: 'absolute', alignSelf: 'center', width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center' },
  currency: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 12, height: 40, borderRadius: 20 },
  otherRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12 },
  footnote: { paddingHorizontal: 32, marginTop: 10 },
  refresh: { alignSelf: 'center', padding: 12 },
});
