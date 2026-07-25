import type { Metadata } from "next";
import { VaultPage } from "@/components/vault-page";

export const metadata: Metadata = {
  title: "Settlement vault",
  description: "LPs fund T+0 merchant advances and earn advance fees plus escrow float yield. Live TVL, share price, and outstanding claims on Arc.",
};

export default function Vault() {
  return <VaultPage />;
}
