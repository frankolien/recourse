import {
  ArrowUpRight,
  Braces,
  FileCheck2,
  Mail,
  ShieldCheck,
} from "lucide-react";
import Link from "next/link";

const faqs = [
  { q: "Who decides my refund?", a: "No one. A deterministic policy engine runs the refund rules onchain. The same engine runs in your browser on the public verifier, so you can recompute the result yourself." },
  { q: "When does the merchant get paid?", a: "Instantly. The settlement vault fronts the merchant at T plus 0 from escrow, then is repaid when the dispute window closes." },
  { q: "What evidence can I submit?", a: "Photos, a written description, tracking, or video. Each rule declares the evidence it needs, and the policy checks it against your claim." },
  { q: "Where do escrowed funds sit?", a: "In a yield-bearing USYC position. Funds earn while protected, and the yield is split between you and the protocol treasury." },
];

const resources = [
  { title: "How verification works", copy: "Recompute any verdict from live Arc data", href: "/verify/5", icon: <FileCheck2 size={18} />, external: false },
  { title: "Policy reference", copy: "Read the rules pinned to your payments", href: "/policies", icon: <ShieldCheck size={18} />, external: false },
  { title: "Developer docs", copy: "Integrate Recourse into your app", href: "https://github.com/frankolien/recourse", icon: <Braces size={18} />, external: true },
];

export function SupportPage() {
  return (
    <div className="page-stack">
      <header className="dash-header">
        <div>
          <h1>Support</h1>
          <p>Answers first, humans second. Most questions resolve the same way a verdict does: transparently.</p>
        </div>
      </header>

      <div className="two-col">
        <section className="dash-panel">
          <div className="panel-heading compact"><h2>Frequently asked</h2></div>
          <div className="faq-list">
            {faqs.map((item) => (
              <div className="faq-item" key={item.q}>
                <strong>{item.q}</strong>
                <p>{item.a}</p>
              </div>
            ))}
          </div>
        </section>

        <div className="page-stack">
          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Contact us</h2></div>
            <p style={{ margin: "0 0 14px", color: "#5c6663", fontSize: 13, lineHeight: 1.55 }}>
              Stuck on a payment or a dispute? Send the order id and we will look at the onchain record with you.
            </p>
            <a className="page-cta" href="mailto:support@recourse.demo"><Mail size={15} /> Email support</a>
          </section>

          <section className="dash-panel">
            <div className="panel-heading compact"><h2>Resources</h2></div>
            <div className="resource-list">
              {resources.map((item) => (
                item.external
                  ? <a className="resource-item" href={item.href} target="_blank" rel="noreferrer" key={item.title}><span>{item.icon}</span><div><strong>{item.title}</strong><small>{item.copy}</small></div><ArrowUpRight size={15} /></a>
                  : <Link className="resource-item" href={item.href} key={item.title}><span>{item.icon}</span><div><strong>{item.title}</strong><small>{item.copy}</small></div><ArrowUpRight size={15} /></Link>
              ))}
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}
