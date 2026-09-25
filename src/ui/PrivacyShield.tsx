import { BlurView } from 'expo-blur';
import * as LocalAuthentication from 'expo-local-authentication';
import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState, Pressable, StyleSheet, Text, View } from 'react-native';

import { usePrefs } from '@/stores/prefs';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';

import { CategoryIcon } from './CategoryIcon';
import { GlassSurface } from './Glass';

/**
 * Blurs the app in the app switcher, and when App Lock is on, requires Face ID /
 * fingerprint / passcode whenever the app returns from the background.
 */
export function PrivacyShield() {
  const { colors, dark } = useTheme();
  const appLock = usePrefs((s) => s.appLock);
  const [state, setState] = useState(AppState.currentState);
  const [locked, setLocked] = useState(appLock);
  const lockedRef = useRef(appLock);

  const unlock = useCallback(() => {
    LocalAuthentication.authenticateAsync({ promptMessage: 'Unlock Paisa Pulse' })
      .then((result) => {
        if (!result.success) return;
        lockedRef.current = false;
        setLocked(false);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    const sub = AppState.addEventListener('change', (next) => {
      setState(next);
      if (!usePrefs.getState().appLock) return;
      if (next === 'background') {
        lockedRef.current = true;
        setLocked(true);
      }
      // Prompt as soon as we come back.
      if (next === 'active' && lockedRef.current) unlock();
    });
    // Cold start with App Lock on.
    if (lockedRef.current && AppState.currentState === 'active') unlock();
    return () => sub.remove();
  }, [unlock]);

  if (appLock && locked) {
    return (
      <View style={[StyleSheet.absoluteFill, styles.center, { backgroundColor: colors.background }]}>
        <CategoryIcon icon="lock.fill" color={colors.accent} size={64} />
        <Text style={[type.title3, { color: colors.label }]}>Paisa Pulse is locked</Text>
        <Pressable onPress={unlock} accessibilityRole="button">
          <GlassSurface radius={24} tint={colors.accent} interactive style={styles.button}>
            <Text style={[type.headline, { color: '#FFFFFF' }]}>Unlock</Text>
          </GlassSurface>
        </Pressable>
      </View>
    );
  }
  if (state !== 'active') {
    return <BlurView style={StyleSheet.absoluteFill} intensity={60} tint={dark ? 'dark' : 'light'} />;
  }
  return null;
}

const styles = StyleSheet.create({
  center: { alignItems: 'center', justifyContent: 'center', gap: 16 },
  button: { height: 48, paddingHorizontal: 32, alignItems: 'center', justifyContent: 'center' },
});
