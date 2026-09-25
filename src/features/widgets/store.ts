import { File, Paths } from 'expo-file-system';

import type { WidgetSnapshot } from './snapshot';

/** Android widgets render in a headless task, so the latest snapshot is kept in a small file. */
const FILE = 'widget-snapshot.json';

export function writeSnapshotFile(snapshot: WidgetSnapshot) {
  const file = new File(Paths.document, FILE);
  if (!file.exists) file.create();
  file.write(JSON.stringify(snapshot));
}

export async function readSnapshotFile(): Promise<WidgetSnapshot | null> {
  try {
    const file = new File(Paths.document, FILE);
    return file.exists ? (JSON.parse(await file.text()) as WidgetSnapshot) : null;
  } catch {
    return null;
  }
}
