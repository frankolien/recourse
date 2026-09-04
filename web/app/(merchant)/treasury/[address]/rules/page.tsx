import { notFound } from "next/navigation";
import { TreasuryRulesPage } from "@/components/treasury/treasury-rules";
import { accountParam } from "@/lib/treasury";

interface PageProps {
  params: Promise<{ address: string }>;
}

export default async function TreasuryRules({ params }: PageProps) {
  const address = accountParam((await params).address);
  if (!address) notFound();
  return <TreasuryRulesPage address={address} />;
}
