import { notFound } from "next/navigation";
import { TreasuryProposalPage } from "@/components/treasury/treasury-proposal";
import { accountParam, hashParam } from "@/lib/treasury";

interface PageProps {
  params: Promise<{ address: string; txHash: string }>;
}

export default async function TreasuryProposal({ params }: PageProps) {
  const resolved = await params;
  const address = accountParam(resolved.address);
  const txHash = hashParam(resolved.txHash);
  if (!address || !txHash) notFound();
  return <TreasuryProposalPage address={address} txHash={txHash} />;
}
