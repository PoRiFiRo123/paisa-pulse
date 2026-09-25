import { toBase64 } from '../loadStatement';


it('matches Node base64 for all padding cases', () => {
  for (const s of ['', 'a', 'ab', 'abc', 'abcd', '₹ statement\n%PDF']) {
    const bytes = new TextEncoder().encode(s);
    expect(toBase64(bytes)).toBe(Buffer.from(bytes).toString('base64'));
  }
});
