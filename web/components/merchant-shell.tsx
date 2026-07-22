"use client";

import {
  Bell,
  Braces,
  ChevronDown,
  CircleDollarSign,
  CircleHelp,
  FileText,
  Home,
  Loader2,
  LockKeyhole,
  LogOut,
  ReceiptText,
  Settings,
  ShieldCheck,
  WalletCards,
  type LucideIcon,
} from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";
import { useAccount } from "wagmi";
import { BrandMark } from "@/components/brand-mark";
import { ConnectWallet, shortAddress } from "@/components/connect-wallet";
import { useSession } from "@/components/session-provider";
import { LottiePlayer } from "@/components/lottie-player";
import pingAnim from "@/lib/lottie/ping.json";
import { arcTestnet } from "@/lib/contracts";
import { accountInitials, accountName } from "@/lib/session";

const GITHUB_URL = "https://github.com/frankolien/recourse";

interface NavItem {
  href: string;
  label: string;
  icon: LucideIcon;
  badge?: string;
}

const primaryNav: NavItem[] = [
  { href: "/dashboard", label: "Dashboard", icon: Home },
  { href: "/payments", label: "Payments", icon: CircleDollarSign },
  { href: "/protection", label: "Protection", icon: ShieldCheck },
  { href: "/disputes", label: "Disputes", icon: WalletCards },
  { href: "/receipts", label: "Receipts", icon: ReceiptText },
  { href: "/vault", label: "Vault", icon: LockKeyhole, badge: "LP" },
  { href: "/policies", label: "Policies", icon: FileText },
];

const bottomNav: NavItem[] = [
  { href: "/settings", label: "Settings", icon: Settings },
  { href: "/support", label: "Support", icon: CircleHelp },
];

const titles: Record<string, string> = {
  "/dashboard": "Dashboard",
  "/payments": "Payments",
  "/protection": "Protection",
  "/disputes": "Disputes",
  "/receipts": "Receipts",
  "/vault": "Vault and yield",
  "/policies": "Policies",
  "/settings": "Settings",
  "/support": "Support",
};

function isActive(pathname: string, href: string) {
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function MerchantShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { account, loading, signOut } = useSession();
  const { address, isConnected } = useAccount();
  const section = Object.keys(titles).find((href) => isActive(pathname, href));
  const title = section ? titles[section] : "Recourse";

  // The merchant workspace is account-gated. Public pages (landing, verifier) are not.
  useEffect(() => {
    if (!loading && !account) router.replace("/signin");
  }, [loading, account, router]);

  async function handleSignOut() {
    await signOut();
    router.replace("/signin");
  }

  if (loading || !account) {
    return (
      <div className="dash-gate">
        <Loader2 className="spin" size={20} /> {loading ? "Loading your workspace…" : "Redirecting to sign in…"}
      </div>
    );
  }

  return (
    <div className="dash-shell">
      <aside className="dash-sidebar">
        <Link href="/dashboard" className="dash-brand">
          <BrandMark />
          <span>Recourse</span>
        </Link>
        <p className="dash-brand-copy">Buyer protection for<br />USDC payments</p>

        <nav className="dash-nav" aria-label="Primary navigation">
          {primaryNav.map((item) => {
            const Icon = item.icon;
            const active = isActive(pathname, item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={active ? "dash-nav-item active" : "dash-nav-item"}
                aria-current={active ? "page" : undefined}
              >
                <Icon size={18} /> {item.label}
                {item.badge && <span className="nav-badge">{item.badge}</span>}
              </Link>
            );
          })}
          <a className="dash-nav-item" href={GITHUB_URL} target="_blank" rel="noreferrer">
            <Braces size={18} /> Developers
          </a>
        </nav>

        <div className="dash-nav-bottom">
          {bottomNav.map((item) => {
            const Icon = item.icon;
            const active = isActive(pathname, item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={active ? "dash-nav-item active" : "dash-nav-item"}
                aria-current={active ? "page" : undefined}
              >
                <Icon size={18} /> {item.label}
              </Link>
            );
          })}
          <Link className="switch-role" href="/verify/5">
            <ShieldCheck size={18} /> Open public verifier
          </Link>
          <button className="dash-nav-item sign-out" type="button" onClick={handleSignOut}>
            <LogOut size={18} /> Sign out
          </button>
        </div>
      </aside>

      <main className="dash-main">
        <header className="dash-topbar">
          <div className="dash-topbar-title">
            <small>Merchant workspace</small>
            <strong>{title}</strong>
          </div>
          <div className="dash-header-actions">
            <span className="network-select" title={`Chain ${arcTestnet.id}`}>
              <LottiePlayer animationData={pingAnim} className="lottie-ping" /> Arc Testnet
            </span>
            <ConnectWallet />
            <Link className="notification-button" href="/disputes" aria-label="Notifications">
              <Bell size={17} />
              <span className="notification-dot" />
            </Link>
            <Link className="profile-button" href="/settings">
              <span className="profile-avatar">{accountInitials(account)}</span>
              <span>
                <strong>{accountName(account)}</strong>
                <small>{isConnected && address ? shortAddress(address) : account.email ?? "Not connected"}</small>
              </span>
              <ChevronDown size={14} />
            </Link>
          </div>
        </header>

        {children}
      </main>
    </div>
  );
}
