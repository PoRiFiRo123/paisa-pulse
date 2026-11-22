import Constants, { ExecutionEnvironment } from 'expo-constants';
import { Platform } from 'react-native';

/**
 * True in Expo Go, which lacks our custom native modules (widgets, alternate icons).
 * Code that needs them must `require` them lazily behind `HAS_CUSTOM_NATIVE`.
 */
export const IS_EXPO_GO = Constants.executionEnvironment === ExecutionEnvironment.StoreClient;
export const HAS_CUSTOM_NATIVE = Platform.OS !== 'web' && !IS_EXPO_GO;

const extra = (Constants.expoConfig?.extra ?? {}) as { freeSigning?: boolean; buildNumber?: number; releaseRepo?: string };

/**
 * Built for a free Apple ID (PAISA_FREE_SIGNING=1, see app.config.js): no Siri/Shortcuts extension
 * and no iCloud. Backups stay in Files › On My iPhone › Paisa Pulse.
 */
export const FREE_SIGNING = Platform.OS === 'ios' && extra.freeSigning === true;

/** CI run number this build came from (0 for local builds). */
export const BUILD_NUMBER = Number(extra.buildNumber ?? 0);

/** GitHub repository whose Releases carry new builds. */
export const RELEASE_REPO = extra.releaseRepo ?? 'PoRiFiRo123/paisa-pulse';
