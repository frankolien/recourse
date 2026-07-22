"use client";

import {
  ArrowLeft,
  ArrowRight,
  BriefcaseBusiness,
  Check,
  ChevronRight,
  Code2,
  HandCoins,
  Landmark,
  LockKeyhole,
  ShieldCheck,
  Smartphone,
  Sparkles,
  Wallet,
} from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useEffect, useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { useSession } from "@/components/session-provider";
import { defaultDemoProfile, readDemoProfile, RecourseRole, saveDemoProfile } from "@/lib/demo-profile";

// Web onboarding covers merchants and liquidity providers only. Per R5 the buyer
// experience lives in the Flutter mobile app, so it is framed as a pointer, not a
// selectable web workspace.
const roles = [
  { id: "merchant" as const, icon: BriefcaseBusiness, title: "Merchant", copy: "Accept protected payments and receive funds immediately." },
  { id: "liquidity" as const, icon: HandCoins, title: "Liquidity provider", copy: "Supply liquidity to settlement vaults and earn yield." },
];

const previewContent = [
  {
    eyebrow: "Purpose-built workspaces",
    title: "Start with the tools you actually need.",
    copy: "Merchant and vault operations stay focused, while every workspace reads from the same protected-payment system.",
    label: "Workspace model",
    value: "Switch roles anytime",
  },
  {
    eyebrow: "Fintech-first identity",
    title: "Your account comes before your wallet.",
    copy: "Set up a familiar business profile now. Connect an onchain wallet only when an action needs a signature.",
    label: "Authentication",
    value: "No wallet required yet",
  },
  {
    eyebrow: "Live Arc infrastructure",
    title: "Configure how protected funds move.",
    copy: "Choose a settlement workspace and start with a clear protection policy instead of an empty configuration screen.",
    label: "Default policy",
    value: "Digital services protection",
  },
  {
    eyebrow: "Setup complete",
    title: "Everything important stays verifiable.",
    copy: "Track settlement, inspect policy terms, and recompute dispute outcomes from the workspace you just created.",
    label: "Network",
    value: "Arc Testnet ready",
  },
];

