import {
  ArrowUpRight,
  Banknote,
  Cloud,
  FileText,
  Info,
  Landmark,
  Percent,
  Zap,
} from "lucide-react";
import Link from "next/link";
import {
  explorerAddressUrl,
  usdcAddress,
  vaultAddress,
  yieldAdapterAddress,
} from "@/lib/contracts";

const metrics = [
  { label: "Escrow TVL", value: "$640.00", sub: "3 open positions", icon: <Landmark size={13} /> },
  { label: "USYC yield (APY)", value: "4.9%", sub: "Accrues while held", icon: <Percent size={13} /> },
  { label: "Earnings accrued", value: "$1.24", sub: "Since 20 Jul 2026", icon: <Banknote size={13} /> },
  { label: "Yield fee", value: "10%", sub: "To the protocol treasury", icon: <Percent size={13} /> },
];

const positions = [
  { merchant: "CloudCompute", product: "24.00 USDC", yield: "+$0.04", days: "9 days", icon: <Cloud size={16} /> },
  { merchant: "FileStore", product: "120.00 USDC", yield: "+$0.31", days: "5 days", icon: <FileText size={16} /> },
  { merchant: "DesignVault", product: "320.00 USDC", yield: "+$0.89", days: "5 days", icon: <Zap size={16} /> },
];

const contracts = [
  { label: "Settlement vault", address: vaultAddress },
  { label: "USYC yield adapter", address: yieldAdapterAddress },
  { label: "USDC (Circle)", address: usdcAddress },
];

function shorten(address: string) {
  return `${address.slice(0, 10)}…${address.slice(-8)}`;
}

export function VaultPage() {
  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Vault and yield</h1>
          <p>Escrowed USDC earns USYC yield while protected, and merchants are paid instantly at T plus 0.</p>
        </div>
      </header>

      <section className="metric-grid">
        {metrics.map((metric) => (
          <article className="metric-card" key={metric.label}>
            <span>{metric.icon} {metric.label}</span>
            <strong>{metric.value}</strong>
            <small>{metric.sub}</small>
          </article>
        ))}
      </section>

      <div className="two-col">
        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading">
              <div><h2>Escrow positions</h2><p>Protected balances currently earning yield</p></div>
              <Link href="/protection">View protections</Link>
            </div>
            <div className="records-table">
              <div className="records-head">
                <span>Merchant</span><span>Escrowed</span><span>Held</span><span>Yield</span><span /></div>
              {positions.map((item) => (
                <div className="records-row" key={item.merchant}>
                  <div className="records-id">
                    <span className="records-badge">{item.icon}</span>
                    <div className="records-cell"><strong>{item.merchant}</strong><small>USYC backed</small></div>
                  </div>
                  <div className="records-cell num"><strong>{item.product}</strong></div>
                  <div className="records-cell"><strong>{item.days}</strong></div>
                  <div><span className="status-pill green">{item.yield}</span></div>
                  <span />
                </div>
              ))}
            </div>
          </section>

          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Instant settlement (T plus 0)</h2></div>
            <ol className="how-steps">
              <li><span><Banknote size={15} /></span><div><strong>Buyer pays into escrow</strong><p>USDC is deposited into the USYC adapter and starts earning immediately.</p></div></li>
              <li><span><Zap size={15} /></span><div><strong>LP fronts the merchant</strong><p>The settlement vault advances the merchant their funds the same block, no waiting on the dispute window.</p></div></li>
              <li><span><Landmark size={15} /></span><div><strong>Vault is repaid on release</strong><p>When the window closes, the vault is repaid principal plus its share of yield.</p></div></li>
            </ol>
          </section>
        </div>

        <section className="dash-panel">
          <div className="panel-heading compact"><h2>Onchain contracts</h2></div>
          <div className="address-list">
            {contracts.map((item) => (
              <div className="address-row" key={item.label}>
                <div>
                  <span>{item.label}</span>
                  <code>{shorten(item.address)}</code>
                </div>
                <a href={explorerAddressUrl(item.address)} target="_blank" rel="noreferrer">ArcScan <ArrowUpRight size={13} /></a>
              </div>
            ))}
          </div>
          <div className="panel-note">
            <Info size={16} />
            <span>On testnet the adapter is a MockUSYCAdapter that simulates yield-bearing shares. It swaps to a USYC Teller adapter once mainnet access is approved.</span>
          </div>
        </section>
      </div>
    </div>
  );
}
