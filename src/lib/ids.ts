import './polyfills';

import { uuidv7 } from 'uuidv7';

/** Time-sortable UUIDv7, used for every primary key. */
export function newId(): string {
  return uuidv7();
}
