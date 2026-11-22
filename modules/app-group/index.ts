import { requireOptionalNativeModule } from 'expo';

const native = requireOptionalNativeModule<{ appGroups: string[] }>('AppGroup');

/**
 * The App Group to use at run time. After free-account re-signing (SideStore/AltStore) the group
 * gets a suffix; the real name is in Info.plist › ALTAppGroups. Falls back to `base`.
 * Mirrors `Snapshot.appGroup` in targets/widget/Snapshot.swift.
 */
export function resolveAppGroup(base: string, groups: string[] = native?.appGroups ?? []): string {
  return groups.find((g) => g === base) ?? groups.find((g) => g.startsWith(`${base}.`)) ?? base;
}
