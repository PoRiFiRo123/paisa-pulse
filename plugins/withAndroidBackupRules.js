// Android Auto Backup rules for Paisa Pulse.
//
// Google's backup should carry our JSON backups (files/backups/) to a new phone, but not the
// SQLCipher database (its key lives in the Android Keystore and never leaves the device) or
// the SecureStore preferences. Replaces expo-secure-store's rules, which back up only
// shared preferences (so set `configureAndroidBackup: false` on expo-secure-store).
const fs = require('fs');
const path = require('path');
const { withAndroidManifest, withDangerousMod } = require('expo/config-plugins');

const RULES = `
    <include domain="sharedpref" path="."/>
    <exclude domain="sharedpref" path="SecureStore"/>
    <include domain="file" path="backups/"/>`;

const FULL_BACKUP = `<?xml version="1.0" encoding="utf-8"?>
<!-- Auto Backup for Android 11 and lower -->
<full-backup-content>${RULES}
</full-backup-content>
`;

const EXTRACTION = `<?xml version="1.0" encoding="utf-8"?>
<!-- Auto Backup and device transfer for Android 12 and higher -->
<data-extraction-rules>
  <cloud-backup>${RULES}
  </cloud-backup>
  <device-transfer>${RULES}
  </device-transfer>
</data-extraction-rules>
`;

module.exports = function withAndroidBackupRules(config) {
  config = withAndroidManifest(config, (c) => {
    const app = c.modResults.manifest.application?.[0];
    if (app) {
      app.$['android:allowBackup'] = 'true';
      app.$['android:fullBackupContent'] = '@xml/paisa_backup_rules';
      app.$['android:dataExtractionRules'] = '@xml/paisa_data_extraction_rules';
    }
    return c;
  });
  return withDangerousMod(config, [
    'android',
    async (c) => {
      const dir = path.join(c.modRequest.platformProjectRoot, 'app/src/main/res/xml');
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'paisa_backup_rules.xml'), FULL_BACKUP);
      fs.writeFileSync(path.join(dir, 'paisa_data_extraction_rules.xml'), EXTRACTION);
      return c;
    },
  ]);
};
