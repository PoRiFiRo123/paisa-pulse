import { Directory, File, Paths } from 'expo-file-system';
import { Platform } from 'react-native';

import { HAS_CUSTOM_NATIVE } from '@/lib/native';

import type { BackupStore } from './auto';

/**
 * This phone's app storage (Documents/backups). On iOS it's part of the device's iCloud
 * backup; on Android it's included in Google's Auto Backup (see plugins/withAndroidBackupRules).
 */
export const deviceStore: BackupStore = {
  kind: 'device',
  label: Platform.OS === 'ios' ? 'On this iPhone' : 'On this phone',
  async available() {
    return Platform.OS !== 'web';
  },
  async list() {
    const dir = new Directory(Paths.document, 'backups');
    if (!dir.exists) return [];
    return dir.list().filter((f): f is File => f instanceof File).map((f) => f.name);
  },
  async write(name, text) {
    const dir = new Directory(Paths.document, 'backups');
    if (!dir.exists) dir.create({ intermediates: true });
    const file = new File(dir, name);
    if (file.exists) file.delete();
    file.create();
    file.write(text);
  },
  async read(name) {
    return new File(new Directory(Paths.document, 'backups'), name).text();
  },
  async remove(name) {
    const file = new File(new Directory(Paths.document, 'backups'), name);
    if (file.exists) file.delete();
  },
};

type CloudModule = typeof import('react-native-cloud-storage');
let cloud: CloudModule | null | undefined;
function cloudModule(): CloudModule | null {
  if (cloud !== undefined) return cloud;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports -- lazy: absent in Expo Go
    cloud = Platform.OS === 'ios' && HAS_CUSTOM_NATIVE ? (require('react-native-cloud-storage') as CloudModule) : null;
  } catch {
    cloud = null;
  }
  return cloud;
}

const DIR = '/Backups';

/** iCloud Drive › Paisa Pulse › Backups (visible in the Files app). iOS development/store builds only. */
export function iCloudStore(): BackupStore | null {
  const m = cloudModule();
  if (!m) return null;
  const storage = new m.CloudStorage(m.CloudStorageProvider.ICloud);
  const scope = m.CloudStorageScope.Documents;
  return {
    kind: 'icloud',
    label: 'iCloud Drive',
    available: () => storage.isCloudAvailable().catch(() => false),
    async list() {
      if (!(await storage.exists(DIR, scope))) return [];
      return storage.readdir(DIR, scope);
    },
    async write(name, text) {
      if (!(await storage.exists(DIR, scope))) await storage.mkdir(DIR, scope);
      await storage.writeFile(`${DIR}/${name}`, text, scope);
    },
    async read(name) {
      // A file may be only a placeholder until iCloud downloads it.
      await storage.downloadFile(`${DIR}/${name}`, scope).catch(() => {});
      return storage.readFile(`${DIR}/${name}`, scope);
    },
    async remove(name) {
      await storage.unlink(`${DIR}/${name}`, scope);
    },
  };
}

/** The store automatic backups use: iCloud Drive when signed in on iOS, otherwise this phone. */
export async function preferredStore(): Promise<BackupStore> {
  const icloud = iCloudStore();
  if (icloud && (await icloud.available())) return icloud;
  return deviceStore;
}

/** Every store that might hold backups, for the restore list. */
export function allStores(): BackupStore[] {
  const icloud = iCloudStore();
  return icloud ? [icloud, deviceStore] : [deviceStore];
}
