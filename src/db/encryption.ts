import { File } from 'expo-file-system';
import { getRandomBytes } from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import { defaultDatabaseDirectory, deleteDatabaseSync, openDatabaseSync, type SQLiteDatabase, type SQLiteOpenOptions } from 'expo-sqlite';

const KEY_NAME = 'paisa-pulse.db-key';

/** 256-bit key generated once per install and kept in the Keychain / Keystore. */
function databaseKey(): string {
  const options = { keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY };
  let key = SecureStore.getItem(KEY_NAME, options);
  if (!key) {
    key = Array.from(getRandomBytes(32), (b) => b.toString(16).padStart(2, '0')).join('');
    SecureStore.setItem(KEY_NAME, key, options);
  }
  return key;
}

function fileExists(name: string): boolean {
  return new File(`file://${defaultDatabaseDirectory}/${name}`).exists;
}

/** True when the native SQLite is SQLCipher (development/store builds, not Expo Go). */
function hasSQLCipher(db: SQLiteDatabase): boolean {
  try {
    return Boolean(db.getFirstSync<{ cipher_version: string }>('PRAGMA cipher_version;')?.cipher_version);
  } catch {
    return false;
  }
}

/**
 * Open the app database, encrypted at rest with SQLCipher when the build includes it.
 *
 * - Expo Go (plain SQLite): opens `plainName` unencrypted.
 * - SQLCipher builds: opens `encryptedName` with a per-install key. On first launch after
 *   upgrading from an unencrypted build, the old database is exported into the encrypted
 *   file and then deleted.
 */
export function openEncryptedDatabase(plainName: string, encryptedName: string, options: SQLiteOpenOptions): SQLiteDatabase {
  const probe = openDatabaseSync(':memory:');
  const cipher = hasSQLCipher(probe);
  probe.closeSync();
  if (!cipher) return openDatabaseSync(plainName, options);

  const hexKey = databaseKey();
  const keyPragma = `PRAGMA key = "x'${hexKey}'";`;

  if (!fileExists(encryptedName) && fileExists(plainName)) {
    const plain = openDatabaseSync(plainName);
    const target = `${defaultDatabaseDirectory}/${encryptedName}`.replace(/'/g, "''");
    plain.execSync(`ATTACH DATABASE '${target}' AS encrypted KEY "x'${hexKey}'";`);
    plain.execSync("SELECT sqlcipher_export('encrypted');");
    plain.execSync('DETACH DATABASE encrypted;');
    plain.closeSync();
    deleteDatabaseSync(plainName);
  }

  const db = openDatabaseSync(encryptedName, options);
  db.execSync(keyPragma);
  try {
    // Fails fast with "file is not a database" if the key is wrong.
    db.getFirstSync('SELECT count(*) FROM sqlite_master;');
    return db;
  } catch {
    // The file came back from a phone backup or migration but its key (kept only on the
    // old device) didn't. It can't be read here, so set it aside and start fresh; the app
    // then offers to restore from a Paisa Pulse backup.
    db.closeSync();
    setAsideUnreadable(encryptedName);
    databaseWasReset = true;
    const fresh = openDatabaseSync(encryptedName, options);
    fresh.execSync(keyPragma);
    return fresh;
  }
}

/** True when this launch found an encrypted database it couldn't open (see above). */
export let databaseWasReset = false;

function setAsideUnreadable(name: string) {
  const stamp = Date.now();
  for (const suffix of ['', '-wal', '-shm']) {
    const file = new File(`file://${defaultDatabaseDirectory}/${name}${suffix}`);
    if (file.exists) file.move(new File(`file://${defaultDatabaseDirectory}/${name}.unreadable-${stamp}${suffix}`));
  }
}