export function OnboardingPage() {
  const router = useRouter();
  const { account, loading } = useSession();
  const [step, setStep] = useState(0);
  const [role, setRole] = useState<RecourseRole>("merchant");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [workspace, setWorkspace] = useState("");

  // Onboarding requires an account; identity (name, email) is seeded from the signed-in
  // provider, while role and workspace are local workspace preferences.
  useEffect(() => {
    if (loading) return;
    if (!account) {
      router.replace("/signin");
      return;
    }
    const profile = readDemoProfile();
    setRole(profile.role === "liquidity" ? "liquidity" : "merchant");
    setFirstName(account.givenName ?? profile.firstName);
    setLastName(account.familyName ?? profile.lastName);
    setEmail(account.email ?? profile.email);
    setWorkspace(profile.workspace || defaultDemoProfile.workspace);
  }, [account, loading, router]);

  function persist(nextStep: number) {
    saveDemoProfile({ firstName, lastName, email, role, workspace, onboardingComplete: nextStep === 3 });
    setStep(nextStep);
  }

  function submitProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    persist(2);
  }

  function finish() {
    saveDemoProfile({ firstName, lastName, email, role, workspace, onboardingComplete: true });
    router.push("/dashboard");
  }

  const preview = previewContent[step];

  return (
    <main className="onboarding-page">
      <header className="onboarding-topbar">
        <Link href="/" className="auth-brand"><BrandMark /><span>Recourse</span></Link>
        <span className="onboarding-secure"><LockKeyhole size={14} /> Secure testnet setup</span>
      </header>

      <div className="onboarding-layout">
        <section className="onboarding-content">
          {step === 0 && (
            <div className="onboarding-card">
              <span className="onboarding-step">Step 1 of 4</span>
              <h1>How will you use Recourse?</h1>
              <p>Choose your first workspace. You can add another role later.</p>
              <div className="role-grid">
                {roles.map((item) => {
                  const Icon = item.icon;
                  return (
                    <button className={role === item.id ? "selected" : ""} onClick={() => setRole(item.id)} key={item.id}>
                      <span className="role-icon"><Icon size={21} /></span>
                      <span><strong>{item.title}</strong><small>{item.copy}</small></span>
                      <span className="role-check">{role === item.id && <Check size={14} />}</span>
                    </button>
                  );
                })}
              </div>
              <p className="onboarding-mobile-note"><Smartphone size={15} /> Buying on Recourse? The buyer experience lives in the mobile app.</p>
              <button className="onboarding-primary" onClick={() => persist(1)}>Continue as {roles.find((item) => item.id === role)?.title} <ArrowRight size={16} /></button>
              <p className="developer-note"><Code2 size={15} /> Building an integration? <a href="https://github.com/frankolien/recourse" target="_blank" rel="noreferrer">Open developer docs</a>.</p>
            </div>
          )}

          {step === 1 && (
            <form className="onboarding-card" onSubmit={submitProfile}>
              <button className="onboarding-back" type="button" onClick={() => setStep(0)}><ArrowLeft size={15} /> Back</button>
              <span className="onboarding-step">Step 2 of 4</span>
              <h1>Tell us about yourself</h1>
              <p>This is how your name and account details appear in Recourse.</p>
              <div className="onboarding-fields two-columns">
                <label><span>First name</span><input required value={firstName} onChange={(event) => setFirstName(event.target.value)} /></label>
                <label><span>Last name</span><input required value={lastName} onChange={(event) => setLastName(event.target.value)} /></label>
              </div>
              <div className="onboarding-fields">
                <label><span>Email address</span><input required type="email" value={email} onChange={(event) => setEmail(event.target.value)} /></label>
              </div>
              <button className="onboarding-primary" type="submit">Continue <ArrowRight size={16} /></button>
            </form>
          )}

          {step === 2 && (
            <div className="onboarding-card">
              <button className="onboarding-back" onClick={() => setStep(1)}><ArrowLeft size={15} /> Back</button>
              <span className="onboarding-step">Step 3 of 4</span>
              <h1>{role === "merchant" ? "Set up your business workspace" : role === "liquidity" ? "Set up your vault workspace" : "Your Recourse wallet is ready"}</h1>
              <p>{role === "merchant" ? "Choose where protected payments and settlements will be managed." : role === "liquidity" ? "Review the testnet vault before supplying any liquidity." : "A testnet account is ready. Connect a wallet when you want to make an onchain transaction."}</p>

              <div className="setup-summary">
                <div className="setup-icon">{role === "merchant" ? <BriefcaseBusiness size={25} /> : role === "liquidity" ? <Landmark size={25} /> : <Wallet size={25} />}</div>
                <div><span>{role === "merchant" ? "Business workspace" : role === "liquidity" ? "Vault workspace" : "Recourse account"}</span><strong>{workspace}</strong><small>Arc Testnet · Demo mode</small></div>
                <span className="setup-ready"><Check size={13} /> Ready</span>
              </div>

              <div className="onboarding-fields">
                <label><span>Workspace name</span><input value={workspace} onChange={(event) => setWorkspace(event.target.value)} /></label>
              </div>

              <div className="setup-options">
                {role === "merchant" && <><button><Landmark size={18} /><span><strong>Recourse settlement wallet</strong><small>Recommended for the prototype</small></span><span className="recommended">Recommended</span></button><button><ShieldCheck size={18} /><span><strong>Digital services policy</strong><small>Full refund when access is not delivered</small></span><ChevronRight size={16} /></button></>}
                {role === "liquidity" && <><button><Landmark size={18} /><span><strong>Settlement vault</strong><small>Review utilization and outstanding exposure</small></span><ChevronRight size={16} /></button><button><Wallet size={18} /><span><strong>Connect funding wallet</strong><small>Needed before a testnet deposit</small></span><ChevronRight size={16} /></button></>}
              </div>
              <button className="onboarding-primary" onClick={() => persist(3)}>Continue <ArrowRight size={16} /></button>
            </div>
          )}

          {step === 3 && (
            <div className="onboarding-card onboarding-complete">
              <div className="complete-mark"><Sparkles size={28} /></div>
              <span className="onboarding-step">Setup complete</span>
              <h1>You are ready, {firstName}.</h1>
              <p>{role === "merchant" ? "Publish a protection policy, accept USDC, and track instant settlement from your workspace." : role === "liquidity" ? "Review vault health, yield sources, and exposure before making a testnet deposit." : "Review protection before paying, follow every active payment, and verify any outcome independently."}</p>
              <div className="complete-flow">
                <span><Check size={14} /> Account created</span>
                <i />
                <span><Check size={14} /> Workspace ready</span>
                <i />
                <span><Check size={14} /> Arc Testnet</span>
              </div>
              <button className="onboarding-primary" onClick={finish}>Go to dashboard <ArrowRight size={16} /></button>
            </div>
          )}
        </section>

        <aside className="onboarding-preview">
          <div className="onboarding-preview-ui" aria-hidden="true">
            <div className="preview-ui-top"><span /><span /><span /></div>
            <div className="preview-ui-grid">
              <div className="preview-ui-card wide"><small>Protected volume</small><strong>$464.00</strong><i /></div>
              <div className="preview-ui-card"><small>Active</small><strong>3</strong><i /></div>
              <div className="preview-ui-card"><small>Settled</small><strong>T+0</strong><i /></div>
              <div className="preview-ui-table"><i /><i /><i /><i /></div>
            </div>
          </div>
          <article className="onboarding-proof-card">
            <span className="onboarding-proof-kicker"><ShieldCheck size={14} /> {preview.eyebrow}</span>
            <h2>{preview.title}</h2>
            <p>{preview.copy}</p>
            <div className="onboarding-proof-fact">
              <span><Landmark size={17} /></span>
              <div><small>{preview.label}</small><strong>{preview.value}</strong></div>
            </div>
          </article>
          <div className="onboarding-preview-progress" aria-label={`Step ${step + 1} of 4`}>
            {[0, 1, 2, 3].map((index) => <span className={index <= step ? "active" : ""} key={index} />)}
            <small>{step + 1} / 4</small>
          </div>
        </aside>
      </div>
    </main>
  );
}
