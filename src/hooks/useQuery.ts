import { addDatabaseChangeListener } from 'expo-sqlite';
import { type DependencyList, useEffect, useLayoutEffect, useRef, useState } from 'react';

/**
 * Run an async database read and re-run it whenever any table changes.
 * Unlike Drizzle's useLiveQuery this works for joins and aggregates.
 */
export function useQuery<T>(fn: () => Promise<T>, deps: DependencyList, initial: T): { data: T; loaded: boolean } {
  const [state, setState] = useState({ data: initial, loaded: false });
  const fnRef = useRef(fn);
  useLayoutEffect(() => {
    fnRef.current = fn;
  });

  useEffect(() => {
    let cancelled = false;
    let scheduled = false;
    const run = () => {
      scheduled = false;
      fnRef
        .current()
        .then((data) => !cancelled && setState({ data, loaded: true }))
        .catch((e) => console.warn('query failed', e));
    };
    run();
    // One refetch per burst of row changes (e.g. a multi-row update).
    const sub = addDatabaseChangeListener(() => {
      if (scheduled) return;
      scheduled = true;
      setTimeout(run, 0);
    });
    return () => {
      cancelled = true;
      sub.remove();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return state;
}
