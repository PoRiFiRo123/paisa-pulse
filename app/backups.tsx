import { format, formatDistanceToNow } from 'date-fns';
import * as Haptics from 'expo-haptics';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';

import { appDb } from '@/db/client';
import { databaseWasReset } from '@/db/encryption';
import { setSetting } from '@/db/settings';
import { type AutoBackupSettings, backUpNow, type BackupFile, type BackupFrequency, type BackupStore, getAutoBackup, listBackups } from '@/features/backup/auto';
import { parseBackup, restoreBackup } from '@/features/backup/backup';
import { pickAndRestoreBackup, shareJsonBackup } from '@/features/backup/share';
import { allStores, preferredStore } from '@/features/backup/stores';
import { usePrefs } from '@/stores/prefs';
import { useToast } from '@/stores/toast';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { GlassButton } from '@/ui/Glass';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { Menu } from '@/ui/Menu';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';

const FREQUENCY: Record<BackupFrequency, string> = { off: 'Off', daily: 'Daily', weekly: 'Weekly' };

type Listing = { store: BackupStore; available: boolean; files: BackupFile[] };

async function fetchBackupState() {
  const [settings, target] = await Promise.all([getAutoBackup(appDb), preferredStore()]);
  const listings: Listing[] = await Promise.all(
    allStores().map(async (store) => {
      const available = await store.available().catch(() => false);
      return { store, available, files: available ? await listBackups(store).catch(() => []) : [] };
    }),
  );
  return { settings, target, listings };
}

