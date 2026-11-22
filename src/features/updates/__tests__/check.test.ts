import { assetFor, buildFromTag, fetchLatestRelease, pickUpdate, type Release, sideStoreInstallUrl } from '../check';

const release: Release = {
  tag_name: 'build-12',
  html_url: 'https://github.com/o/r/releases/tag/build-12',
  body: ' Notes ',
  published_at: '2026-11-22T00:00:00Z',
  assets: [
    { name: 'PaisaPulse.apk', browser_download_url: 'https://x/PaisaPulse.apk' },
    { name: 'PaisaPulse.ipa', browser_download_url: 'https://x/PaisaPulse.ipa' },
  ],
};

describe('update check', () => {
  it('reads the build number from the tag', () => {
    expect(buildFromTag('build-12')).toBe(12);
    expect(buildFromTag('v1.0.0')).toBeNull();
  });

  it('picks the file for each platform', () => {
    expect(assetFor(release, 'android')).toBe('https://x/PaisaPulse.apk');
    expect(assetFor(release, 'ios')).toBe('https://x/PaisaPulse.ipa');
    expect(assetFor({ ...release, assets: [] }, 'ios')).toBeNull();
  });

  it('offers only newer builds, never on local builds', () => {
    expect(pickUpdate(release, 11, 'ios')).toMatchObject({ build: 12, fileUrl: 'https://x/PaisaPulse.ipa', notes: 'Notes' });
    expect(pickUpdate(release, 12, 'ios')).toBeNull();
    expect(pickUpdate(release, 13, 'android')).toBeNull();
    expect(pickUpdate(release, 0, 'android')).toBeNull();
    expect(pickUpdate({ ...release, tag_name: 'nightly' }, 5, 'android')).toBeNull();
  });

  it('builds a SideStore install link', () => {
    expect(sideStoreInstallUrl('https://x/a b.ipa')).toBe('sidestore://install?url=https%3A%2F%2Fx%2Fa%20b.ipa');
  });

  it('returns null when GitHub has no release', async () => {
    const fetcher = jest.fn().mockResolvedValue({ ok: false });
    await expect(fetchLatestRelease('o/r', fetcher as unknown as typeof fetch)).resolves.toBeNull();
  });
});
