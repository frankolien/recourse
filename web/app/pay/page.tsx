"use client";

import { ArrowRight, ShieldCheck, Smartphone } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { API_BASE } from "@/lib/api";

type ScannedRequest = {
  v: number;
  chainId: number;
  escrow: string;
  policyId: number;
  merchant: string;
  amount: string;
  orderRef: string;
};

type OrderSummary = {
  itemName: string;
  description: string;
  imageHash?: string;
};

// The payload rides in ?request= (or the fragment) exactly as the QR encodes it, so
// this page can decode it without any server round trip.
function decodePayload(raw: string): ScannedRequest | null {
  try {
    const base64 = raw.replaceAll("-", "+").replaceAll("_", "/");
    const parsed = JSON.parse(atob(base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=")));
    if (!parsed || typeof parsed.amount !== "string" || typeof parsed.merchant !== "string") return null;
    return parsed as ScannedRequest;
  } catch {
    return null;
  }
}

function extractRawPayload(): string | null {
  const params = new URLSearchParams(window.location.search);
  for (const name of ["request", "payload", "code"]) {
    const value = params.get(name);
    if (value) return value;
  }
  const fragment = window.location.hash.replace(/^#/, "");
  if (!fragment) return null;
  const eq = fragment.indexOf("=");
  if (eq >= 0 && ["request", "payload", "code"].includes(fragment.slice(0, eq))) {
    return fragment.slice(eq + 1);
  }
  return fragment || null;
}

function formatUsdc(baseUnits: string): string {
  const value = Number(baseUnits) / 1_000_000;
  return value.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 6 });
}

export default function PayPage() {
  const [raw, setRaw] = useState<string | null>(null);
  const [request, setRequest] = useState<ScannedRequest | null>(null);
  const [order, setOrder] = useState<OrderSummary | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const payload = extractRawPayload();
    setRaw(payload);
    setRequest(payload ? decodePayload(payload) : null);
    setReady(true);
  }, []);

  useEffect(() => {
    if (!request || request.v < 2) return;
    let cancelled = false;
    fetch(`${API_BASE}/api/orders/${request.orderRef}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((manifest) => {
        if (!cancelled && manifest?.itemName) {
          setOrder({
            itemName: manifest.itemName,
            description: manifest.description,
            imageHash: manifest.imageHash,
          });
        }
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [request]);

  const appLink = raw ? `recourse://pay?request=${raw}` : "recourse://pay";

  return (
    <div className="pay-landing">
      <header className="pay-landing-brand">
        <BrandMark />
        <span>Recourse</span>
      </header>

      {!ready ? null : request ? (
        <main className="pay-landing-card">
          <span className="pay-landing-shield">
            <ShieldCheck size={22} />
          </span>
          <h1>Protected checkout</h1>
          {order?.imageHash && (
            /* Content-addressed image; the app re-verifies the hash, the web preview just renders it. */
            // eslint-disable-next-line @next/next/no-img-element
            <img
              className="pay-landing-image"
              src={`${API_BASE}/api/orders/image/${order.imageHash}`}
              alt={order.itemName}
            />
          )}
          <div className="pay-landing-amount">
            {formatUsdc(request.amount)} <span>USDC</span>
          </div>
          {order ? (
            <>
              <strong className="pay-landing-item">{order.itemName}</strong>
              <p className="pay-landing-description">{order.description}</p>
            </>
          ) : (
            <p className="pay-landing-description">Merchant {request.merchant.slice(0, 6)}…{request.merchant.slice(-4)} · Policy #{request.policyId}</p>
          )}
          <a className="pay-landing-open" href={appLink}>
            <Smartphone size={17} /> Open in the Recourse app
          </a>
          <p className="pay-landing-hint">
            This payment is escrowed under an immutable refund policy on Arc. Paying
            requires the Recourse iOS app, which verifies the order end to end before any
            funds move. Don&apos;t have it?{" "}
            <a href="https://testflight.apple.com/join/rWWg1wCb" target="_blank" rel="noreferrer">
              Join the free beta on TestFlight
            </a>.
          </p>
        </main>
      ) : (
        <main className="pay-landing-card">
          <h1>Nothing to pay here</h1>
          <p className="pay-landing-description">
            This link is missing its checkout payload. Ask the merchant to share the QR
            card again.
          </p>
          <Link className="pay-landing-open" href="/">
            Recourse home <ArrowRight size={15} />
          </Link>
        </main>
      )}
    </div>
  );
}
