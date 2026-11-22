/**
 * In-app update check (like CarLink's): CI publishes every main build as a GitHub Release
 * tagged `build-<run number>` with PaisaPulse.apk and PaisaPulse.ipa (.github/workflows/build.yml).
 * The app compares that number with its own BUILD_NUMBER.
 */

export type ReleaseAsset = { name: string; browser_download_url: string };
export type Release = { tag_name: string; html_url: string; body?: string | null; published_at?: string; assets: ReleaseAsset[] };

export type AvailableUpdate = {
  build: number;
  /** Release page (notes, both files). */
  pageUrl: string;
  /** Direct file for this platform, if the release has one. */
  fileUrl: string | null;
  notes: string;
  publishedAt: string | null;
};

/** `build-42` → 42; anything else → null. */
export function buildFromTag(tag: string): number | null {
  const m = /^build-(\d+)$/.exec(tag.trim());
  return m ? Number(m[1]) : null;
}

export function assetFor(release: Release, platform: 'ios' | 'android'): string | null {
  const ext = platform === 'ios' ? '.ipa' : '.apk';
  return release.assets.find((a) => a.name.toLowerCase().endsWith(ext))?.browser_download_url ?? null;
}

/**
 * The update to offer, or null. Local builds (`current` 0) never nag: they have no number to compare.
 */
export function pickUpdate(release: Release, current: number, platform: 'ios' | 'android'): AvailableUpdate | null {
  const build = buildFromTag(release.tag_name);
  if (!current || build === null || build <= current) return null;
  return {
    build,
    pageUrl: release.html_url,
    fileUrl: assetFor(release, platform),
    notes: (release.body ?? '').trim(),
    publishedAt: release.published_at ?? null,
  };
}

/**
 * On iPhone, hand the .ipa straight to SideStore (it re-signs with the user's Apple ID);
 * if SideStore isn't installed the caller falls back to the release page.
 */
export function sideStoreInstallUrl(ipaUrl: string): string {
  return `sidestore://install?url=${encodeURIComponent(ipaUrl)}`;
}

export async function fetchLatestRelease(repo: string, fetcher: typeof fetch = fetch): Promise<Release | null> {
  const res = await fetcher(`https://api.github.com/repos/${repo}/releases/latest`, {
    headers: { Accept: 'application/vnd.github+json' },
  });
  if (!res.ok) return null;
  return (await res.json()) as Release;
}
