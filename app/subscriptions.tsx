import { differenceInCalendarDays, format } from 'date-fns';
import * as Haptics from 'expo-haptics';
import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { describeFrequency } from '@/features/recurring/recurring';
import { type DetectedSubscription, detectSubscriptions, listSubscriptions, monthlyEquivalent, type Subscription, trackSubscription } from '@/features/recurring/subscriptions';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { useToast } from '@/stores/toast';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { EmptyState } from '@/ui/EmptyState';
import { GlassButton } from '@/ui/Glass';
import { GroupHeader, InsetGroup } from '@/ui/InsetGroup';
import { MerchantIcon } from '@/ui/MerchantIcon';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';

function renews(at: number, now: number): string {
  const days = differenceInCalendarDays(at, now);
  if (days <= 0) return 'renews today';
  if (days === 1) return 'renews tomorrow';
  if (days < 7) return `renews in ${days} days`;
  return `renews ${format(at, 'd MMM')}`;
}

/** Recurring expenses as subscriptions: cost per month and year, next renewal, total paid. */
export default function SubscriptionsScreen() {
  const { colors } = useTheme();
  const money = useMoney();
  const toast = useToast((s) => s.show);
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const [now] = useState(() => Date.now());
  const { data: subs, loaded } = useQuery(() => listSubscriptions(appDb), [], []);
  const { data: detected } = useQuery(() => detectSubscriptions(appDb), [], []);

  const active = subs.filter((s) => s.active);
  const inactive = subs.filter((s) => !s.active);
  const monthly = active.reduce((sum, s) => sum + s.monthly, 0);
  const edit = (id: string) => router.push({ pathname: '/recurring-form', params: { id } });

  const track = async (d: DetectedSubscription) => {
    await trackSubscription(appDb, d);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
    toast({ message: `Tracking ${d.payee}` });
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}>
        <LargeTitle title="Subscriptions" />

        {active.length ? (
          <View style={[styles.card, { backgroundColor: colors.card }]}>
            <Text style={[type.subhead, { color: colors.secondary }]}>
              {active.length} active · per month
            </Text>
            <Text style={[type.amount, { color: colors.label }]} numberOfLines={1} adjustsFontSizeToFit>
              {money.amount(monthly)}
            </Text>
            <Text style={[type.subhead, { color: colors.secondary }]}>{money.amount(monthly * 12)} a year</Text>
          </View>
        ) : null}

        {detected.length ? (
          <>
            <GroupHeader title="Looks like a subscription" />
            <InsetGroup dividerInset={66}>
              {detected.map((d) => (
                <View key={d.payee} style={[styles.row, { backgroundColor: colors.card }]}>
                  <MerchantIcon name={d.payee} size={40} />
                  <View style={{ flex: 1, gap: 2 }}>
                    <Text style={[type.body, { color: colors.label }]} numberOfLines={1}>
                      {d.payee}
                    </Text>
                    <Text style={[type.footnote, { color: colors.secondary }]} numberOfLines={1}>
                      {money.amount(d.amount)} {d.frequency} · {d.transactionIds.length} payments · last {format(d.lastAt, 'd MMM')}
                    </Text>
                  </View>
                  <Pressable
                    onPress={() => track(d)}
                    accessibilityRole="button"
                    accessibilityLabel={`Track ${d.payee}, about ${money.amount(monthlyEquivalent({ ...d, interval: 1 }))} a month`}
                    style={[styles.track, { backgroundColor: `${colors.accent}1F` }]}
                  >
                    <Text style={[type.subhead, { color: colors.accent, fontWeight: '600' }]}>Track</Text>
                  </Pressable>
                </View>
              ))}
            </InsetGroup>
            <Text style={[type.footnote, styles.footnote, { color: colors.secondary }]}>
              Found from payments with the same payee and amount on a regular schedule. Tracking adds future payments automatically.
            </Text>
          </>
        ) : null}

        {loaded && !subs.length && !detected.length ? (
          <EmptyState
            icon="repeat"
            title="No subscriptions yet"
            message="Add Netflix, Spotify, your gym or rent as a recurring expense, or open a past payment and choose Repeat."
            actionLabel="Add Recurring"
            onAction={() => router.push('/recurring-form')}
          />
        ) : null}

        {active.length ? (
          <>
            <GroupHeader title="Active" />
            <InsetGroup dividerInset={66}>
              {active.map((s) => (
                <SubscriptionRow key={s.rule.id} s={s} now={now} onPress={() => edit(s.rule.id)} />
              ))}
            </InsetGroup>
          </>
        ) : null}
        {inactive.length ? (
          <>
            <GroupHeader title="Paused or ended" />
            <InsetGroup dividerInset={66}>
              {inactive.map((s) => (
                <SubscriptionRow key={s.rule.id} s={s} now={now} onPress={() => edit(s.rule.id)} />
              ))}
            </InsetGroup>
          </>
        ) : null}
      </ScrollView>
      <TopBar
        title="Subscriptions"
        scrollY={scrollY}
        leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />}
        trailing={<GlassButton icon="plus" accessibilityLabel="Add subscription" onPress={() => router.push('/recurring-form')} />}
      />
    </View>
  );
}

function SubscriptionRow({ s, now, onPress }: { s: Subscription; now: number; onPress: () => void }) {
  const { colors } = useTheme();
  const money = useMoney();
  const name = s.rule.payee ?? s.category?.name ?? 'Subscription';
  const status = s.rule.pausedAt !== null ? 'Paused' : !s.active ? 'Ended' : renews(s.rule.nextAt, now);
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={`${name}, ${money.amount(s.rule.amount)} ${describeFrequency(s.rule).toLowerCase()}, ${status}, ${money.amount(s.yearly)} a year, paid ${money.amount(s.paid)} so far`}
      style={({ pressed }) => [styles.row, { backgroundColor: pressed ? colors.fill : colors.card, opacity: s.active ? 1 : 0.55 }]}
    >
      <MerchantIcon name={name} fallbackIcon={s.category?.icon} fallbackColor={s.category?.color} size={40} />
      <View style={{ flex: 1, gap: 2 }}>
        <Text style={[type.body, { color: colors.label }]} numberOfLines={1}>
          {name}
        </Text>
        <Text style={[type.footnote, { color: colors.secondary }]} numberOfLines={1}>
          {describeFrequency(s.rule)} · {s.account.name} · {status}
        </Text>
        {s.payments ? (
          <Text style={[type.footnote, { color: colors.secondary }]} numberOfLines={1}>
            Paid {money.amount(s.paid)} since {format(s.firstPaidAt!, 'MMM yyyy')} · {s.payments} {s.payments === 1 ? 'payment' : 'payments'}
          </Text>
        ) : null}
      </View>
      <View style={{ alignItems: 'flex-end', gap: 2 }}>
        <Text style={[type.bodyAmount, { color: colors.label }]}>{money.amount(s.rule.amount)}</Text>
        <Text style={[type.caption, { color: colors.secondary }]}>{money.amount(s.yearly)}/yr</Text>
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: { marginHorizontal: 16, marginTop: 14, borderRadius: 22, padding: 18, gap: 2 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 11, minHeight: 64 },
  track: { paddingHorizontal: 14, height: 32, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  footnote: { paddingHorizontal: 32, paddingTop: 8 },
});
