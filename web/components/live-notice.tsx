"use client";

import { Inbox, Loader2, WifiOff } from "lucide-react";
import type { LiveState } from "@/lib/use-live";

// Renders the non-row states of a live list: loading, indexer offline, or empty.
// Callers render their own rows when data is present and defer to this otherwise, so
// a down backend reads as an honest offline notice rather than fabricated records.
export function LiveNotice({
  state,
  emptyTitle,
  emptyHint,
}: {
  state: LiveState<unknown>;
  emptyTitle: string;
  emptyHint: string;
}) {
  if (state.loading) {
    return (
      <div className="state-inline">
        <Loader2 size={18} className="spin" />
        <div>
          <strong>Loading onchain data</strong>
          <p>Reading the live indexer projection of Arc state.</p>
        </div>
      </div>
    );
  }

  if (state.error) {
    return (
      <div className="state-inline error">
        <WifiOff size={18} />
        <div>
          <strong>Indexer offline</strong>
          <p>Start the backend to load live onchain records. Verifiable reads still work directly against Arc.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="state-inline">
      <Inbox size={18} />
      <div>
        <strong>{emptyTitle}</strong>
        <p>{emptyHint}</p>
      </div>
    </div>
  );
}
