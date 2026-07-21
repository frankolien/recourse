"use client";

import { ArrowRight, Check, KeyRound, Mail, ShieldCheck, Wallet } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { GoogleMark } from "@/components/google-mark";
import { defaultDemoProfile, saveDemoProfile } from "@/lib/demo-profile";

const benefits = [
  "Protection terms locked before payment",
  "Deterministic dispute outcomes",
  "Instant merchant settlement",
];

export function SignInPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");

  function begin(emailAddress = defaultDemoProfile.email) {
    const localName = emailAddress.split("@")[0].split(/[._-]/)[0];
    const firstName = localName ? localName.charAt(0).toUpperCase() + localName.slice(1) : "Frank";
    saveDemoProfile({ ...defaultDemoProfile, firstName, email: emailAddress });
    router.push("/onboarding");
  }

  function submitEmail(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    begin(email || defaultDemoProfile.email);
  }

  return (
    <main className="auth-page">
      <section className="auth-story">
        <Link href="/" className="auth-brand"><BrandMark /><span>Recourse</span></Link>
        <div className="auth-story-copy">
          <span className="auth-kicker"><ShieldCheck size={14} /> Buyer protection for USDC</span>
          <h1>Payments should come with protection.</h1>
          <p>Use stablecoins with clear refund terms, verifiable outcomes, and no wallet complexity up front.</p>
          <ul>
            {benefits.map((benefit) => <li key={benefit}><Check size={16} /> {benefit}</li>)}
          </ul>
        </div>
        <p className="auth-network"><span /> Live prototype on Arc Testnet</p>
      </section>

      <section className="auth-panel-wrap">
        <div className="auth-panel">
          <span className="demo-label">Interactive demo</span>
          <h2>Welcome to Recourse</h2>
          <p>Create an account or sign in to continue.</p>

          <button className="auth-provider" onClick={() => begin()}>
            <GoogleMark /> Continue with Google
          </button>
          <button className="auth-provider" onClick={() => begin()}>
            <KeyRound size={18} /> Sign in with passkey
          </button>

          <div className="auth-divider"><span>or continue with email</span></div>

          <form onSubmit={submitEmail}>
            <label htmlFor="email">Email address</label>
            <div className="auth-input"><Mail size={17} /><input id="email" type="email" placeholder="you@company.com" value={email} onChange={(event) => setEmail(event.target.value)} /></div>
            <button className="auth-submit" type="submit">Continue <ArrowRight size={16} /></button>
          </form>

          <button className="auth-wallet" onClick={() => begin()}><Wallet size={17} /> Connect an existing wallet</button>
          <small className="auth-disclaimer">Authentication is simulated for this testnet prototype. No credentials are collected.</small>
          <p className="auth-terms">By continuing, you agree to the Terms and Privacy Policy.</p>
        </div>
      </section>
    </main>
  );
}
