import * as Haptics from 'expo-haptics';
import * as ImagePicker from 'expo-image-picker';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withRepeat, withTiming } from 'react-native-reanimated';

import { appDb } from '@/db/client';
import { accountsWithBalance } from '@/features/accounts/queries';
import { commitDrafts, learnedCategories, looksLogged, undoCommit } from '@/features/capture/commit';
import { DraftList } from '@/features/capture/DraftList';
import type { CaptureContext, CaptureDraft } from '@/features/capture/drafts';
import { canListen, canReadImages, readImageText, speechModule } from '@/features/capture/native';
import { parsePaymentScreenshot } from '@/features/capture/screenshot';
import { parseSpokenTransactions } from '@/features/capture/voice';
import { categoriesByKind } from '@/features/categories/queries';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { usePrefs } from '@/stores/prefs';
import { useToast } from '@/stores/toast';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { GlassSurface } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { SheetHeader, useSheetBackground } from '@/ui/SheetHeader';

const EXAMPLES = ['“250 lunch, 80 auto and 40 chai”', '“Paid 420 on Swiggy with my card yesterday”', '“Got salary 90k in Axis”', '“Moved 5000 from Axis to Baroda”'];

/** Voice and screenshot capture: everything is read on the phone, reviewed, then added in one go with Undo. */
export default function CaptureScreen() {
  const { mode = 'voice' } = useLocalSearchParams<{ mode?: 'voice' | 'screenshot' }>();
  const { colors } = useTheme();
  const background = useSheetBackground();
  const money = useMoney();
  const toast = useToast((s) => s.show);
  const lastAccountId = usePrefs((s) => s.lastAccountId);

  const { data: accounts } = useQuery(() => accountsWithBalance(appDb), [], []);
  const { data: expense } = useQuery(() => categoriesByKind(appDb, 'expense'), [], []);
  const { data: income } = useQuery(() => categoriesByKind(appDb, 'income'), [], []);
  const { data: learned } = useQuery(() => learnedCategories(appDb), [], new Map<string, string>());
  const categories = useMemo(() => [...expense, ...income], [expense, income]);
  const ctx = useMemo(
    () => ({ accounts, categories, learned, defaultAccountId: accounts.find((a) => a.id === lastAccountId)?.id ?? accounts[0]?.id ?? null }),
    [accounts, categories, learned, lastAccountId],
  );
  // Read by the parsers at the moment they run, with a fresh `now`.
  const ctxRef = useRef<Omit<CaptureContext, 'now'> | null>(null);
  useEffect(() => {
    ctxRef.current = ctx;
  }, [ctx]);

  const [drafts, setDrafts] = useState<CaptureDraft[]>([]);
  const [skipped, setSkipped] = useState<string[]>([]);
  const update = (key: string, patch: Partial<CaptureDraft>) => setDrafts((ds) => ds.map((d) => (d.key === key ? { ...d, ...patch } : d)));
  const chosen = drafts.filter((d) => d.include && d.accountId);
  const total = chosen.filter((d) => d.type === 'expense').reduce((s, d) => s + d.amount, 0);

  const save = async () => {
    if (!chosen.length) return;
    const ids = await commitDrafts(appDb, drafts, mode === 'voice' ? 'voice' : 'screenshot');
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
    toast({ message: ids.length === 1 ? 'Added 1 transaction' : `Added ${ids.length} transactions`, actionLabel: 'Undo', onAction: () => undoCommit(appDb, ids) });
    router.back();
  };

  return (
    <View style={{ flex: 1, backgroundColor: background }}>
      <SheetHeader title={mode === 'voice' ? 'Say It' : 'From Screenshots'} onSave={save} canSave={chosen.length > 0} />
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingBottom: 40 }}>
        {mode === 'voice' ? (
          <VoiceInput
            onText={(text) => {
              const ctx = ctxRef.current!;
              const parsed = parseSpokenTransactions(text, { ...ctx, now: Date.now() });
              // Keep the user's ticks and edits for drafts that are still there.
              setDrafts((old) => parsed.drafts.map((d) => {
                const prev = old.find((o) => o.key === d.key && o.source === d.source);
                return prev ?? d;
              }));
              setSkipped(parsed.skipped);
            }}
          />
        ) : (
          <ScreenshotInput onDrafts={(found) => setDrafts((old) => [...old, ...found])} contextRef={ctxRef} />
        )}

        {drafts.length ? (
          <>
            <Text style={[type.footnote, styles.section, { color: colors.secondary }]}>
              {chosen.length} TO ADD{total ? ` · ${money.amount(total)} SPENT` : ''}
            </Text>
            <DraftList drafts={drafts} accounts={accounts} categories={categories} onChange={update} />
            <Text style={[type.footnote, styles.hint, { color: colors.secondary }]}>Tap a row to fix its amount, category, account or type.</Text>
          </>
        ) : null}
        {skipped.length ? (
          <Text style={[type.footnote, styles.hint, { color: '#FF9500' }]}>No amount heard in: {skipped.map((s) => `“${s}”`).join(', ')}</Text>
        ) : null}
      </ScrollView>
    </View>
  );
}

