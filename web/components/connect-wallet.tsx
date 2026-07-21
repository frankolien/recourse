"use client";

import { LogOut, Wallet } from "lucide-react";
import { useAccount, useConnect, useDisconnect } from "wagmi";

export function shortAddress(address: string) {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

export function ConnectWallet({ className = "wallet-button" }: { className?: string }) {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    return (
      <button className={className} onClick={() => disconnect()} title="Disconnect wallet">
        <Wallet size={15} /> {shortAddress(address)} <LogOut size={13} />
      </button>
    );
  }

  return (
    <button
      className={className}
      onClick={() => connectors[0] && connect({ connector: connectors[0] })}
      disabled={isPending || connectors.length === 0}
    >
      <Wallet size={15} /> {isPending ? "Connecting…" : "Connect wallet"}
    </button>
  );
}