/** Automatic backups (iCloud Drive or this phone), Back Up Now, and restore from any backup. */
export default function BackupsScreen() {
  const { restore: restoreMode } = useLocalSearchParams<{ restore?: string }>();
  const { colors } = useTheme();
  const toast = useToast((s) => s.show);
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const [settings, setSettings] = useState<AutoBackupSettings | null>(null);
  const [target, setTarget] = useState<BackupStore | null>(null);
  const [listings, setListings] = useState<Listing[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(() => {
    fetchBackupState().then(({ settings: s, target: t, listings: l }) => {
      setSettings(s);
      setTarget(t);
      setListings(l);
    });
  }, []);
  useEffect(load, [load]);

  const setFrequency = async (frequency: BackupFrequency) => {
    const next = { ...(settings ?? (await getAutoBackup(appDb))), frequency };
    await setSetting(appDb, 'autoBackup', next);
    setSettings(next);
  };

  const backUp = async () => {
    if (!target) return;
    setBusy('Backing up…');
    try {
      await backUpNow(appDb, target);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      toast({ message: `Backed up to ${target.label}` });
    } catch (e) {
      Alert.alert('Backup failed', e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
      load();
    }
  };

  const restore = (store: BackupStore, file: BackupFile) =>
    Alert.alert(`Restore ${format(file.at, 'd MMM yyyy, h:mm a')}?`, 'This replaces everything in Paisa Pulse with this backup.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Restore',
        style: 'destructive',
        onPress: async () => {
          setBusy('Restoring…');
          try {
            const backup = parseBackup(await store.read(file.name));
            await restoreBackup(appDb, backup);
            await usePrefs.getState().hydrate();
            Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
            toast({ message: 'Backup restored' });
            router.replace('/');
          } catch (e) {
            Alert.alert('Couldn’t restore', e instanceof Error ? e.message : String(e));
          } finally {
            setBusy(null);
          }
        },
      },
    ]);

  const fromFile = async () => {
    try {
      if (await pickAndRestoreBackup()) {
        await usePrefs.getState().hydrate();
        toast({ message: 'Backup restored' });
        router.replace('/');
      }
    } catch (e) {
      Alert.alert('Couldn’t restore', e instanceof Error ? e.message : String(e));
    }
  };

  const where =
    target?.kind === 'icloud'
      ? 'Backups go to iCloud Drive › Paisa Pulse › Backups, so they’re safe if you lose or change your iPhone.'
      : Platform.OS === 'android'
        ? 'Backups stay on this phone and are included in Android’s Google backup, so they come back when you set up a new phone.'
        : 'Backups stay on this iPhone (and in its iCloud backup). Sign in to iCloud Drive to keep them off the phone too.';

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 60 }}>
        <LargeTitle title={restoreMode ? 'Restore' : 'Backups'} />
        {databaseWasReset ? (
          <View style={[styles.banner, { backgroundColor: '#FF95001F' }]}>
            <Text style={[type.subhead, { color: colors.label }]}>
              Your previous Paisa Pulse data was encrypted with a key that stays on the old phone, so it couldn’t be opened here. Restore one of
              your backups below.
            </Text>
          </View>
        ) : null}

        {restoreMode ? null : (
          <>
            <GroupHeader title="Automatic backup" />
            <InsetGroup>
              <Menu
                items={(Object.keys(FREQUENCY) as BackupFrequency[]).map((f) => ({ title: FREQUENCY[f], checked: settings?.frequency === f, onPress: () => setFrequency(f) }))}
              >
                {(open) => (
                  <GroupRow
                    title="Back up"
                    value={settings ? FREQUENCY[settings.frequency] : ''}
                    leading={<CategoryIcon icon="arrow.clockwise" color="#34C759" size={30} square />}
                    chevron
                    onPress={open}
                  />
                )}
              </Menu>
              <GroupRow
                title="Location"
                value={target?.label ?? ''}
                leading={<CategoryIcon icon={target?.kind === 'icloud' ? 'icloud.fill' : 'iphone'} color="#007AFF" size={30} square />}
              />
              <GroupRow
                title={busy ?? 'Back Up Now'}
                tinted
                leading={busy ? <ActivityIndicator color={colors.accent} /> : <CategoryIcon icon="square.and.arrow.up" color={colors.accent} size={30} square />}
                onPress={busy ? undefined : backUp}
              />
            </InsetGroup>
            <Text style={[type.footnote, styles.footnote, { color: settings?.lastError ? colors.expense : colors.secondary }]}>
              {settings?.lastError
                ? `Last backup failed: ${settings.lastError}`
                : settings?.lastAt
                  ? `Last backup ${formatDistanceToNow(settings.lastAt, { addSuffix: true })}. `
                  : 'No backups yet. '}
              {settings?.lastError ? '' : where} The newest 14 are kept.
            </Text>
          </>
        )}

        {listings === null ? (
          <ActivityIndicator style={{ marginTop: 30 }} color={colors.accent} />
        ) : (
          listings.map(({ store, available, files }) => (
            <View key={store.kind}>
              <GroupHeader title={`Restore from ${store.label}`} />
              {!available ? (
                <Text style={[type.footnote, styles.footnote, { color: colors.secondary }]}>Not available. Check that you’re signed in to iCloud Drive.</Text>
              ) : files.length ? (
                <InsetGroup>
                  {files.slice(0, 14).map((f) => (
                    <GroupRow
                      key={f.name}
                      title={format(f.at, 'EEE d MMM yyyy')}
                      value={format(f.at, 'h:mm a')}
                      leading={<CategoryIcon icon="doc.text.fill" color="#8E8E93" size={30} square />}
                      chevron
                      onPress={() => restore(store, f)}
                    />
                  ))}
                </InsetGroup>
              ) : (
                <Text style={[type.footnote, styles.footnote, { color: colors.secondary }]}>No backups here yet.</Text>
              )}
            </View>
          ))
        )}

        <GroupHeader title="Files" />
        <InsetGroup>
          {restoreMode ? null : (
            <GroupRow
              title="Export Backup File…"
              leading={<CategoryIcon icon="square.and.arrow.up" color="#5E5CE6" size={30} square />}
              chevron
              onPress={() => shareJsonBackup().catch((e: Error) => Alert.alert('Couldn’t back up', e.message))}
            />
          )}
          <GroupRow title="Restore from a File…" leading={<CategoryIcon icon="square.and.arrow.down" color="#5E5CE6" size={30} square />} chevron onPress={fromFile} />
        </InsetGroup>
      </ScrollView>
      <TopBar
        title={restoreMode ? 'Restore' : 'Backups'}
        scrollY={scrollY}
        leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={() => router.back()} />}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  footnote: { paddingHorizontal: 32, paddingTop: 8 },
  banner: { marginHorizontal: 16, marginTop: 12, borderRadius: 16, padding: 14 },
});
