import '@/lib/polyfills';

import { isLiquidGlassAvailable } from 'expo-glass-effect';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { View } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

import { DatabaseProvider } from '@/db/DatabaseProvider';
import { useA11yWatcher } from '@/stores/a11y';
import { useTheme } from '@/theme/useTheme';
import { PrivacyShield } from '@/ui/PrivacyShield';
import { ShakeToUndo } from '@/ui/ShakeToUndo';
import { ToastHost } from '@/ui/ToastHost';

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <DatabaseProvider>
        <AppShell />
      </DatabaseProvider>
    </GestureHandlerRootView>
  );
}

function AppShell() {
  useA11yWatcher();
  const { dark, colors } = useTheme();
  const base = dark ? DarkTheme : DefaultTheme;
  const navTheme = {
    ...base,
    colors: { ...base.colors, background: colors.background, card: colors.card, text: colors.label, primary: colors.accent, border: colors.separator },
  };
  // On iOS 26 the system sheet is Liquid Glass; keep our sheet content transparent over it.
  const sheetBackground = isLiquidGlassAvailable() ? 'transparent' : colors.background;
  const sheet = (detents: number[]) =>
    ({
      presentation: 'formSheet',
      sheetAllowedDetents: detents,
      sheetGrabberVisible: true,
      sheetCornerRadius: 32,
      headerShown: false,
      contentStyle: { backgroundColor: sheetBackground },
    }) as const;

  return (
    <ThemeProvider value={navTheme}>
      <View style={{ flex: 1, backgroundColor: colors.background }}>
        <StatusBar style={dark ? 'light' : 'auto'} />
        <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }}>
          <Stack.Screen name="(tabs)" />
          <Stack.Screen name="transaction/[id]" />
          <Stack.Screen name="account/[id]" />
          <Stack.Screen name="categories" />
          <Stack.Screen name="add" options={sheet([0.92])} />
          <Stack.Screen name="account-form" options={sheet([0.92])} />
          <Stack.Screen name="category-form" options={sheet([0.92])} />
          <Stack.Screen name="pick-category" options={sheet([0.6, 0.92])} />
          <Stack.Screen name="onboarding/index" options={{ gestureEnabled: false, animation: 'fade' }} />
        </Stack>
        <ToastHost />
        <ShakeToUndo />
        <PrivacyShield />
      </View>
    </ThemeProvider>
  );
}
