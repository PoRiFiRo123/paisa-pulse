import { resolveAppGroup } from '..';

const BASE = 'group.com.paisapulse.app';

describe('resolveAppGroup', () => {
  it('keeps the base group without re-signing', () => {
    expect(resolveAppGroup(BASE, [])).toBe(BASE);
  });
  it('uses the renamed group after free-account re-signing', () => {
    expect(resolveAppGroup(BASE, ['group.com.paisapulse.app.ABC123XYZ'])).toBe('group.com.paisapulse.app.ABC123XYZ');
  });
  it('ignores unrelated groups', () => {
    expect(resolveAppGroup(BASE, ['group.com.other.app.ABC'])).toBe(BASE);
  });
});
