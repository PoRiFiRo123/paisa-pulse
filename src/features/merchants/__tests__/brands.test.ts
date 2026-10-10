import { logoUrl, matchBrand, monogram, onColor } from '../brands';

describe('brands', () => {
  it('recognises merchants from payees and narrations, most specific first', () => {
    expect(matchBrand('SWIGGY LIMITED')?.name).toBe('Swiggy');
    expect(matchBrand('Swiggy Instamart')?.name).toBe('Swiggy Instamart');
    expect(matchBrand('AMAZON PRIME VIDEO')?.name).toBe('Amazon Prime');
    expect(matchBrand('Amazon Pay India')?.name).toBe('Amazon');
    expect(matchBrand('youtube premium')?.name).toBe('YouTube');
    expect(matchBrand('Rahul Sharma')).toBeNull();
    expect(matchBrand(null)).toBeNull();
  });

  it('picks readable monogram colours and letters', () => {
    expect(onColor('#FC8019')).toBe('#000000');
    expect(onColor('#E50914')).toBe('#FFFFFF');
    expect(onColor('#F8CB46')).toBe('#000000');
    expect(onColor('#000000')).toBe('#FFFFFF');
    expect(monogram("McDonald's")).toBe('M');
    expect(monogram('1mg')).toBe('1');
  });

  it('builds logo URLs from the brand domain only', () => {
    expect(logoUrl(matchBrand('Netflix')!)).toBe('https://www.google.com/s2/favicons?domain=netflix.com&sz=128');
    expect(logoUrl(matchBrand('BESCOM bill')!)).toBeNull();
  });
});
