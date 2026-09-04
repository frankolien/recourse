import { notFound } from "next/navigation";
import { TreasuryScheduledPage } from "@/components/treasury/treasury-scheduled";
import { accountParam } from "@/lib/treasury";

interface PageProps {
  params: Promise<{ address: string }>;
}

export default async function TreasuryScheduled({ params }: PageProps) {
  const address = accountParam((await params).address);
  if (!address) notFound();
  return <TreasuryScheduledPage address={address} />;
}
