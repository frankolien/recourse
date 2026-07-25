import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Protected checkout",
  description: "A USDC checkout escrowed under an immutable refund policy on Arc. Open it in the Recourse app to verify and pay.",
};

export default function PayLayout({ children }: { children: React.ReactNode }) {
  return children;
}
