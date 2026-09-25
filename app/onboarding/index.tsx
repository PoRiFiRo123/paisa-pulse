import * as Haptics from 'expo-haptics';
import * as LocalAuthentication from 'expo-local-authentication';
import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Switch, Text, TextInput, View } from 'react-native';
import Animated, { FadeInRight, FadeOutLeft } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { appDb } from '@/db/client';
import type { AccountType } from '@/db/schema';
import { createAccount } from '@/features/accounts/mutations';
import { accountIcon } from '@/features/accounts/presentation';
import { usePrefs } from '@/stores/prefs';
import { ACCENTS, type AccentKey } from '@/theme/tokens';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { Aurora } from '@/ui/Aurora';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { GlassSurface } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';

type Suggestion = { key: string; type: AccountType; name: string; on: boolean; color: string };

const SUGGESTIONS: Suggestion[] = [
  { key: 'bank', type: 'bank', name: 'Salary account', on: true, color: '#5E5CE6' },
  { key: 'card', type: 'card', name: 'Credit card', on: false, color: '#FF2D55' },
  { key: 'cash', type: 'cash', name: 'Cash', on: true, color: '#34C759' },
  { key: 'wallet', type: 'wallet', name: 'UPI wallet', on: false, color: '#FF9500' },
];

