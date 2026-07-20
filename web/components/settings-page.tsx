"use client";

import { ArrowUpRight } from "lucide-react";
import { useState } from "react";
import {
  arcTestnet,
  escrowAddress,
  explorerAddressUrl,
  registryAddress,
  usdcAddress,
  vaultAddress,
  yieldAdapterAddress,
} from "@/lib/contracts";

const contracts = [
  { label: "Recourse escrow", address: escrowAddress },
  { label: "Policy registry", address: registryAddress },
  { label: "Settlement vault", address: vaultAddress },
  { label: "USYC yield adapter", address: yieldAdapterAddress },
  { label: "USDC (Circle)", address: usdcAddress },
];

const notifications = [
  { key: "disputes", title: "Dispute updates", copy: "When a dispute is filed or a verdict lands", on: true },
  { key: "settlement", title: "Instant settlement", copy: "When a merchant is paid from escrow", on: true },
  { key: "yield", title: "Yield summaries", copy: "Weekly escrow earnings recap", on: false },
];

function shorten(address: string) {
  return `${address.slice(0, 12)}…${address.slice(-8)}`;
}

export function SettingsPage() {
  const [toggles, setToggles] = useState<Record<string, boolean>>(
    Object.fromEntries(notifications.map((item) => [item.key, item.on])),
  );

  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Settings</h1>
          <p>Your profile, network, and the contracts this workspace reads from.</p>
        </div>
      </header>

      <div className="two-col">
        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Profile</h2></div>
            <div className="field-list">
              <label className="field-row"><span>Display name</span><input defaultValue="Frank Olien" /></label>
              <label className="field-row"><span>Contact email</span><input defaultValue="frank@recourse.demo" type="email" /></label>
              <label className="field-row"><span>Payout address</span><input defaultValue="0xD70beb0ce6E261fdaa8Cb72607316C6bcA16A082" /></label>
            </div>
          </section>

          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Notifications</h2></div>
            <div className="field-list" style={{ gap: 0 }}>
              {notifications.map((item) => (
                <div className="toggle-row" key={item.key}>
                  <div><strong>{item.title}</strong><small>{item.copy}</small></div>
                  <button
                    type="button"
                    role="switch"
                    aria-checked={toggles[item.key]}
                    aria-label={item.title}
                    className={toggles[item.key] ? "toggle-pill on" : "toggle-pill"}
                    onClick={() => setToggles((current) => ({ ...current, [item.key]: !current[item.key] }))}
                  />
                </div>
              ))}
            </div>
          </section>
        </div>

        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Network</h2></div>
            <div className="field-list">
              <div className="field-row"><span>Chain</span><input value="Arc Testnet" readOnly /></div>
              <div className="field-row"><span>Chain ID</span><input value={String(arcTestnet.id)} readOnly /></div>
              <div className="field-row"><span>RPC endpoint</span><input value={arcTestnet.rpcUrls.default.http[0]} readOnly /></div>
            </div>
          </section>

          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Contract addresses</h2></div>
            <div className="address-list">
              {contracts.map((item) => (
                <div className="address-row" key={item.label}>
                  <div><span>{item.label}</span><code>{shorten(item.address)}</code></div>
                  <a href={explorerAddressUrl(item.address)} target="_blank" rel="noreferrer">ArcScan <ArrowUpRight size={13} /></a>
                </div>
              ))}
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}
