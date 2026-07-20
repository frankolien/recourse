import {
  ArrowUpRight,
  Check,
  ChevronRight,
  CircleDollarSign,
  CircleHelp,
  ClipboardList,
  Cloud,
  Code2,
  FileCheck2,
  FileText,
  Headphones,
  Landmark,
  LockKeyhole,
  MessageCircle,
  PackageCheck,
  Send,
  Shield,
  ShieldCheck,
  Store,
  Zap,
} from "lucide-react";
import Link from "next/link";

const protections = [
  {
    merchant: "CloudCompute",
    product: "API Credits Pack",
    amount: "$24.00",
    units: "24.00 USDC",
    ends: "3 Aug 2026, 4:30 PM",
    remaining: "in 13 days",
    progress: 70,
    href: "/verify/5",
    icon: <Cloud size={18} />,
    tone: "cloud",
  },
  {
    merchant: "FileStore",
    product: "Pro Plan · Monthly",
    amount: "$120.00",
    units: "120.00 USDC",
    ends: "15 Aug 2026, 10:00 AM",
    remaining: "in 25 days",
    progress: 45,
    href: "/protection",
    icon: <FileText size={18} />,
    tone: "file",
  },
  {
    merchant: "DesignVault",
    product: "Premium Assets",
    amount: "$320.00",
    units: "320.00 USDC",
    ends: "28 Aug 2026, 11:59 PM",
    remaining: "in 38 days",
    progress: 30,
    href: "/protection",
    icon: <Zap size={18} />,
    tone: "design",
  },
];

const activities = [
  { icon: <PackageCheck size={15} />, title: "Payment to CloudCompute", detail: "", time: "20 Jul, 11:42 AM", tone: "soft" },
  { icon: <Check size={15} />, title: "Merchant paid instantly", detail: "CloudCompute", time: "20 Jul, 11:42 AM", tone: "green" },
  { icon: <ShieldCheck size={15} />, title: "Protection activated", detail: "Order #RC-281", time: "20 Jul, 11:42 AM", tone: "soft" },
  { icon: <ClipboardList size={15} />, title: "Evidence requested", detail: "Order #RC-284", time: "20 Jul, 9:18 AM", tone: "orange" },
  { icon: <Landmark size={15} />, title: "Deposit to vault", detail: "", time: "19 Jul, 6:01 PM", tone: "gray" },
];

const learnCards = [
  { icon: <FileCheck2 size={21} />, title: "How protection works", copy: "Understand policies, escrow and disputes", href: "/policies" },
  { icon: <Store size={21} />, title: "For merchants", copy: "Get paid instantly while buyers stay protected", href: "/vault" },
  { icon: <Code2 size={21} />, title: "For developers", copy: "Integrate Recourse into your app", href: "https://github.com/frankolien/recourse" },
  { icon: <LockKeyhole size={21} />, title: "Security and audits", copy: "Built on Arc with best in class security", href: "/verify/5" },
];

