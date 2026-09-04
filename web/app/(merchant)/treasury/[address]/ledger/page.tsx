import { notFound } from "next/navigation";
import { TreasuryLedgerPage } from "@/components/treasury/treasury-ledger";
import { accountParam } from "@/lib/treasury";

interface PageProps {
  params: Promise<{ address: string }>;
}

export default async function TreasuryLedger({ params }: PageProps) {
  const address = accountParam((await params).address);
  if (!address) notFound();
  return <TreasuryLedgerPage address={address} />;
}
