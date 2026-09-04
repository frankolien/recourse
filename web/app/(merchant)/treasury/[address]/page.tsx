import { notFound } from "next/navigation";
import { TreasuryAccountPage } from "@/components/treasury/treasury-account";
import { accountParam } from "@/lib/treasury";

interface PageProps {
  params: Promise<{ address: string }>;
}

export default async function TreasuryAccount({ params }: PageProps) {
  const address = accountParam((await params).address);
  if (!address) notFound();
  return <TreasuryAccountPage address={address} />;
}
