import { format } from 'date-fns';
import * as DocumentPicker from 'expo-document-picker';
import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';

import { appDb } from '@/db/client';

import { exportBackup, exportCsv, parseBackup, restoreBackup } from './backup';

async function shareText(filename: string, content: string, mimeType: string, UTI: string) {
  const file = new File(Paths.cache, filename);
  if (file.exists) file.delete();
  file.create();
  file.write(content);
  await Sharing.shareAsync(file.uri, { mimeType, UTI, dialogTitle: filename });
}

/** Share a CSV of all transactions through the native share sheet. */
export async function shareCsvExport() {
  const csv = await exportCsv(appDb);
  await shareText(`paisa-pulse-${format(Date.now(), 'yyyy-MM-dd')}.csv`, csv, 'text/csv', 'public.comma-separated-values-text');
}

/** Share a full JSON backup the user can keep in Files, Drive or anywhere. */
export async function shareJsonBackup() {
  const backup = await exportBackup(appDb);
  await shareText(`paisa-pulse-backup-${format(Date.now(), 'yyyy-MM-dd')}.json`, JSON.stringify(backup), 'application/json', 'public.json');
}

/** Pick a backup file and replace all data with it. Returns false if cancelled. */
export async function pickAndRestoreBackup(): Promise<boolean> {
  const result = await DocumentPicker.getDocumentAsync({ type: ['application/json', 'text/plain', '*/*'], copyToCacheDirectory: true });
  if (result.canceled || !result.assets?.[0]) return false;
  const text = await new File(result.assets[0].uri).text();
  const backup = parseBackup(text);
  await restoreBackup(appDb, backup);
  return true;
}
