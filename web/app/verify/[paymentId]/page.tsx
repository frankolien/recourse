import { notFound } from "next/navigation";
import { VerifyPage } from "@/components/verify-page";

interface PageProps {
  params: Promise<{ paymentId: string }>;
}

export default async function PaymentVerifyPage({ params }: PageProps) {
  const { paymentId } = await params;

  if (!/^\d+$/.test(paymentId) || paymentId === "0") notFound();

  return <VerifyPage paymentId={BigInt(paymentId)} />;
}
