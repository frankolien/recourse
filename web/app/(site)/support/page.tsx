import type { Metadata } from "next";
import { Mail } from "lucide-react";

export const metadata: Metadata = {
  title: "Support",
  description: "Help with the Recourse iOS app.",
};

const faqs = [
  {
    question: "What is Recourse?",
    answer:
      "An iOS money app for USDC on Arc, Circle's blockchain. You send dollars by @handle, request money by name, write cheques the other person cashes later, convert between USDC and EURC, and put idle dollars into Earn.",
  },
  {
    question: "Is my money safe?",
    answer:
      "Your account is a 2-of-3 smart account on Arc. Your phone's Secure Enclave and your iCloud key sign together, and a sealed recovery key brings the account back on a new phone. No single key we hold can spend. The chain enforces it, not us.",
  },
  {
    question: "Which network is it on?",
    answer:
      "Arc testnet today, so every balance is test money with no monetary value. Mainnet when Arc's mainnet money exists.",
  },
];

export default function SupportPage() {
  return (
    <div className="site-wrap site-support">
      <h1 className="site-h1">Support</h1>
      <p className="site-sub">
        Recourse is in beta on Arc testnet. If something in the app looks wrong, or you want your data deleted, email us
        and a person will answer.
      </p>
      <a href="mailto:gkenny896@gmail.com" className="site-btn site-btn-primary">
        <Mail size={16} aria-hidden="true" />
        <span>Email support</span>
      </a>
      <section className="site-faq" aria-label="Frequently asked questions">
        {faqs.map(({ question, answer }) => (
          <div key={question} className="site-faq-item">
            <h2>{question}</h2>
            <p>{answer}</p>
          </div>
        ))}
      </section>
    </div>
  );
}
