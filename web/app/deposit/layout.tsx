import type { Metadata, Viewport } from "next";
import "./deposit.css";
import { Providers } from "@/components/providers";

export const metadata: Metadata = {
  title: "Add money from another chain",
  description: "Move USDC from Base, Arbitrum or Ethereum to your Recourse account on Arc, through Circle's own bridge.",
};

// The page is opened from inside the app, whose interior is flat black, so it
// carries the app's night palette rather than the marketing site's white.
export const viewport: Viewport = {
  themeColor: "#070907",
};

export default function DepositLayout({ children }: { children: React.ReactNode }) {
  return (
    <Providers>
      <div className="dep">{children}</div>
    </Providers>
  );
}