function VoiceInput({ onText }: { onText: (text: string) => void }) {
  const { colors } = useTheme();
  const [available] = useState(canListen);
  const [listening, setListening] = useState(false);
  const [text, setText] = useState('');
  const [error, setError] = useState<string | null>(null);
  const base = useRef('');
  const pulse = useSharedValue(1);
  const pulseStyle = useAnimatedStyle(() => ({ transform: [{ scale: pulse.value }] }));

  const changeText = useCallback(
    (t: string) => {
      setText(t);
      onText(t);
    },
    [onText],
  );

  useEffect(() => {
    const m = speechModule();
    if (!m || !available) return;
    const mod = m.ExpoSpeechRecognitionModule;
    const subs = [
      mod.addListener('result', (e) => {
        const heard = e.results[0]?.transcript ?? '';
        changeText(`${base.current}${base.current && heard ? ', ' : ''}${heard}`);
      }),
      mod.addListener('end', () => setListening(false)),
      mod.addListener('error', (e) => {
        setListening(false);
        if (e.error !== 'aborted' && e.error !== 'no-speech') setError(e.message || 'Couldn’t hear that. Try again.');
      }),
    ];
    return () => {
      subs.forEach((s) => s.remove());
      mod.abort();
    };
  }, [available, changeText]);

  useEffect(() => {
    pulse.set(listening ? withRepeat(withTiming(1.12, { duration: 650 }), -1, true) : withTiming(1));
  }, [listening, pulse]);

  const toggle = async () => {
    const m = speechModule();
    if (!m) return;
    const mod = m.ExpoSpeechRecognitionModule;
    if (listening) {
      mod.stop();
      return;
    }
    setError(null);
    const perm = await mod.requestPermissionsAsync();
    if (!perm.granted) {
      setError('Allow microphone and speech recognition in Settings to use voice.');
      return;
    }
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => {});
    base.current = text.trim();
    const onDevice = mod.supportsOnDeviceRecognition();
    mod.start({
      lang: 'en-IN',
      interimResults: true,
      continuous: true,
      addsPunctuation: true,
      // Stay on the phone when the device supports it.
      requiresOnDeviceRecognition: onDevice,
      contextualStrings: ['rupees', 'lakh', 'Swiggy', 'Zomato', 'Blinkit', 'Zepto', 'auto', 'chai', 'UPI', 'Axis', 'Baroda'],
      iosTaskHint: 'dictation',
    });
    setListening(true);
  };

  return (
    <View style={styles.voice}>
      {available ? (
        <Pressable onPress={toggle} accessibilityRole="button" accessibilityLabel={listening ? 'Stop listening' : 'Start listening'} style={styles.micWrap}>
          <Animated.View style={pulseStyle}>
            <GlassSurface radius={44} tint={listening ? colors.expense : colors.accent} interactive style={styles.mic}>
              <Icon name={listening ? 'stop.fill' : 'mic.fill'} size={34} color="#FFFFFF" weight="semibold" />
            </GlassSurface>
          </Animated.View>
          <Text style={[type.subhead, { color: colors.secondary, marginTop: 10 }]}>{listening ? 'Listening… tap to stop' : 'Tap and say what you spent'}</Text>
        </Pressable>
      ) : (
        <Text style={[type.footnote, styles.note, { color: colors.secondary }]}>
          Type it below, or use the microphone on your keyboard. Live voice needs the Paisa Pulse app build (it isn’t available in Expo Go).
        </Text>
      )}
      <TextInput
        value={text}
        onChangeText={changeText}
        multiline
        autoFocus={!available}
        placeholder="250 lunch, 80 auto and 40 chai"
        placeholderTextColor={colors.secondary}
        style={[type.body, styles.transcript, { color: colors.label, backgroundColor: colors.card }]}
        accessibilityLabel="What you spent"
      />
      {error ? <Text style={[type.footnote, styles.note, { color: colors.expense }]}>{error}</Text> : null}
      {!text ? (
        <View style={styles.examples}>
          {EXAMPLES.map((e) => (
            <Text key={e} style={[type.footnote, { color: colors.secondary }]}>
              {e}
            </Text>
          ))}
          <Text style={[type.caption, { color: colors.secondary, marginTop: 6 }]}>Understood on your phone. Nothing is sent anywhere.</Text>
        </View>
      ) : null}
    </View>
  );
}

