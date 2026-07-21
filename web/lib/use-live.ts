"use client";

import { useEffect, useState } from "react";

export interface LiveState<T> {
  data: T | null;
  loading: boolean;
  // Set when the backend is unreachable or returns an error, so pages can show an
  // honest "indexer offline" state instead of fabricated rows.
  error: string | null;
}

export function useLive<T>(fetcher: () => Promise<T>): LiveState<T> {
  const [state, setState] = useState<LiveState<T>>({ data: null, loading: true, error: null });

  useEffect(() => {
    let alive = true;
    fetcher()
      .then((data) => {
        if (alive) setState({ data, loading: false, error: null });
      })
      .catch((e: unknown) => {
        if (alive) setState({ data: null, loading: false, error: e instanceof Error ? e.message : String(e) });
      });
    return () => {
      alive = false;
    };
    // The fetchers are module-level stable references; run once on mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return state;
}