export function DashboardPage() {
  return (
    <>
      <header className="dash-header">
        <div>
          <h1>Good morning, Frank <span>👋</span></h1>
          <p>Here is what is happening with your protected payments.</p>
        </div>
      </header>

      <section className="summary-grid">
        <article className="balance-card">
          <div className="summary-label">USDC Balance <CircleHelp size={13} /></div>
          <strong>$2,480.50</strong>
          <span>2,480.50 USDC</span>
          <div className="balance-actions">
            <button><Send size={13} /> Send</button>
            <button>Receive</button>
            <button>Pay</button>
          </div>
        </article>

        <Link className="summary-card protected-summary" href="/protection">
          <div className="summary-label">Protected Payments</div>
          <strong><em>3</em> active</strong>
          <b>$640.00 <span>protected</span></b>
          <p>Across 3 merchants</p>
          <div className="summary-icon green"><ShieldCheck size={21} /></div>
        </Link>

        <Link className="summary-card action-summary" href="/disputes">
          <div className="summary-label">Action Needed</div>
          <strong><em>1</em></strong>
          <b>Evidence required</b>
          <p>Order #RC-284</p>
          <div className="summary-icon orange"><ClipboardList size={21} /></div>
        </Link>

        <Link className="summary-card spent-summary" href="/payments">
          <div className="summary-label">Total Spent <ArrowUpRight size={14} /></div>
          <strong>$1,240.00</strong>
          <p>This month</p>
          <svg viewBox="0 0 180 52" aria-label="Spending trend" className="sparkline">
            <defs>
              <linearGradient id="sparkFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stopColor="#0d7656" stopOpacity=".16" />
                <stop offset="1" stopColor="#0d7656" stopOpacity="0" />
              </linearGradient>
            </defs>
            <path d="M0 47 C14 31 22 47 34 43 S51 14 67 24 S80 42 94 32 S111 38 122 25 S142 29 153 17 S166 8 180 2 L180 52 L0 52Z" fill="url(#sparkFill)" />
            <path d="M0 47 C14 31 22 47 34 43 S51 14 67 24 S80 42 94 32 S111 38 122 25 S142 29 153 17 S166 8 180 2" fill="none" stroke="#0d7656" strokeWidth="2" />
          </svg>
        </Link>
      </section>

      <div className="dash-content-grid">
        <div className="dash-primary-column">
          <section className="dash-panel protections-panel">
            <div className="panel-heading">
              <div><h2>Active protections</h2><p>Payments currently protected by Recourse</p></div>
              <Link href="/protection">View all protections</Link>
            </div>
            <div className="protection-table">
              <div className="protection-head">
                <span>Merchant</span><span>Amount</span><span>Protection ends</span><span>Status</span><span>Progress</span><span />
              </div>
              {protections.map((item) => (
                <Link className="protection-row" href={item.href} key={item.merchant}>
                  <div className="merchant-cell"><span className={`merchant-icon ${item.tone}`}>{item.icon}</span><span><strong>{item.merchant}</strong><small>{item.product}</small></span></div>
                  <div><strong>{item.amount}</strong><small>{item.units}</small></div>
                  <div><strong>{item.ends}</strong><small>{item.remaining}</small></div>
                  <div><span className="active-status"><ShieldCheck size={14} /> Active</span></div>
                  <div className="progress-cell"><span><i style={{ width: `${item.progress}%` }} /></span><small>{item.progress}% of window</small></div>
                  <ChevronRight size={16} />
                </Link>
              ))}
            </div>
          </section>

          <section className="dash-panel disputes-panel">
            <div className="panel-heading compact">
              <div><h2>Disputes</h2><p>Track and resolve issues with your protected payments</p></div>
              <Link href="/disputes">View all disputes</Link>
            </div>
            <Link className="dispute-row" href="/disputes">
              <div className="dispute-order"><span className="dispute-icon"><LockKeyhole size={17} /></span><div><strong>Order #RC-284</strong><small>vs MegaStore</small><b>Evidence required</b></div></div>
              <div className="dispute-info"><span>Issue</span><strong>Service was not delivered</strong><small>Requested on<br />20 Jul 2026, 9:18 AM</small></div>
              <div className="dispute-info due"><span>Evidence due</span><strong>Today, 5:00 PM</strong><small>in 5h 42m</small></div>
              <div className="dispute-timeline">
                <div className="timeline-line"><i className="done" /><i className="review" /><i /><i /></div>
                <div className="timeline-labels"><span><b>Submitted</b><small>20 Jul, 9:18 AM</small></span><span><b>Under review</b><small>Waiting for evidence</small></span><span><b>Decision</b><small>Pending</small></span><span><b>Resolved</b><small>Pending</small></span></div>
              </div>
            </Link>
          </section>

          <section className="learn-section">
            <h2>Learn about Recourse</h2>
            <div className="learn-grid">
              {learnCards.map((item) => (
                item.href.startsWith("http")
                  ? <a key={item.title} href={item.href} target="_blank" rel="noreferrer"><span>{item.icon}</span><div><strong>{item.title}</strong><p>{item.copy}</p></div></a>
                  : <Link key={item.title} href={item.href}><span>{item.icon}</span><div><strong>{item.title}</strong><p>{item.copy}</p></div></Link>
              ))}
            </div>
          </section>
        </div>

        <aside className="dash-right-rail">
          <section className="dash-panel activity-panel">
            <div className="panel-heading compact"><h2>Recent activity</h2><Link href="/payments">View all</Link></div>
            <div className="activity-list">
              {activities.map((item, index) => (
                <div className="activity-item" key={`${item.title}-${index}`}>
                  <span className={`activity-icon ${item.tone}`}>{item.icon}</span>
                  <div><strong>{item.title}</strong>{item.detail && <small>{item.detail}</small>}</div>
                  <time>{item.time}</time>
                </div>
              ))}
            </div>
          </section>

          <section className="dash-panel earnings-panel">
            <div className="panel-heading compact"><h2>Escrow earnings</h2><Link href="/vault">View details</Link></div>
            <div className="earnings-grid">
              <div><span>Total escrowed</span><strong>$640.00 USDC</strong></div>
              <div><span>Earnings (est.)</span><strong className="green-text">$1.24 USDC</strong></div>
              <div><span>Yield source</span><b><CircleDollarSign size={13} /> USYC</b></div>
              <div><span>Since</span><strong>20 Jul 2026</strong></div>
            </div>
          </section>

          <section className="support-panel">
            <div><h2>Need help with a payment?</h2><p>Our support team is here to help you resolve issues quickly and fairly.</p><Link href="/support" className="support-cta">Contact support</Link></div>
            <div className="support-art"><MessageCircle size={29} /><Headphones size={58} /><Shield size={28} /></div>
          </section>
        </aside>
      </div>
    </>
  );
}
