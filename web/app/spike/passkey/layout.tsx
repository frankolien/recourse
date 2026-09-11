import type { Metadata, Viewport } from "next";

export const metadata: Metadata = {
  title: "Passkey account spike",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: "#070907",
};

export default function SpikeLayout({ children }: { children: React.ReactNode }) {
  return children;
}
