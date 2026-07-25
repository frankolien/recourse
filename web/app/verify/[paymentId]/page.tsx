import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { VerifyPage } from "@/components/verify-page";

interface PageProps {
  params: Promise<{ paymentId: string }>;
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { paymentId } = await params;
  return {
    title: `Verify payment #${paymentId}`,
    description: `Recompute the onchain verdict for payment #${paymentId} from public Arc state, in your browser, and check it against what the contract decided.`,
  };
}

export default async function PaymentVerifyPage({ params }: PageProps) {
  const { paymentId } = await params;

  if (!/^\d+$/.test(paymentId) || paymentId === "0") notFound();

  return <VerifyPage paymentId={BigInt(paymentId)} />;
}
