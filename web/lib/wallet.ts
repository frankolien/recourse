"use client";

// Every signed-in account gets a browser-resident Arc wallet, provisioned on first
// use, so the web workspace works like the phone: no extension required. Prototype
// custody within R4 (testnet keys are throwaways): the key is generated locally,
// scoped to the account id in localStorage, and never leaves this device.

import { useEffect, useState } from "react";
import { createWalletClient, erc20Abi, http } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { arcTestnet, publicClient, usdcAddress } from "./contracts";

const KEY_PREFIX = "recourse.arcwallet.v1.";

export function walletFor(accountId: number) {
  const key = `${KEY_PREFIX}${accountId}`;
  let pk = window.localStorage.getItem(key) as `0x${string}` | null;
  if (!pk) {
    pk = generatePrivateKey();
    window.localStorage.setItem(key, pk);
  }
  return privateKeyToAccount(pk);
}

export function useArcWallet(accountId: number | undefined): `0x${string}` | null {
  const [address, setAddress] = useState<`0x${string}` | null>(null);
  useEffect(() => {
    if (accountId == null) return;
    setAddress(walletFor(accountId).address);
  }, [accountId]);
  return address;
}

export function useUsdcBalance(address: `0x${string}` | null): bigint | null {
  const [balance, setBalance] = useState<bigint | null>(null);
  useEffect(() => {
    if (!address) return;
    let alive = true;
    const load = () =>
      publicClient
        .readContract({
          address: usdcAddress,
          abi: erc20Abi,
          functionName: "balanceOf",
          args: [address],
        })
        .then((value) => {
          if (alive) setBalance(value);
        })
        .catch(() => {});
    load();
    const timer = setInterval(load, 15_000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, [address]);
  return balance;
}

export async function sendUsdc(
  accountId: number,
  to: `0x${string}`,
  amountBaseUnits: bigint,
): Promise<`0x${string}`> {
  const account = walletFor(accountId);
  const wallet = createWalletClient({ account, chain: arcTestnet, transport: http() });
  const hash = await wallet.writeContract({
    address: usdcAddress,
    abi: erc20Abi,
    functionName: "transfer",
    args: [to, amountBaseUnits],
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error("transfer reverted onchain");
  return hash;
}
