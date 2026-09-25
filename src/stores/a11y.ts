import { useEffect } from 'react';
import { AccessibilityInfo, Platform } from 'react-native';
import { create } from 'zustand';

type A11yState = { reduceTransparency: boolean; increaseContrast: boolean };

/** System accessibility settings the design adapts to. */
export const useA11y = create<A11yState>(() => ({ reduceTransparency: false, increaseContrast: false }));

/** Mount once at the root: keeps `useA11y` in sync with the system settings. */
export function useA11yWatcher() {
  useEffect(() => {
    const set = (patch: Partial<A11yState>) => useA11y.setState(patch);
    const subs: { remove: () => void }[] = [];
    if (Platform.OS === 'ios') {
      AccessibilityInfo.isReduceTransparencyEnabled().then((v) => set({ reduceTransparency: v })).catch(() => {});
      AccessibilityInfo.isDarkerSystemColorsEnabled().then((v) => set({ increaseContrast: v })).catch(() => {});
      subs.push(
        AccessibilityInfo.addEventListener('reduceTransparencyChanged', (v) => set({ reduceTransparency: v })),
        AccessibilityInfo.addEventListener('darkerSystemColorsChanged', (v) => set({ increaseContrast: v })),
      );
    } else if (Platform.OS === 'android') {
      AccessibilityInfo.isHighTextContrastEnabled().then((v) => set({ increaseContrast: v })).catch(() => {});
      subs.push(AccessibilityInfo.addEventListener('highTextContrastChanged', (v) => set({ increaseContrast: v })));
    }
    return () => subs.forEach((s) => s.remove());
  }, []);
}
