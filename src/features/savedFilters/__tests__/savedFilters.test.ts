/**
 * @jest-environment node
 */
import { createTestDb } from '@/db/__tests__/testDb';

import { deleteSavedFilter, listSavedFilters, parsePayload, saveFilter, updateSavedFilter } from '../savedFilters';


it('saves, lists in order, updates and deletes filters', async () => {
  const { db, raw } = createTestDb();
  const payload = { search: 'swiggy', filters: { monthOffset: 0, accountIds: ['a'], categoryIds: [null], types: ['expense' as const] } };
  const a = await saveFilter(db, '  Food delivery ', payload, 1);
  await saveFilter(db, 'Card spends', { ...payload, search: '' }, 2);
  let rows = await listSavedFilters(db);
  expect(rows.map((r) => r.name)).toEqual(['Food delivery', 'Card spends']);
  expect(rows[0].payload).toEqual(payload);
  await updateSavedFilter(db, a.id, { name: 'Swiggy', payload: { ...payload, search: 'zomato' } }, 3);
  rows = await listSavedFilters(db);
  expect([rows[0].name, rows[0].payload.search]).toEqual(['Swiggy', 'zomato']);
  await deleteSavedFilter(db, a.id);
  expect(await listSavedFilters(db)).toHaveLength(1);
  await expect(saveFilter(db, '   ', payload)).rejects.toThrow();
  raw.close();
});

it('parses bad payloads safely', () => {
  expect(parsePayload('nope').filters.accountIds).toEqual([]);
  expect(parsePayload('{"filters":{"monthOffset":"x","types":"bad"}}').filters).toEqual({ monthOffset: null, accountIds: [], categoryIds: [], types: [] });
});
