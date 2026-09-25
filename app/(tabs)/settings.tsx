import Constants from 'expo-constants';
import * as LocalAuthentication from 'expo-local-authentication';
import { router, useScrollToTop } from 'expo-router';
import { useRef } from 'react';
import { Alert, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';

import { pickAndRestoreBackup, shareCsvExport, shareJsonBackup } from '@/features/backup/share';
import { usePrefs } from '@/stores/prefs';
import { useToast } from '@/stores/toast';
import { ACCENTS, type AccentKey } from '@/theme/tokens';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { Menu } from '@/ui/Menu';
import { LargeTitle, TopBar, useBottomSpace, useScrollHeader, useTitleTop } from '@/ui/Screen';

const THEMES = { system: 'System', light: 'Light', dark: 'Dark', amoled: 'AMOLED Black' } as const;

function ordinal(n: number): string {
  const s = ['th', 'st', 'nd', 'rd'];
  const v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

export default function SettingsScreen() {
  const scrollRef = useRef<ScrollView>(null);
  useScrollToTop(scrollRef);
  const { colors } = useTheme();
  const prefs = usePrefs();
  const toast = useToast((s) => s.show);
  const { scrollY, onScroll } = useScrollHeader();
  const titleTop = useTitleTop();
  const bottom = useBottomSpace();
  const icon = (name: string, color: string) => <CategoryIcon icon={name} color={color} size={30} square />;

  const toggleLock = async (on: boolean) => {
    if (!on) return prefs.set('appLock', false);
    const [hardware, enrolled] = await Promise.all([LocalAuthentication.hasHardwareAsync(), LocalAuthentication.isEnrolledAsync()]);
    if (!hardware || !enrolled) {
      Alert.alert('Set up Face ID or fingerprint first', 'App lock uses your phone’s biometrics or passcode.');
      return;
    }
    const result = await LocalAuthentication.authenticateAsync({ promptMessage: 'Turn on App Lock' });
    if (result.success) prefs.set('appLock', true);
  };

  const run = (task: () => Promise<unknown>, failure: string) => task().catch((e: Error) => Alert.alert(failure, e.message));

  const restore = () =>
    Alert.alert('Restore from backup?', 'This replaces everything in Paisa Pulse with the backup’s data.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Choose File',
        style: 'destructive',
        onPress: () =>
          run(async () => {
            if (await pickAndRestoreBackup()) {
              await usePrefs.getState().hydrate();
              toast({ message: 'Backup restored' });
            }
          }, 'Couldn’t restore'),
      },
    ]);

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView
        ref={scrollRef}
        onScroll={onScroll}
        scrollEventThrottle={16}
        contentInsetAdjustmentBehavior="never"
        contentContainerStyle={{ paddingTop: titleTop, paddingBottom: bottom }}
      >
        <LargeTitle title="Settings" />

        <GroupHeader title="Appearance" />
        <InsetGroup>
          <Menu
            items={(Object.keys(THEMES) as (keyof typeof THEMES)[]).map((t) => ({
              title: THEMES[t],
              checked: prefs.theme === t,
              onPress: () => prefs.set('theme', t),
            }))}
          >
            {(open) => <GroupRow title="Theme" value={THEMES[prefs.theme]} leading={icon('moon.fill', '#5856D6')} chevron onPress={open} />}
          </Menu>
          <Menu
            items={(Object.keys(ACCENTS) as AccentKey[]).map((a) => ({
              title: ACCENTS[a].name,
              checked: prefs.accent === a,
              onPress: () => prefs.set('accent', a),
            }))}
          >
            {(open) => (
              <GroupRow
                title="Accent colour"
                value={ACCENTS[prefs.accent].name}
                leading={icon('paintpalette.fill', colors.accent)}
                chevron
                onPress={open}
              />
            )}
          </Menu>
          <GroupRow title="Currency" value="₹ · Lakh, Crore" leading={icon('indianrupeesign', '#34C759')} />
        </InsetGroup>

        <GroupHeader title="Money" />
        <InsetGroup>
          <GroupRow title="Categories" leading={icon('tag.fill', '#FF9500')} chevron onPress={() => router.push('/categories')} />
          <Menu
            items={Array.from({ length: 28 }, (_, i) => ({
              title: i === 0 ? '1st (calendar month)' : `${ordinal(i + 1)} (e.g. salary day)`,
              checked: prefs.monthStartDay === i + 1,
              onPress: () => prefs.set('monthStartDay', i + 1),
            }))}
          >
            {(open) => (
              <GroupRow title="Month starts on" value={ordinal(prefs.monthStartDay)} leading={icon('calendar', '#FF3B30')} chevron onPress={open} />
            )}
          </Menu>
          <Menu
            items={[
              { title: 'Monday', checked: prefs.weekStartDay === 1, onPress: () => prefs.set('weekStartDay', 1) },
              { title: 'Sunday', checked: prefs.weekStartDay === 0, onPress: () => prefs.set('weekStartDay', 0) },
            ]}
          >
            {(open) => (
              <GroupRow
                title="Week starts on"
                value={prefs.weekStartDay === 1 ? 'Monday' : 'Sunday'}
                leading={icon('calendar.badge.clock', '#32ADE6')}
                chevron
                onPress={open}
              />
            )}
          </Menu>
          <GroupRow title="Accounts" leading={icon('creditcard.fill', '#007AFF')} chevron onPress={() => router.navigate('/accounts')} />
        </InsetGroup>

        <GroupHeader title="Privacy" />
        <InsetGroup>
          <GroupRow
            title="App Lock"
            leading={icon('lock.fill', '#34C759')}
            trailing={<Switch value={prefs.appLock} onValueChange={toggleLock} trackColor={{ true: colors.income }} />}
          />
          <GroupRow
            title="Hide amounts"
            leading={icon('eye.slash.fill', '#8E8E93')}
            trailing={<Switch value={prefs.hideAmounts} onValueChange={(v) => prefs.set('hideAmounts', v)} trackColor={{ true: colors.income }} />}
          />
        </InsetGroup>

        <GroupHeader title="Data" />
        <InsetGroup>
          <GroupRow title="Export CSV" leading={icon('square.and.arrow.up', '#007AFF')} chevron onPress={() => run(shareCsvExport, 'Couldn’t export')} />
          <Menu
            items={[
              { title: 'Export Backup', icon: 'square.and.arrow.up', onPress: () => run(shareJsonBackup, 'Couldn’t back up') },
              { title: 'Restore from Backup…', icon: 'square.and.arrow.down', onPress: restore },
            ]}
          >
            {(open) => <GroupRow title="Backup & Restore" leading={icon('square.and.arrow.down', '#5E5CE6')} chevron onPress={open} />}
          </Menu>
        </InsetGroup>

        <View style={styles.footer}>
          <Text style={[type.footnote, { color: colors.secondary }]}>Paisa Pulse {Constants.expoConfig?.version ?? ''}</Text>
          <Text style={[type.footnote, { color: colors.secondary, textAlign: 'center' }]}>
            No account. No servers. Your data stays on this phone.
          </Text>
        </View>
      </ScrollView>
      <TopBar title="Settings" scrollY={scrollY} />
    </View>
  );
}

const styles = StyleSheet.create({
  footer: { alignItems: 'center', gap: 2, marginTop: 24, paddingHorizontal: 32 },
});
