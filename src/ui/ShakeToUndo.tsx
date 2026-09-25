import * as Haptics from 'expo-haptics';
import { Accelerometer } from 'expo-sensors';
import { useEffect } from 'react';
import { Alert, AppState, Platform } from 'react-native';

import { UNDO_WINDOW_MS, useToast } from '@/stores/toast';

/** Acceleration (in g) that counts as a deliberate shake; ~1 g is gravity at rest. */
const SHAKE_THRESHOLD = 2.2;
const SAMPLE_MS = 100;

/**
 * Shake to undo, like iOS: shaking after a delete or edit offers "Undo …?".
 * The accelerometer only runs while an undo is available and the app is active.
 */
export function ShakeToUndo() {
  const lastUndo = useToast((s) => s.lastUndo);

  useEffect(() => {
    if (!lastUndo || Platform.OS === 'web') return;
    let cancelled = false;
    let asking = false;
    let sub: ReturnType<typeof Accelerometer.addListener> | null = null;
    const start = async () => {
      if (sub || !(await Accelerometer.isAvailableAsync().catch(() => false)) || cancelled || sub) return;
      Accelerometer.setUpdateInterval(SAMPLE_MS);
      sub = Accelerometer.addListener(({ x, y, z }) => {
        if (asking || Math.sqrt(x * x + y * y + z * z) < SHAKE_THRESHOLD) return;
        const entry = useToast.getState().lastUndo;
        if (!entry || Date.now() - entry.at > UNDO_WINDOW_MS) return;
        asking = true;
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => {});
        Alert.alert(`Undo ${entry.label.replace(/^./, (c) => c.toLowerCase())}?`, undefined, [
          { text: 'Cancel', style: 'cancel', onPress: () => (asking = false) },
          {
            text: 'Undo',
            onPress: () => {
              asking = false;
              useToast.getState().undo();
            },
          },
        ]);
      });
    };
    const stop = () => {
      sub?.remove();
      sub = null;
    };
    start();
    const app = AppState.addEventListener('change', (s) => (s === 'active' ? start() : stop()));
    // Stop listening once the undo window closes.
    const expire = setTimeout(stop, Math.max(0, lastUndo.at + UNDO_WINDOW_MS - Date.now()));
    return () => {
      cancelled = true;
      stop();
      app.remove();
      clearTimeout(expire);
    };
  }, [lastUndo]);

  return null;
}
