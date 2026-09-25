import { useMigrations } from 'drizzle-orm/expo-sqlite/migrator';
import { type ReactNode, useEffect, useState } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';

import { purgeDeletedTransactions } from '@/features/transactions/mutations';
import { usePrefs } from '@/stores/prefs';

import { appDb, db, prepareDatabase } from './client';
import migrations from './migrations/migrations';
import { seedStarterCategories } from './seed';

/** Runs migrations, seeds starter categories, purges old soft deletes and loads preferences before rendering the app. */
export function DatabaseProvider({ children }: { children: ReactNode }) {
  const [prepared, setPrepared] = useState(Platform.OS !== 'web');
  useEffect(() => {
    if (!prepared) prepareDatabase().then(() => setPrepared(true));
  }, [prepared]);
  return prepared ? <DatabaseReady>{children}</DatabaseReady> : null;
}

function DatabaseReady({ children }: { children: ReactNode }) {
  const migration = useMigrations(db, migrations);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<Error | undefined>();

  useEffect(() => {
    if (!migration.success) return;
    (async () => {
      await seedStarterCategories(appDb);
      await purgeDeletedTransactions(appDb);
      await usePrefs.getState().hydrate();
      setReady(true);
    })().catch(setError);
  }, [migration.success]);

  const failure = migration.error ?? error;
  if (failure) {
    return (
      <View style={styles.center}>
        <Text style={styles.title}>Couldn’t open your data</Text>
        <Text style={styles.detail}>{failure.message}</Text>
      </View>
    );
  }
  // Keep the splash-coloured screen until the database is ready (a few ms on a normal launch).
  if (!ready) return null;
  return children;
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 8 },
  title: { fontSize: 17, fontWeight: '600' },
  detail: { fontSize: 13, color: '#8A8A8E', textAlign: 'center' },
});