function ScreenshotInput({ onDrafts, contextRef }: { onDrafts: (d: CaptureDraft[]) => void; contextRef: React.RefObject<Omit<CaptureContext, 'now'> | null> }) {
  const { colors } = useTheme();
  const [available] = useState(canReadImages);
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const started = useRef(false);
  const counter = useRef(0);

  const pick = useCallback(async () => {
    setMessage(null);
    const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsMultipleSelection: true, selectionLimit: 10, quality: 1 });
    if (result.canceled || !result.assets.length) return;
    const found: CaptureDraft[] = [];
    let unreadable = 0;
    for (const [i, asset] of result.assets.entries()) {
      setBusy(`Reading ${i + 1} of ${result.assets.length}…`);
      try {
        const lines = await readImageText(asset.uri);
        const ctx = contextRef.current!;
        const draft = parsePaymentScreenshot(lines, { ...ctx, now: Date.now() }, `shot-${counter.current++}`);
        if (!draft) {
          unreadable++;
          continue;
        }
        if (await looksLogged(appDb, draft.amount, draft.occurredAt)) {
          draft.include = false;
          draft.warning = 'Looks like one you already added.';
        }
        found.push(draft);
      } catch (e) {
        unreadable++;
        setMessage(e instanceof Error ? e.message : String(e));
      }
    }
    setBusy(null);
    if (unreadable) setMessage(`${unreadable} ${unreadable === 1 ? 'image' : 'images'} didn’t look like a payment receipt.`);
    onDrafts(found);
  }, [contextRef, onDrafts]);

  useEffect(() => {
    if (started.current || !available) return;
    started.current = true;
    const t = setTimeout(pick, 350);
    return () => clearTimeout(t);
  }, [available, pick]);

  return (
    <View style={styles.voice}>
      <View style={[styles.shotIcon, { backgroundColor: `${colors.accent}1F` }]}>
        <Icon name="photo.on.rectangle" size={34} color={colors.accent} />
      </View>
      <Text style={[type.subhead, styles.note, { color: colors.secondary }]}>
        {available
          ? 'Pick payment screenshots from GPay, PhonePe, Paytm, CRED or your bank app. Text is read on your phone; the images never leave it.'
          : 'Reading screenshots needs the Paisa Pulse app build (it isn’t available in Expo Go).'}
      </Text>
      {busy ? (
        <View style={styles.busy}>
          <ActivityIndicator color={colors.accent} />
          <Text style={[type.subhead, { color: colors.secondary }]}>{busy}</Text>
        </View>
      ) : available ? (
        <Pressable onPress={pick} accessibilityRole="button" style={[styles.pick, { backgroundColor: colors.accent }]}>
          <Text style={[type.headline, { color: '#FFFFFF' }]}>Choose Screenshots</Text>
        </Pressable>
      ) : null}
      {message ? <Text style={[type.footnote, styles.note, { color: '#FF9500' }]}>{message}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  voice: { alignItems: 'center', paddingHorizontal: 16, gap: 12 },
  micWrap: { alignItems: 'center', marginTop: 8 },
  mic: { width: 88, height: 88, alignItems: 'center', justifyContent: 'center' },
  transcript: { alignSelf: 'stretch', minHeight: 84, borderRadius: 16, padding: 14, textAlignVertical: 'top' },
  examples: { alignSelf: 'stretch', paddingHorizontal: 8, gap: 4 },
  note: { textAlign: 'center', paddingHorizontal: 16 },
  section: { paddingHorizontal: 32, marginTop: 22, marginBottom: 6 },
  hint: { paddingHorizontal: 32, marginTop: 8 },
  shotIcon: { width: 76, height: 76, borderRadius: 38, alignItems: 'center', justifyContent: 'center', marginTop: 8 },
  busy: { flexDirection: 'row', alignItems: 'center', gap: 10, padding: 12 },
  pick: { height: 50, borderRadius: 25, paddingHorizontal: 28, alignItems: 'center', justifyContent: 'center' },
});
