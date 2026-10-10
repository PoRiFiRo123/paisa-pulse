import { router } from 'expo-router';
import { Linking, ScrollView, StyleSheet, Text, View } from 'react-native';

import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { GlassButton } from '@/ui/Glass';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';

const PHRASES = [
  { say: '“Log an expense in Paisa Pulse”', then: 'Siri asks how much and what for, then logs it. No need to open the app.' },
  { say: '“Log income in Paisa Pulse”', then: 'For money you received.' },
  { say: '“How much have I spent in Paisa Pulse?”', then: 'Hear this month’s total and today’s spending.' },
];

const WALLET_STEPS = [
  'Open the Shortcuts app and go to Automation.',
  'Tap +, choose Wallet, pick your cards, and choose Run Immediately.',
  'Add the action Paisa Pulse › Log Card Payment.',
  'Set Amount to Shortcut Input › Amount, Merchant to Merchant, and Card to Card or Pass.',
  'Done. Each tap-to-pay is added the next time you open Paisa Pulse, matched to the card with the same name.',
];

/** How to use Siri phrases, Shortcuts actions and Wallet automations with Paisa Pulse (iOS). */
export default function SiriScreen() {
  const { colors } = useTheme();
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}>
        <LargeTitle title="Siri & Shortcuts" />

        <GroupHeader title="Just say" />
        <InsetGroup dividerInset={16}>
          {PHRASES.map((p) => (
            <View key={p.say} style={[styles.phrase, { backgroundColor: colors.card }]}>
              <Text style={[type.headline, { color: colors.label }]}>{p.say}</Text>
              <Text style={[type.subhead, { color: colors.secondary }]}>{p.then}</Text>
            </View>
          ))}
        </InsetGroup>
        <Text style={[type.footnote, styles.footnote, { color: colors.secondary }]}>
          These work right after installing. Entries from Siri are added when you next open the app, with an Undo.
        </Text>

        <GroupHeader title="Log Apple Pay payments automatically" />
        <InsetGroup dividerInset={16}>
          {WALLET_STEPS.map((step, i) => (
            <View key={step} style={[styles.step, { backgroundColor: colors.card }]}>
              <View style={[styles.number, { backgroundColor: `${colors.accent}1F` }]}>
                <Text style={[type.subhead, { color: colors.accent, fontWeight: '700' }]}>{i + 1}</Text>
              </View>
              <Text style={[type.subhead, { color: colors.label, flex: 1 }]}>{step}</Text>
            </View>
          ))}
        </InsetGroup>

        <InsetGroup style={{ marginTop: 22 }}>
          <GroupRow
            title="Open Shortcuts"
            tinted
            leading={<CategoryIcon icon="square.grid.2x2" color="#FF2D55" size={30} square />}
            chevron
            onPress={() => Linking.openURL('shortcuts://').catch(() => {})}
          />
        </InsetGroup>
        <Text style={[type.footnote, styles.footnote, { color: colors.secondary }]}>
          Shortcuts also lists “Say Expenses”, which opens voice entry, and every action above for your own automations, such as
          logging rent on the 1st.
        </Text>
      </ScrollView>
      <TopBar title="Siri & Shortcuts" scrollY={scrollY} leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />} />
    </View>
  );
}

const styles = StyleSheet.create({
  phrase: { paddingHorizontal: 16, paddingVertical: 12, gap: 3 },
  step: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 12 },
  number: { width: 28, height: 28, borderRadius: 14, alignItems: 'center', justifyContent: 'center' },
  footnote: { paddingHorizontal: 32, paddingTop: 8 },
});
