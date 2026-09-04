"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { useSession } from "@/components/session-provider";
import { publicClient } from "@/lib/contracts";
import {
  errorMessage,
  getAccount,
  getAccounts,
  getAddressBook,
  getLedger,
  getLinkedAddresses,
  getProposal,
  getProposals,
  getScheduled,
  linkAddress,
  linkMessage,
  nowSeconds,
  sameAddress,
  type Hex,
  type ProposalStatus,
} from "@/lib/treasury";
import { walletFor } from "@/lib/wallet";

// Every open treasury page refetches on this cadence; the indexer refreshes views
// every 15 s, so 10 s keeps a member at most one interval behind the chain.
export const POLL_MS = 10_000;

export const treasuryKeys = {
  linked: ["treasury", "linked"] as const,
  accounts: ["treasury", "accounts"] as const,
  account: (address: string) => ["treasury", "account", address] as const,
  proposals: (address: string, statuses: string) => ["treasury", "proposals", address, statuses] as const,
  proposal: (address: string, txHash: string) => ["treasury", "proposal", address, txHash] as const,
  scheduled: (address: string) => ["treasury", "scheduled", address] as const,
  vetoCall: (address: string, hash: string) => ["treasury", "veto-call", address, hash] as const,
  ledger: (address: string) => ["treasury", "ledger", address] as const,
  addressBook: (address: string) => ["treasury", "address-book", address] as const,
  nativeBalance: (address: string) => ["treasury", "native-balance", address] as const,
};

export function useLinkedAddresses() {
  return useQuery({ queryKey: treasuryKeys.linked, queryFn: getLinkedAddresses });
}

export function useAccounts() {
  return useQuery({ queryKey: treasuryKeys.accounts, queryFn: getAccounts, refetchInterval: POLL_MS });
}

export function useTreasuryAccount(address: string) {
  return useQuery({
    queryKey: treasuryKeys.account(address),
    queryFn: () => getAccount(address),
    refetchInterval: POLL_MS,
  });
}

export function useProposals(address: string, statuses?: ProposalStatus[]) {
  const filter = statuses?.join(",") ?? "";
  return useQuery({
    queryKey: treasuryKeys.proposals(address, filter),
    queryFn: () => getProposals(address, statuses),
    refetchInterval: POLL_MS,
  });
}

export function useProposal(address: string, txHash: string) {
  return useQuery({
    queryKey: treasuryKeys.proposal(address, txHash),
    queryFn: () => getProposal(address, txHash),
    refetchInterval: POLL_MS,
  });
}

export function useScheduled(address: string) {
  return useQuery({
    queryKey: treasuryKeys.scheduled(address),
    queryFn: () => getScheduled(address),
    refetchInterval: POLL_MS,
  });
}

export function useLedger(address: string, limit = 100) {
  return useQuery({
    queryKey: treasuryKeys.ledger(address),
    queryFn: () => getLedger(address, limit),
    refetchInterval: POLL_MS,
  });
}

export function useAddressBook(address: string) {
  return useQuery({ queryKey: treasuryKeys.addressBook(address), queryFn: () => getAddressBook(address) });
}

// On Arc the native balance is USDC (18 decimals); it is what a signer's own key
// spends on gas when it vetoes from the browser.
export function useNativeBalance(address: string | null) {
  return useQuery({
    queryKey: treasuryKeys.nativeBalance(address ?? ""),
    queryFn: () => publicClient.getBalance({ address: address as Hex }),
    enabled: Boolean(address),
    refetchInterval: 15_000,
  });
}

export function useNow(): number {
  const [now, setNow] = useState(nowSeconds);
  useEffect(() => {
    const timer = setInterval(() => setNow(nowSeconds()), 1000);
    return () => clearInterval(timer);
  }, []);
  return now;
}

export type LinkState = "checking" | "linking" | "linked" | "error";

// Shared across hook instances so two panels on one page do not both ask the key
// to sign the link message.
const inflightLinks = new Map<string, Promise<void>>();

// Ensures the signed-in user's browser key is a linked address, signing the link
// message once if it is not. Every account that names the key as a signer becomes
// visible after that.
export function useBrowserKeyLink(): { address: Hex | null; state: LinkState; error: string | null } {
  const { account } = useSession();
  const accountId = account?.accountId;
  const linked = useLinkedAddresses();
  const queryClient = useQueryClient();
  const [address, setAddress] = useState<Hex | null>(null);
  const [state, setState] = useState<LinkState>("checking");
  const [error, setError] = useState<string | null>(null);
  const attempted = useRef(false);

  useEffect(() => {
    if (accountId != null) setAddress(walletFor(accountId).address);
  }, [accountId]);

  useEffect(() => {
    if (accountId == null || !address || !linked.data) return;
    if (linked.data.some((entry) => sameAddress(entry.address, address))) {
      setState("linked");
      return;
    }
    if (attempted.current) return;
    attempted.current = true;
    setState("linking");
    const key = address.toLowerCase();
    let job = inflightLinks.get(key);
    if (!job) {
      job = walletFor(accountId)
        .signMessage({ message: linkMessage(address, accountId) })
        .then((signature) => linkAddress({ address: key, signature }))
        .then(() => queryClient.invalidateQueries({ queryKey: treasuryKeys.linked }))
        .finally(() => inflightLinks.delete(key));
      inflightLinks.set(key, job);
    }
    job
      .then(() => setState("linked"))
      .catch((cause: unknown) => {
        setState("error");
        setError(errorMessage(cause));
      });
  }, [accountId, address, linked.data, queryClient]);

  useEffect(() => {
    if (linked.error) {
      setState("error");
      setError(errorMessage(linked.error));
    }
  }, [linked.error]);

  return { address, state, error };
}
