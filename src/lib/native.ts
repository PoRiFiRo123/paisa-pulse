import Constants, { ExecutionEnvironment } from 'expo-constants';
import { Platform } from 'react-native';

/**
 * True in Expo Go, which lacks our custom native modules (widgets, alternate icons).
 * Code that needs them must `require` them lazily behind `HAS_CUSTOM_NATIVE`.
 */
export const IS_EXPO_GO = Constants.executionEnvironment === ExecutionEnvironment.StoreClient;
export const HAS_CUSTOM_NATIVE = Platform.OS !== 'web' && !IS_EXPO_GO;
