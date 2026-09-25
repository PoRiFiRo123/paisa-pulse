import { HAS_CUSTOM_NATIVE } from '@/lib/native';

/** Alternate icons configured in app.json (expo-alternate-app-icons). */
export const APP_ICONS = [
  { name: null, title: 'Default' },
  { name: 'Midnight', title: 'Midnight' },
  { name: 'Saffron', title: 'Saffron' },
  { name: 'Mint', title: 'Mint' },
  { name: 'Mono', title: 'Mono' },
] as const;
export type AppIconName = (typeof APP_ICONS)[number]['name'];

type IconsModule = typeof import('expo-alternate-app-icons');

/** The module throws at import in Expo Go, so it is required lazily. */
function iconsModule(): IconsModule | null {
  if (!HAS_CUSTOM_NATIVE) return null;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports -- lazy: absent in Expo Go
    const mod = require('expo-alternate-app-icons') as IconsModule;
    return mod.supportsAlternateIcons ? mod : null;
  } catch {
    return null;
  }
}

export const appIconsSupported = () => iconsModule() !== null;

export function currentAppIcon(): AppIconName {
  return (iconsModule()?.getAppIconName() as AppIconName) ?? null;
}

export async function setAppIcon(name: AppIconName): Promise<void> {
  const mod = iconsModule();
  if (!mod) return;
  if (name === null) await mod.resetAppIcon();
  else await mod.setAlternateAppIcon(name as Parameters<IconsModule['setAlternateAppIcon']>[0]);
}
