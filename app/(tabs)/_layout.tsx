import { Redirect } from 'expo-router';
import * as QuickActions from 'expo-quick-actions';
import { useQuickActionRouting } from 'expo-quick-actions/router';
import { useEffect } from 'react';
import { Platform } from 'react-native';
import { NativeTabs } from 'expo-router/unstable-native-tabs';

import { usePrefs } from '@/stores/prefs';
import { useTheme } from '@/theme/useTheme';

// Real system tab bar: Liquid Glass on iOS 26+, classic on older iOS, Material 3 on Android.
export default function TabsLayout() {
  const onboarded = usePrefs((s) => s.onboarded);
  const { colors } = useTheme();
  useQuickActions();
  if (!onboarded) return <Redirect href="/onboarding" />;
  return (
    <NativeTabs minimizeBehavior="onScrollDown" tintColor={colors.accent}>
      <NativeTabs.Trigger name="index">
        <NativeTabs.Trigger.Label>Home</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf={{ default: 'house', selected: 'house.fill' }} md="home" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="activity">
        <NativeTabs.Trigger.Label>Activity</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="list.bullet" md="receipt_long" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="accounts">
        <NativeTabs.Trigger.Label>Accounts</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf={{ default: 'creditcard', selected: 'creditcard.fill' }} md="account_balance_wallet" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="settings">
        <NativeTabs.Trigger.Label>Settings</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf={{ default: 'gearshape', selected: 'gearshape.fill' }} md="settings" />
      </NativeTabs.Trigger>
      {/* Shown as its own glass button on the right of the bar on iOS 26. */}
      <NativeTabs.Trigger name="search" role="search">
        <NativeTabs.Trigger.Label>Search</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon sf="magnifyingglass" md="search" />
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}

/** Home Screen quick actions (long-press the app icon). No-op in Expo Go. */
function useQuickActions() {
  useQuickActionRouting();
  useEffect(() => {
    const icon = (symbol: string) => (Platform.OS === 'ios' ? `symbol:${symbol}` : undefined);
    QuickActions.setItems([
      { id: 'expense', title: 'Add Expense', icon: icon('minus.circle'), params: { href: '/add?type=expense' } },
      { id: 'income', title: 'Add Income', icon: icon('plus.circle'), params: { href: '/add?type=income' } },
      { id: 'transfer', title: 'Transfer', icon: icon('arrow.left.arrow.right'), params: { href: '/add?type=transfer' } },
      { id: 'search', title: 'Search', icon: Platform.OS === 'ios' ? 'search' : undefined, params: { href: '/search' } },
    ]).catch(() => {});
  }, []);
}
