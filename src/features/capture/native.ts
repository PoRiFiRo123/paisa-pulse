import { Platform } from 'react-native';

import { HAS_CUSTOM_NATIVE } from '@/lib/native';

// Speech recognition and OCR are custom native modules: present in development/store
// builds, missing in Expo Go. They're required lazily so Expo Go never loads them.

type SpeechModule = typeof import('expo-speech-recognition');
type TextModule = typeof import('expo-text-extractor');

let speech: SpeechModule | null | undefined;
let text: TextModule | null | undefined;

export function speechModule(): SpeechModule | null {
  if (speech !== undefined) return speech;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    speech = HAS_CUSTOM_NATIVE ? (require('expo-speech-recognition') as SpeechModule) : null;
  } catch {
    speech = null;
  }
  return speech;
}

function textModule(): TextModule | null {
  if (text !== undefined) return text;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    text = HAS_CUSTOM_NATIVE ? (require('expo-text-extractor') as TextModule) : null;
  } catch {
    text = null;
  }
  return text;
}

/** True when the phone can turn speech into text in this build. */
export function canListen(): boolean {
  const m = speechModule();
  try {
    return Boolean(m?.ExpoSpeechRecognitionModule.isRecognitionAvailable());
  } catch {
    return false;
  }
}

export function canReadImages(): boolean {
  return Boolean(textModule()?.isSupported);
}

/** On-device text recognition (Apple Vision / Google ML Kit). Returns lines or blocks of text. */
export async function readImageText(uri: string): Promise<string[]> {
  const m = textModule();
  if (!m) throw new Error('Reading screenshots needs the Paisa Pulse app build (not Expo Go).');
  // The Android module expects a plain path for files.
  const path = Platform.OS === 'android' && uri.startsWith('file://') ? decodeURI(uri.replace('file://', '')) : uri;
  return m.extractTextFromImage(path);
}
