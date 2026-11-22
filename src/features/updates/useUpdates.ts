import { useEffect } from 'react';
import { AppState, Linking, Platform } from 'react-native';
import { create } from 'zustand';

import { BUILD_NUMBER, HAS_CUSTOM_NATIVE, RELEASE_REPO } from '@/lib/native';
import { useToast } from '@/stores/toast';

import { type AvailableUpdate, fetchLatestRelease, pickUpdate, sideStoreInstallUrl } from './check';

/** At most one network check per this long (launch + foreground). */
const CHECK_EVERY_MS = 6 * 60 * 60_000;

type UpdatesState = { available: AvailableUpdate | null; checkedAt: number; announced: number };
export const useUpdates = create<UpdatesState>(() => ({ available: null, checkedAt: 0, announced: 0 }));

export async function checkForUpdate(force = false): Promise<AvailableUpdate | null> {
  if (!HAS_CUSTOM_NATIVE || !BUILD_NUMBER || (Platform.OS !== 'ios' && Platform.OS !== 'android')) return null;
  const { checkedAt } = useUpdates.getState();
  if (!force && Date.now() - checkedAt < CHECK_EVERY_MS) return useUpdates.getState().available;
  useUpdates.setState({ checkedAt: Date.now() });
  try {
    const release = await fetchLatestRelease(RELEASE_REPO);
    const available = release ? pickUpdate(release, BUILD_NUMBER, Platform.OS) : null;
    useUpdates.setState({ available });
    return available;
  } catch {
    return null; // offline: try again next time
  }
}

/** Android: download the APK in the browser. iPhone: SideStore, else the release page. */
export async function installUpdate(update: AvailableUpdate): Promise<void> {
  if (Platform.OS === 'ios' && update.fileUrl) {
    try {
      await Linking.openURL(sideStoreInstallUrl(update.fileUrl));
      return;
    } catch {
      // SideStore isn't installed.
    }
  }
  await Linking.openURL(Platform.OS === 'android' && update.fileUrl ? update.fileUrl : update.pageUrl);
}

/** Checks at launch and on foreground; announces each new build once with a toast. */
export function useUpdateCheck() {
  useEffect(() => {
    const run = async () => {
      const update = await checkForUpdate();
      if (!update || useUpdates.getState().announced >= update.build) return;
      useUpdates.setState({ announced: update.build });
      useToast.getState().show(
        { message: `Build ${update.build} is ready`, actionLabel: 'Update', onAction: () => installUpdate(update) },
        8000,
      );
    };
    void run();
    const sub = AppState.addEventListener('change', (s) => s === 'active' && void run());
    return () => sub.remove();
  }, []);
}
