import type { Metadata, Viewport } from "next";
import { GeistSans } from "geist/font/sans";
import { GeistMono } from "geist/font/mono";
import { Inter } from "next/font/google";
import "./globals.css";
import { SessionProvider } from "@/components/session-provider";

// Geist is the product typeface (the iOS app sets it too). Inter is loaded for the
// Olien console only, which follows Squads' typography rather than the app's.
const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" });

const description = "Dollars on your phone, sent by name. Recourse is a money app for USDC on Arc.";

export const metadata: Metadata = {
  metadataBase: new URL("https://recourse-arc.vercel.app"),
  title: {
    default: "Recourse",
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
  themeColor: "#ffffff",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable} ${inter.variable}`}>
      <body>
        <SessionProvider>{children}</SessionProvider>
      </body>
    </html>
  );
}
