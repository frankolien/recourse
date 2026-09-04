import { notFound } from "next/navigation";
import { TreasuryPayPage } from "@/components/treasury/treasury-pay";
import { accountParam } from "@/lib/treasury";

interface PageProps {
  params: Promise<{ address: string }>;
}

export default async function TreasuryPay({ params }: PageProps) {
  const address = accountParam((await params).address);
  if (!address) notFound();
  return <TreasuryPayPage address={address} />;
}
