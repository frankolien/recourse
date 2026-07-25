import type { Metadata, Viewport } from "next";
import { GeistSans } from "geist/font/sans";
import { GeistMono } from "geist/font/mono";
import "./globals.css";
import { SessionProvider } from "@/components/session-provider";

const description = "Deterministic, publicly verifiable buyer protection for USDC payments on Arc. Disputes are computed, not decided.";

export const metadata: Metadata = {
  metadataBase: new URL("https://recourse-arc.vercel.app"),
  title: {
    default: "Recourse | Buyer protection for USDC",
    template: "%s | Recourse",
  },
  description,
  openGraph: {
    title: "Recourse",
    description,
    url: "/",
    siteName: "Recourse",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Recourse",
    description,
  },
};

export const viewport: Viewport = {
  themeColor: "#f6f5f0",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body>
        <SessionProvider>{children}</SessionProvider>
      </body>
    </html>
  );
}
