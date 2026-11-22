/**
 * Dynamic Expo config on top of app.json.
 *
 * PAISA_FREE_SIGNING=1 makes the build installable with a FREE Apple ID (SideStore, AltStore,
 * Sideloadly). A free account allows 3 apps per device and every app extension takes a slot, and it
 * can't use iCloud. So this build:
 *   - keeps the app + the widget extension (2 slots) and drops the Siri/Shortcuts extension,
 *   - drops the iCloud container (backups go to Files › On My iPhone › Paisa Pulse instead).
 * Android ignores the flag. CI sets it for the iOS build (.github/workflows/build.yml).
 *
 * PAISA_BUILD_NUMBER (CI run number) and PAISA_RELEASE_REPO feed the in-app update check.
 */
const FREE_SIGNING = process.env.PAISA_FREE_SIGNING === '1';
const BUILD_NUMBER = Number(process.env.PAISA_BUILD_NUMBER || 0);
const RELEASE_REPO = process.env.PAISA_RELEASE_REPO || 'PoRiFiRo123/paisa-pulse';

/** @param {{ config: import('expo/config').ExpoConfig }} ctx */
module.exports = ({ config }) => {
  const plugins = (config.plugins ?? [])
    .filter((p) => !(FREE_SIGNING && pluginName(p) === 'react-native-cloud-storage'))
    .map((p) => {
      // Only the widget target in a free build; every target otherwise.
      if (pluginName(p) === '@bacons/apple-targets') {
        return FREE_SIGNING ? ['@bacons/apple-targets', { match: 'widget' }] : p;
      }
      return p;
    });

  return {
    ...config,
    ios: {
      ...config.ios,
      ...(BUILD_NUMBER ? { buildNumber: String(BUILD_NUMBER) } : {}),
      infoPlist: {
        ...config.ios?.infoPlist,
        // Documents (and the backups in it) show up in Files › On My iPhone › Paisa Pulse.
        UIFileSharingEnabled: true,
        LSSupportsOpeningDocumentsInPlace: true,
      },
    },
    android: {
      ...config.android,
      ...(BUILD_NUMBER ? { versionCode: BUILD_NUMBER } : {}),
    },
    plugins,
    extra: {
      ...config.extra,
      freeSigning: FREE_SIGNING,
      buildNumber: BUILD_NUMBER,
      releaseRepo: RELEASE_REPO,
    },
  };
};

function pluginName(p) {
  return Array.isArray(p) ? p[0] : p;
}
