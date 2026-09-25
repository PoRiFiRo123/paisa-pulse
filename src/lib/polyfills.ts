import { getRandomValues } from 'expo-crypto';

// Hermes has no Web Crypto. uuidv7 silently falls back to Math.random without it.
const g = globalThis as { crypto?: { getRandomValues?: unknown } };
if (typeof g.crypto?.getRandomValues !== 'function') {
  g.crypto = { ...g.crypto, getRandomValues };
}