/** First launch, under a minute, no sign-up (SPEC §5.3). */
export default function OnboardingScreen() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const prefs = usePrefs();
  const [step, setStep] = useState(0);
  const [accounts, setAccounts] = useState(SUGGESTIONS);
  const [biometrics, setBiometrics] = useState(false);
  const [lock, setLock] = useState(false);

  useEffect(() => {
    Promise.all([LocalAuthentication.hasHardwareAsync(), LocalAuthentication.isEnrolledAsync()])
      .then(([h, e]) => setBiometrics(h && e))
      .catch(() => {});
  }, []);

  const finish = async () => {
    for (const a of accounts.filter((x) => x.on && x.name.trim())) {
      await createAccount(appDb, { name: a.name, type: a.type, color: a.color, icon: accountIcon(a.type) });
    }
    if (lock) prefs.set('appLock', true);
    prefs.set('onboarded', true);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
    router.replace('/');
  };

  const next = () => (step < 3 ? setStep(step + 1) : finish());
  const canContinue = step !== 1 || accounts.some((a) => a.on && a.name.trim());

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.background }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <Aurora height={900} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: insets.top + 40 }]} keyboardShouldPersistTaps="handled">
        <Animated.View key={step} entering={FadeInRight.springify().damping(20)} exiting={FadeOutLeft.duration(150)}>
          <GlassSurface radius={30} style={styles.card}>
            {step === 0 ? (
              <>
                <CategoryIcon icon="indianrupeesign.circle.fill" color={colors.accent} size={72} />
                <Text style={[type.largeTitle, { color: colors.label }]}>Paisa Pulse</Text>
                <Text style={[type.body, { color: colors.glassLabelSecondary }]}>
                  Fast to log, beautiful to look at. Your data never leaves your phone.
                </Text>
                {[
                  ['lock.fill', 'No sign-up, no servers'],
                  ['hand.raised.fill', 'No ads, no loan offers'],
                  ['iphone', 'Everything stays on this device'],
                ].map(([icon, text]) => (
                  <View key={text} style={styles.bullet}>
                    <Icon name={icon} size={18} color={colors.accent} />
                    <Text style={[type.body, { color: colors.label }]}>{text}</Text>
                  </View>
                ))}
              </>
            ) : null}

            {step === 1 ? (
              <>
                <Text style={[type.title2, { color: colors.label }]}>Add your accounts</Text>
                <Text style={[type.subhead, { color: colors.glassLabelSecondary }]}>
                  Rename them to match your bank and card. You can add more later.
                </Text>
                {accounts.map((a, i) => (
                  <View key={a.key} style={[styles.accountRow, { backgroundColor: colors.card }]}>
                    <CategoryIcon icon={accountIcon(a.type)} color={a.color} size={32} square />
                    <TextInput
                      value={a.name}
                      onChangeText={(name) => setAccounts(accounts.map((x, j) => (j === i ? { ...x, name, on: true } : x)))}
                      style={[type.body, { flex: 1, color: colors.label, paddingVertical: 10 }]}
                      accessibilityLabel={`${a.type} account name`}
                    />
                    <Switch
                      value={a.on}
                      onValueChange={(on) => setAccounts(accounts.map((x, j) => (j === i ? { ...x, on } : x)))}
                      trackColor={{ true: colors.income }}
                    />
                  </View>
                ))}
              </>
            ) : null}

            {step === 2 ? (
              <>
                <Text style={[type.title2, { color: colors.label }]}>Pick a colour</Text>
                <Text style={[type.subhead, { color: colors.glassLabelSecondary }]}>It tints buttons, highlights and the Home screen.</Text>
                <View style={styles.accents}>
                  {(Object.keys(ACCENTS) as AccentKey[]).map((k) => (
                    <Pressable
                      key={k}
                      accessibilityRole="radio"
                      accessibilityLabel={ACCENTS[k].name}
                      accessibilityState={{ checked: prefs.accent === k }}
                      onPress={() => {
                        Haptics.selectionAsync().catch(() => {});
                        prefs.set('accent', k);
                      }}
                      style={[styles.accent, { backgroundColor: ACCENTS[k].light }]}
                    >
                      {prefs.accent === k ? <Icon name="checkmark" size={20} color="#FFFFFF" weight="bold" /> : null}
                    </Pressable>
                  ))}
                </View>
              </>
            ) : null}

            {step === 3 ? (
              <>
                <CategoryIcon icon="lock.fill" color="#34C759" size={56} />
                <Text style={[type.title2, { color: colors.label }]}>Keep it private</Text>
                <Text style={[type.subhead, { color: colors.glassLabelSecondary }]}>
                  Lock Paisa Pulse with Face ID or your fingerprint. The screen also blurs in the app switcher.
                </Text>
                <View style={[styles.accountRow, { backgroundColor: colors.card }]}>
                  <Text style={[type.body, { color: colors.label, flex: 1, paddingVertical: 12 }]}>
                    {biometrics ? 'Use App Lock' : 'Biometrics not set up'}
                  </Text>
                  <Switch value={lock} disabled={!biometrics} onValueChange={setLock} trackColor={{ true: colors.income }} />
                </View>
              </>
            ) : null}
          </GlassSurface>
        </Animated.View>
      </ScrollView>

      <View style={[styles.footer, { paddingBottom: insets.bottom + 16 }]}>
        <View style={styles.dots}>
          {[0, 1, 2, 3].map((i) => (
            <View key={i} style={[styles.dot, { backgroundColor: i === step ? colors.accent : colors.separator }]} />
          ))}
        </View>
        <Pressable disabled={!canContinue} onPress={next} accessibilityRole="button" style={{ opacity: canContinue ? 1 : 0.5 }}>
          <GlassSurface radius={27} tint={colors.accent} interactive style={styles.cta}>
            <Text style={[type.headline, { color: '#FFFFFF' }]}>{step === 0 ? 'Get Started' : step === 3 ? 'Start Tracking' : 'Continue'}</Text>
          </GlassSurface>
        </Pressable>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingBottom: 160 },
  card: { padding: 24, gap: 14 },
  bullet: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  accountRow: { flexDirection: 'row', alignItems: 'center', gap: 12, borderRadius: 16, paddingHorizontal: 12 },
  accents: { flexDirection: 'row', flexWrap: 'wrap', gap: 14 },
  accent: { width: 52, height: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center' },
  footer: { position: 'absolute', left: 16, right: 16, bottom: 0, gap: 16 },
  dots: { flexDirection: 'row', gap: 8, alignSelf: 'center' },
  dot: { width: 8, height: 8, borderRadius: 4 },
  cta: { height: 54, alignItems: 'center', justifyContent: 'center' },
});
