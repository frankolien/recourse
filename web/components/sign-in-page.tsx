"use client";

import { Apple, Check, Loader2, ShieldCheck, Smartphone } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { GoogleSignInButton } from "@/components/google-signin";
import { useSession } from "@/components/session-provider";
import { readDemoProfile } from "@/lib/demo-profile";

const benefits = [
  "Protection terms locked before payment",
  "Deterministic dispute outcomes",
  "Instant merchant settlement",
];

export function SignInPage() {
  const router = useRouter();
  const { account, loading, signInWithGoogle } = useSession();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Already signed in: skip the form. New accounts finish onboarding first.
  useEffect(() => {
    if (!loading && account) {
      router.replace(readDemoProfile().onboardingComplete ? "/dashboard" : "/onboarding");
    }
  }, [account, loading, router]);

  const onGoogle = useCallback(
    async (idToken: string) => {
      setBusy(true);
      setError(null);
      try {
        await signInWithGoogle(idToken);
        router.replace(readDemoProfile().onboardingComplete ? "/dashboard" : "/onboarding");
      } catch (signInError) {
        setError(signInError instanceof Error ? signInError.message : "Sign-in failed");
        setBusy(false);
      }
    },
    [router, signInWithGoogle],
  );

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
          <h2>Welcome to Recourse</h2>
          <p>Sign in to your merchant workspace.</p>

          {busy ? (
            <div className="auth-busy"><Loader2 className="spin" size={18} /> Signing you in…</div>
          ) : (
            <GoogleSignInButton onCredential={onGoogle} onError={setError} />
          )}

          {error && <p className="auth-error">{error}</p>}

          <button className="auth-provider" type="button" disabled title="Sign in with Apple runs in the Recourse iOS app">
            <Apple size={18} /> Continue with Apple
          </button>

          <p className="auth-mobile-note"><Smartphone size={15} /> Buying on Recourse? Sign in happens in the mobile app.</p>
          <p className="auth-terms">By continuing, you agree to the Terms and Privacy Policy.</p>
        </div>
      </section>
    </main>
  );
}
